# POC 7 — Paso 9B-1: reinicio de Audiosrv durante captura

**Fecha:** 2026-09-15  
**Estado:** CLOSED — caracterización reproducible del comportamiento observado  
**Alcance:** endpoint WASAPI Loopback abierto + reinicio forzado de Windows Audio (`Audiosrv`)

## Objetivo

Provocar una condición que afecte al subsistema de audio mientras `EndToEndPOC` mantiene una captura WASAPI Loopback activa y observar si la captura continúa, se detiene, lanza una excepción y cómo queda la grabación.

Esta prueba sustituye al intento A→B descartado en Paso 9A: cambiar el dispositivo de salida predeterminado no se considera una invalidación fiable de un stream WASAPI ya abierto.

## Procedimiento

1. Se utilizó el endpoint previamente caracterizado: `Realtek Digital Output (Realtek(R) Audio)`.
2. Se inició `whisper-server` en `127.0.0.1:8080`.
3. Se inició `EndToEndPOC` con captura configurada a 48 kHz, 2 canales, IEEE Float de 32 bits.
4. La captura comenzó con audio real presente.
5. `Restart-Service Audiosrv` inicialmente falló porque el servicio tenía dependencias.
6. Se ejecutó `Restart-Service Audiosrv -Force` durante la captura activa.
7. No se realizó ninguna otra acción sobre el dispositivo durante la prueba.

## Resultado observado

El reinicio forzado de `Audiosrv` produjo una **interrupción efectiva de la captura**. El programa terminó su ciclo de captura aproximadamente a los **43.740 s**, en lugar de completar los 130 s configurados.

La salida de `EndToEndPOC` contiene:

- `ANTES DE STOP`
- `DESPUS DE STOP`
- `Captura detenida.`

No apareció texto de excepción en `poc9b-console-err.log`.

La captura registró:

| Métrica | Resultado |
|---|---:|
| Frames capturados | 2,099,520 |
| Bytes capturados | 16,796,160 |
| Duración calculada | 43.740 s |
| Frames descartados del ring | 1,139,520 |
| Recording chunks producidos | 4,094 |
| Recording chunks escritos | 4,094 |
| Recording chunks descartados | 0 |
| Recording bytes producidos | 16,796,160 |
| Recording bytes escritos | 16,796,160 |
| Recording task | OK |
| Expected WAV bytes | 16,796,160 |
| Actual WAV bytes | 16,796,160 |
| Duración WAV | 43.740 s |
| `recordingOk` | OK |

El worker ASR alcanzó únicamente las ventanas `#00` a `#09`. Se produjeron 10 jobs, se procesaron 10 y no hubo jobs descartados.

## Hechos establecidos

1. Con el stream WASAPI Loopback activo, el reinicio forzado de `Audiosrv` **sí cambió el comportamiento respecto de una ejecución normal**: la captura dejó de alcanzar los 130 s configurados.
2. La grabación no perdió datos dentro del intervalo efectivamente capturado: bytes producidos y escritos coinciden y `recordingOk` resultó `OK`.
3. No hubo drops en la cola de recording.
4. El worker ASR procesó correctamente los 10 jobs que llegaron a producirse antes de la parada.
5. `poc9b-console-err.log` quedó vacío; por tanto, esta evidencia **no demuestra por sí sola** que se haya propagado una excepción `AUDCLNT_E_DEVICE_INVALIDATED` al proceso.
6. Tampoco demuestra reconexión automática: la aplicación no continuó capturando después de la interrupción.

## Interpretación

La prueba demuestra una **interrupción del stream/ciclo de captura asociada temporalmente al reinicio de `Audiosrv`**. Esto confirma que el caso de pérdida del subsistema de audio es material para Paso 9.

La prueba no permite afirmar todavía cuál fue el mecanismo interno exacto (`RecordingStopped`, excepción WASAPI concreta, finalización inducida por el servicio u otra ruta de NAudio), porque el log de consola no registra una excepción explícita y el proceso concluyó de forma normal desde el punto de vista del cierre final.

## Decisión para Paso 9

**9B-1 CLOSED — evidencia válida de interrupción.**

No se implementa reconexión todavía. Antes de modificar producción, el siguiente análisis debe determinar qué señal/evento expone actualmente `WasapiLoopbackCapture` en este caso y si `Program.cs` distingue una parada normal de una pérdida de dispositivo/subsistema.

La implementación de reconexión automática queda pendiente de esa caracterización; no se infiere únicamente a partir de este experimento.
