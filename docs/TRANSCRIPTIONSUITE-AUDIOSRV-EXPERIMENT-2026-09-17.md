# TRANSCRIPTIONSUITE AUDIOSRV EXPERIMENT

**Fecha:** 2026-09-17  
**Rama:** `transcriptionsuite-adaptation`  
**Commit auditado:** `48ebc81176380aac09cdb8fd6341426603c33123`  
**Objetivo:** observar empíricamente qué ocurre con la captura real de audio de sistema de TranscriptionSuite en Windows durante `Restart-Service Audiosrv -Force`.

## 1. Baseline

Se ejecutó un harness local fuera del repositorio bajo `C:\Users\Enrique\AppData\Local\Temp\opencode\audiosrv-exp2.ps1`.

El harness de captura utiliza un `AudioWorklet` byte-idéntico al de TranscriptionSuite auditado, con SHA-256:

`317E379726F4CF53A3713682F9734554585302379C1ABAF1016DE7EF91CD09E1`

La adquisición usa `getDisplayMedia` y `setDisplayMediaRequestHandler` con `audio: 'loopback'`, replicando el mecanismo observado en TranscriptionSuite.

Electron utilizado: **33.4.11**. El proyecto declara Electron `^41.10.3`; esta diferencia queda como limitación del experimento.

Baseline observado durante aproximadamente 15.2 s:

- captura: `audio:live`
- sample rate: 48 kHz
- canales: mono
- chunks: 151
- frecuencia: aproximadamente 10 chunks/s
- `lastChunkAgeMs`: aproximadamente 18–58 ms
- `AudioContext`: `running`
- track: `live`
- eventos de lifecycle antes del restart: ninguno
- peak PCM: aproximadamente 870, confirmando que había señal audible real

**FACT:** antes del restart existía flujo PCM real y estable.

## 2. Audiosrv Restart

El comando ejecutado fue:

```powershell
Restart-Service Audiosrv -Force
```

Ventana observada:

- BEGIN: `19:58:40.988Z`
- END: `19:58:42.324Z`
- duración: `1332 ms`

Durante aproximadamente +0.3 a +0.9 s después del inicio del restart se observaron **6 eventos `devicechange`**:

- `19:58:41.295Z`
- `19:58:41.xxxZ`
- `19:58:41.xxxZ`
- `19:58:41.xxxZ`
- `19:58:41.xxxZ`
- `19:58:41.959Z`

El conteo exacto intermedio queda preservado en `driver.log` del run `20260917-135823`.

## 3. After Restart

El comportamiento posterior fue significativo:

- Los chunks **continuaron llegando**.
- La frecuencia permaneció aproximadamente entre 9 y 12 chunks/s.
- `lastChunkAgeMs` permaneció bajo, hasta aproximadamente 90 ms.
- Sin embargo, desde aproximadamente +1.6 s apareció `peak=0`.
- El flujo posterior correspondía a silencio digital, no a audio PCM utilizable.
- `AudioContext` permaneció `running`.
- `ctxChanges=0`.
- `muted=false`.
- No aparecieron errores de renderer ni excepciones.
- `track.onended` ocurrió en `19:58:55.356Z`, aproximadamente +14.4 s después del restart.
- En ese momento `MediaStreamTrack.readyState` pasó a `ended`.
- Después de `onended`, el flujo de chunks observado por el harness no constituyó una recuperación de la captura real: el recurso de captura había terminado y no se produjo una nueva adquisición.

El run alcanzó aproximadamente 87.0 s de observación total y registró 866 chunks.

**FACT:** comprobar solamente que siguen llegando chunks habría dado un falso negativo: el stream presentó un flujo de chunks aparentemente sano mientras el contenido ya era silencio digital (`peak=0`).

## 4. Detection

La inspección del código de TranscriptionSuite en `48ebc811` mostró que la capa de captura no registra handlers para:

- `MediaStreamTrack.onended`
- `MediaStreamTrack.onmute`
- `AudioContext.onstatechange`
- `devicechange`

Tampoco existe en `audioCapture.ts` un watchdog basado en recencia o contenido de chunks.

`useLiveMode.ts` tampoco introduce un monitor equivalente de recencia/contenido de la captura.

El evento `devicechange` observado durante el restart no produjo una recuperación de la captura.

**FACT:** el experimento no observó una ruta de detección explícita que convirtiera la pérdida de captura en un estado de fallo/recovery.

**INFERENCE:** para la aplicación, este fallo puede quedar enmascarado como ausencia de voz, porque VAD o la capa superior no reciben una señal inequívoca de que el dispositivo/captura ha muerto.

## 5. Recovery

No se observó ninguna recreación automática de:

- `getDisplayMedia()`;
- `MediaStream`;
- `MediaStreamTrack`;
- `AudioContext`;
- `AudioWorklet`;
- mecanismo loopback.

El `MediaStreamTrack` terminó en `readyState=ended` y no se observó una nueva adquisición que restableciera la captura.

**FACT:** no hubo recuperación automática observable durante el experimento.

**INFERENCE:** una estrategia de recuperación deberá contemplar la recreación de la captura, no solamente reanudar el procesamiento del stream existente.

## 6. Evidence

### Run

