# POC7 Paso 10 — Eliminar grabación propia (transcripción en vivo únicamente)

**Fecha:** 2026-09-16
**Rama:** `poc7-paso10-drop-own-recording` (creada desde `poc7-paso6-temporal-guard-clean` en el commit `10a78f0`)
**Estado:** Implementado, compila. **Pendiente de correr end-to-end con whisper-server real y de commitear.**

## Decisión de producto

El audio de la clase ya se captura y respalda por separado con **OBS Studio**, que graba en bloques de 2 minutos (protección contra corte/crash a mitad de sesión — igual que hacía `session.wav` en esta app, pero es responsabilidad de OBS ahora).

Por lo tanto, esta app **deja de tener responsabilidad de grabación/archivo**. Su único trabajo pasa a ser: transcribir en casi tiempo real. Sigue capturando audio del sistema vía WASAPI loopback (la misma fuente que OBS), en paralelo e independiente de OBS — son dos consumidores separados de la misma señal, sin que uno dependa del otro.

Se descartó leer el audio desde los archivos de 2 minutos de OBS como fuente para esta app porque introduciría hasta 2 minutos de retraso en la transcripción, incompatible con el objetivo de "casi tiempo real" (tipo Parakeet).

## Trabajo previo de consolidación (mismo día, antes de esto)

Antes de tocar `Program.cs` se resolvió una divergencia de ramas real (no solo documentada, verificada con evidencia):

- `poc7-paso6-temporal-guard-clean` (commit más reciente en GitHub, 2026-09-15) tiene el guard temporal integrado en `Reconstruct-WhisperWindows.ps1` y el flush final de palabras diferidas. Confirmada como la rama correcta.
- `reconstruction-fixes` y `poc7-paso6-temporal-guard` (sin "-clean") en GitHub están desactualizadas (últimos commits 2026-09-10/11): les falta el guard reubicado y el flush final.
- `AGENTS.md` y `docs/PROJECT-STATE.md` fueron corregidos: ya no apuntan a `reconstruction-fixes` como rama principal, apuntan a `poc7-paso6-temporal-guard-clean`.
- El escenario "MATCH posterior a un SIN MATCH" (que sí existía en `reconstruction-fixes`) se re-verificó contra `poc7-paso6-temporal-guard-clean` corriendo `tests/Test-Issue1-E1-PosteriorMatch.Tests.ps1` — pasa. Nota: ese archivo no es un test Pester real (no usa `Describe`/`It`/`Should`), es un script con aserciones caseras (`Write-Host "[OK]"`); Pester lo ejecuta pero reporta `0/0/0/0/0` porque no encuentra bloques formales. Esto aplica probablemente a buena parte de `tests/` — pendiente de limpieza, no bloqueante.
- Se commiteó y empujó a `origin/poc7-paso6-temporal-guard-clean` también el trabajo de Paso 8 (aislamiento de grabación) que había quedado sin commitear desde el día anterior.

## Cambios hechos en `AudioCapturePOC/EndToEndPOC/Program.cs`

Eliminado (ya no es responsabilidad de esta app):
- `RecordingQueueCapacity`, la cola `recordingQueue` (`BlockingCollection<byte[]>`) y sus contadores (`recordingChunksProduced/Written/Dropped`, `recordingBytesProduced/Written`, `recordingQueueMaxDepth`).
- Las funciones `UpdateRecordingQueueMaxDepth` y `TryEnqueueRecording`.
- `sessionWavPath` y el `recordingTask` que escribía `session.wav` con `WaveFileWriter`.
- El bloque completo `=== RESULTADO GRABACIÓN ===` y la variable `recordingOk`.
- El `using System.Collections.Concurrent;` (ya no se usa nada de ese namespace).

Conservado sin cambios (sigue siendo necesario):
- Captura WASAPI loopback, ring buffer, scheduler de ventanas, cola de inferencia, whisper-server, conversión y reconstrucción.
- **Watchdog y reconexión (Paso 8) intactos** — ahora protegen la continuidad de la *transcripción en vivo*, no una grabación de archivo.
- Los WAV pequeños por ventana en `audit-audio/window-NN.wav` (son para depuración del pipeline de ASR, no una grabación de sesión completa; se pueden quitar después si se quiere, no se tocaron).

Cosmético:
- El banner de consola decía "Paso 5"; se actualizó a "Paso 10".
- La línea final de veredicto ya no incluye `recordingOk` en la condición de PASS/FAIL.

## Build

```
dotnet build AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

Compiló correctamente, 21 advertencias (no revisadas en detalle todavía — pendiente confirmar que ninguna sea nueva/relevante a este cambio).

## whisper-server (confirmado 2026-09-16)

```powershell
cd C:\whisper.cpp
.\build-server-test\bin\Release\whisper-server.exe `
  -m "C:\whisper.cpp\ggml-large-v3-turbo-q5_0.bin" `
  --host 127.0.0.1 `
  --port 8080
```

Escucha en `http://127.0.0.1:8080/inference` — coincide con `WhisperServerUrl` en `Program.cs`. (Nota: contexto de sesiones anteriores mencionaba el puerto 8081; el puerto vigente confirmado por Enrique y usado en el código es **8080**.)

## Pendiente / próximos pasos

1. Con whisper-server corriendo (comando arriba), correr:
   ```
   dotnet run --project AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
   ```
   (~130s). Revisar especialmente `=== RESULTADO CAPTURA ===`, `=== RESULTADO COLA ===`, `=== CONVERT -> BUILD -> RECONSTRUCT ===` y el veredicto final `POC 7 Paso 10 PASS/FAIL`.
2. Si pasa: commitear en `poc7-paso10-drop-own-recording` y decidir si se mergea a `poc7-paso6-temporal-guard-clean` o se deja como rama separada hasta validar más.
3. Siguiente prioridad grande de producto (Fase 1, después de cerrar esto): **reconstrucción incremental real** — hoy `Reconstruct-WhisperWindows` se invoca en batch al final de la sesión completa (un solo proceso PowerShell reconstruye todo el corpus). Para "casi tiempo real" tipo Parakeet, el transcript debe irse actualizando mientras se habla, no solo al final.
4. Fase 2 (asistente de IA para participaciones en clase) — no empieza hasta que la Fase 1 (transcripción en vivo confiable) esté cerrada, según `docs/MVP-STATE-INVENTORY-2026-09-14.md`.
