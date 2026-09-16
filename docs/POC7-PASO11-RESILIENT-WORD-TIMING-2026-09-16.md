# POC7 Paso 11 — Timing invertido a nivel palabra: no debe tirar la ventana completa

**Fecha:** 2026-09-16
**Rama:** `poc7-paso11-resilient-word-timing` (crear con `git checkout -b poc7-paso11-resilient-word-timing` desde `poc7-paso10-drop-own-recording`, commit `8ed4acf`)
**Estado:** Cambio aplicado en disco. **Sin commitear. Sin re-validar con una corrida real.**

## Contexto: Paso 10 ya quedó validado (capítulo cerrado)

La corrida real de `dotnet run` del Paso 10 (con audio real sonando, whisper-server en `127.0.0.1:8080`) confirmó que quitar la grabación propia no rompió nada:

- `Jobs producidos: 32` = exactamente lo esperado para 130s con ventana 5s/paso 4s.
- `Contabilidad: 32 = 32 + 0 + 0 | OK`, `Capacidad máxima: 1 <= 3 | OK`.
- `Stop reason: Normal`, `Capture exception: null`, `Reconexiones intentadas: 0` (no hizo falta el watchdog).
- 271 palabras reconstruidas, orden temporal OK, 0 IDs duplicados.

El resultado final dio `POC 7 Paso 10 FAIL`, pero **no por el cambio de Paso 10** — fue por un bug preexistente y no relacionado, descrito abajo. Arquitectónicamente, Paso 10 (transcripción sin grabación propia) está confirmado como correcto.

## El bug real: timing invertido a nivel palabra tira toda la ventana

En esa misma corrida, 2 de 32 ventanas (#12 y #27) fallaron con:

```
Inverted whisper-server word timing for ' Dr': 1 > 0.4.
Inverted whisper-server word timing for ' We': 1 > 0.42.
```

Este es el bug de timing que ya estaba anotado desde antes de este proyecto ("Inverted whisper-server word timing..." mencionado en la auditoría original). Causa raíz: `whisper-server` ocasionalmente devuelve una palabra individual con `end < start` (empieza después de que termina) — parece afectar sobre todo fragmentos cortos. `Convert-WhisperServer.ps1` (línea ~88) reaccionaba con `throw`, lo cual abortaba la conversión de **toda la respuesta HTTP**, perdiendo también las 10-20 palabras buenas de esa ventana.

## Fix aplicado

Archivo: `src/Import/Convert-WhisperServer.ps1`

```diff
             if ($to -lt $from) {
-                throw "Inverted whisper-server word timing for '$text': $from > $to."
+                Write-Warning "Skipping word with inverted whisper-server timing for '$text': $from > $to."
+                continue
             }
```

En vez de tirar toda la ventana, descarta solo la palabra individual con timing inválido y sigue procesando el resto. El guard existente `if ($tokens.Count -eq 0) { throw "whisper-server JSON contains no usable word units." }` sigue protegiendo el caso de que una ventana quede completamente vacía.

**Alcance deliberadamente mínimo:** no se tocaron las otras validaciones de la misma función (timing de segmento invertido, NaN, negativos, campos faltantes) porque no hay evidencia de que esas fallen en la práctica — solo se corrigió exactamente el caso que se observó fallar en una corrida real, siguiendo la disciplina de "evidencia antes que la solución" de `AGENTS.md`.

## Pendiente / próximos pasos (empezar por aquí mañana)

1. Crear la rama (si no existe ya) y confirmar:
   ```powershell
   cd C:\Users\Enrique\whisper-reconstruction
   git checkout -b poc7-paso11-resilient-word-timing
   git status   # debe mostrar src/Import/Convert-WhisperServer.ps1 modificado
   ```
2. Levantar whisper-server:
   ```powershell
   cd C:\whisper.cpp
   .\build-server-test\bin\Release\whisper-server.exe `
     -m "C:\whisper.cpp\ggml-large-v3-turbo-q5_0.bin" `
     --host 127.0.0.1 `
     --port 8080
   ```
3. En otra ventana, con audio real sonando por el sistema:
   ```powershell
   cd C:\Users\Enrique\whisper-reconstruction
   dotnet run --project AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
   ```
4. Verificar en la salida:
   - `Windows convertidas` debería subir a 32 (o acercarse, si no hay más timing invertido en esa corrida específica — el bug es probabilístico, no determinístico, así que puede que una corrida nueva no lo dispare en absoluto).
   - Confirmar que aparecen líneas `WARNING: Skipping word with inverted whisper-server timing...` en la consola si el bug se repite, en vez de `INFERENCE EXCEPTION`.
   - Ver si `POC 7 Paso 10 PASS` finalmente (el texto del veredicto todavía dice "Paso 10" en el código; son cambios acumulativos sobre el mismo binario).
5. Si sale bien: commitear y empujar:
   ```powershell
   git add src/Import/Convert-WhisperServer.ps1
   git commit -m "Skip words with inverted whisper-server timing instead of failing the whole window"
   git push origin poc7-paso11-resilient-word-timing
   ```
6. Decidir si mergear `poc7-paso10-drop-own-recording` + `poc7-paso11-resilient-word-timing` de vuelta a `poc7-paso6-temporal-guard-clean` como la rama consolidada, o seguir apilando POCs.

## Después de esto (Fase 1 del producto, la pieza grande que falta)

Con Paso 10 y Paso 11 cerrados, la transcripción en vivo (sin grabación propia, resistente a datos sucios de whisper-server) debería estar sólida. La siguiente prioridad grande, ya anotada en `docs/POC7-PASO10-DROP-OWN-RECORDING-2026-09-16.md`, es la **reconstrucción incremental real**: hoy `Reconstruct-WhisperWindows` corre en batch al final de la sesión completa (un solo proceso PowerShell reconstruye todo el corpus). Para "casi tiempo real" tipo Parakeet, el transcript debe irse actualizando mientras se habla, no solo al final. Esa es la siguiente conversación a tener, después de cerrar este paso.

Fase 2 (asistente de IA para participaciones en clase) sigue sin empezar — está condicionada a que la Fase 1 quede cerrada, según `docs/MVP-STATE-INVENTORY-2026-09-14.md`.