`C:\Users\Enrique\AppData\Local\Temp\opencode\audiosrv-exp2\20260917-135823`

Artefactos principales:

- `driver.log` — 20687 B
- `electron-out.log`
- `electron-err.log` — vacío

Limpieza posterior confirmada:

- Electron de prueba: detenido
- proceso de tono: detenido
- `Audiosrv`: `Running`
- no quedó reproducción de tono activa

Un supuesto proceso residual `powershell pid=18976` fue identificado como falso positivo del propio driver, porque su command line contenía `audiosrv-exp`; no correspondía a un proceso de prueba residual.

### Código observado

El análisis de `audioCapture.ts` y `useLiveMode.ts` de `48ebc811` no encontró handlers de lifecycle ni watchdog de chunks/contenido equivalentes al mecanismo de recuperación desarrollado en el POC NAudio.

### Criterio de interpretación

Se separaron explícitamente:

1. **flujo de chunks:** si el `AudioWorklet` sigue enviando buffers;
2. **contenido PCM utilizable:** si esos buffers contienen señal distinta de silencio digital;
3. **estado del recurso:** si el `MediaStreamTrack` sigue `live` o pasa a `ended`.

Esto evita interpretar "no hubo voz" como "no llegaron muestras".

## 7. Comparison With POC 9B-1

| Evento | POC / NAudio 9B-1 | TranscriptionSuite / Chromium |
|---|---|---|
| Antes del restart | captura PCM estable | captura PCM estable |
| `Restart-Service Audiosrv -Force` | sí | sí |
| Comportamiento inmediato | `DataAvailable` deja de producir datos | chunks continúan inicialmente |
| Señal posterior | 0 frames después de la pérdida | chunks de silencio (`peak=0`) |
| `RecordingStopped` / lifecycle | no hubo stop temprano utilizable como detector | `onended` llegó aproximadamente +14.4 s |
| Detección automática | no suficiente por `RecordingStopped`; POC posterior añadió watchdog | no se observó watchdog de contenido/lifecycle |
| Recreación de captura | añadida experimentalmente mediante watchdog/reconnect | no observada |
| Riesgo de falso negativo | pérdida visible como ausencia de frames | pérdida enmascarada por flujo de chunks silenciosos |

La diferencia principal no es que TranscriptionSuite haya evitado el fallo: el experimento muestra que el fallo puede presentarse como un **stream zombie de silencio**, que es más difícil de distinguir de una clase en silencio.

## 8. Conclusion

### 1. PCM utilizable

**FACT:** después de `Restart-Service Audiosrv -Force`, los chunks continuaron llegando aproximadamente a 9–12/s, pero el contenido pasó a `peak=0` aproximadamente +1.6 s después del restart. El `MediaStreamTrack` terminó posteriormente con `onended` y `readyState=ended` aproximadamente +14.4 s después.

**Conclusión:** no se mantuvo PCM utilizable de la captura original.

### 2. Detección

**FACT:** no se observó un watchdog de chunks/contenido ni consumo de `devicechange`/`onended` que disparara una recuperación en el código auditado.

**INFERENCE:** la pérdida puede quedar enmascarada como silencio normal para las capas superiores.

### 3. Recuperación

**FACT:** no se observó recreación automática de `getDisplayMedia`, `MediaStream` o `MediaStreamTrack` después del fallo.

**Conclusión:** no hubo recuperación automática durante este experimento.

### 4. Watchdog

**INFERENCE:** un watchdog de mera presencia de chunks no es suficiente. La prueba demuestra que pueden seguir llegando chunks mientras el contenido ya es silencio digital. La detección debería combinar señales de contenido y ciclo de vida del recurso, además de `devicechange` cuando corresponda.

### 5. Recreación de captura

**INFERENCE:** una recuperación robusta necesita contemplar la re-adquisición de la captura; reactivar únicamente el procesamiento de un track ya terminado no sería suficiente.

### 6. NAudio

**UNKNOWN:** este experimento por sí solo no demuestra que NAudio deba permanecer definitivamente en la arquitectura.

**INFERENCE:** eliminar NAudio todavía no es seguro para el MVP: antes habría que implementar y validar en la capa Web un mecanismo equivalente de detección + recuperación y repetir una prueba de este mismo tipo. Mientras eso no esté validado, NAudio continúa siendo la ruta de captura que ya dispone de watchdog/recreación experimental en el POC.

## Limitaciones

1. El experimento utilizó Electron **33.4.11**, mientras TranscriptionSuite declara `^41.10.3`. No se demuestra equivalencia exacta entre ambas versiones.
2. Se utilizó un harness de captura que replica las piezas relevantes (`getDisplayMedia`, handler de loopback y AudioWorklet), no el dashboard completo de TranscriptionSuite. Por tanto, el experimento demuestra el comportamiento de esa ruta de captura, no de todas las capas de la aplicación.
3. La evidencia de contenido PCM se basó en las métricas del harness, incluyendo `peak`, y no en una grabación persistente del experimento.

## Estado

**Experimento: CERRADO.**

No se modificó código fuente ni se escribieron artefactos en el repositorio como parte del experimento. Este documento registra posteriormente los resultados para continuar el trabajo arquitectónico en la rama `transcriptionsuite-adaptation`.
