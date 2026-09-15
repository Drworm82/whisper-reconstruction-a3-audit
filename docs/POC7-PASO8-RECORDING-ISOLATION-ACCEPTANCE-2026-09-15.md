# POC 7 — Paso 8: Recording Isolation Acceptance

## Estado

- Resultado: PASS
- Fecha: 2026-09-15
- Objetivo: demostrar que un fallo del ASR no puede detener ni corromper la grabación independiente de audio.
- Implementación probada: recording queue bounded + recording task independiente + session.wav.
- No se hizo commit como parte de esta prueba.

## Mecánica de la prueba

- Build OK.
- whisper-server persistente inicialmente.
- EndToEndPOC ejecutado durante 130 s.
- A aproximadamente t=85 s se terminó intencionalmente el whisper-server.
- ASR_KILLED=True.
- La aplicación llegó a shutdown normal.
- APP_EXITED=True.
- whisper-server fue restaurado posteriormente con la misma invocación y quedó escuchando nuevamente en 127.0.0.1:8080.

## Configuración

- WASAPI Loopback
- 48 kHz
- 2 canales
- 32-bit IEEE Float
- Ring buffer: 20 s
- Ventana: 5 s
- Overlap: 1 s
- Step: 4 s
- Cola ASR: capacidad 3 / DropOldest
- Recording queue: bounded, capacidad 8192

## Evidencia de captura

- Frames capturados: 6,240,000
- Bytes capturados: 49,920,000
- Duración calculada: 130.000 s
- Frames descartados del ring buffer: 5,280,000

Los frames descartados del ring buffer NO representan pérdida de grabación de session.wav; corresponden a la sobrescritura normal del buffer circular de 20 s.

## Evidencia de grabación

- recordingChunksProduced: 11,711
- recordingChunksWritten: 11,711
- recordingChunksDropped: 0
- recordingBytesProduced: 49,920,000
- recordingBytesWritten: 49,920,000
- recordingQueueMaxDepth: 7
- recordingTaskException: null
- session.wav: existe
- tamaño total del archivo WAV: 49,920,058 bytes
- bytes del chunk data: 49,920,000
- relación bytes escritos/capturados: 100 %
- duración WAV: 130.000 s
- Header: RIFF/WAVE
- fmt: size 18
- fact: size 4
- data: 49,920,000 bytes
- formato validado: 48 kHz / 2 canales / 32-bit float
- recordingWavFormatMatches: true
- recordingOk: true

Los 58 bytes adicionales del archivo corresponden al contenedor/header WAV; el bloque `data` contiene exactamente los 49,920,000 bytes de audio capturados.

## Evidencia de aislamiento ASR

- Jobs producidos: 32
- Jobs procesados: 32
- Jobs descartados: 0
- Jobs pendientes: 0
- Windows exitosas: 18
- Windows fallidas: 14
- Inference FAIL: 0
- Inference EXCEPTION: 14

- 13 excepciones correspondieron a conexiones rechazadas a 127.0.0.1:8080 después de matar whisper-server, en ventanas #19–#31.
- Hubo además una excepción aislada en #06 relacionada con un fallo del pipeline PowerShell/Convert (`exit code 1`, CLIXML).
- Estas excepciones quedaron contenidas por el catch por job.
- Ninguna de estas fallas produjo excepción del recording task.
- recordingChunksDropped permaneció en 0.
- recordingBytesWritten permaneció exactamente igual a totalBytesCaptured.

## Resultado de criterios de aceptación

| # | Criterio | Resultado | Valor / evidencia |
|---|---|---|---|
| 1 | Captura aproximadamente 130 s | PASS | 130.000 s |
| 2 | recordingChunksDropped == 0 | PASS | 0 |
| 3 | recordingTaskException == null | PASS | null |
| 4 | recordingBytesWritten == totalBytesCaptured | PASS | 49,920,000 == 49,920,000 |
| 5 | session.wav existe y tiene header/formato válido | PASS | RIFF/WAVE, fmt 18, fact 4, data 49,920,000 |
| 6 | Grabación conserva los bytes pese al fallo ASR | PASS | 100 % |
| 7 | Terminación normal | PASS | APP_EXITED=True |
| 8 | recordingOk == true | PASS | true |
| 9 | Fallo ASR ≠ fallo recorder | PASS | 14 fallos ASR, recorder OK, 0 drops |
| 10 | El veredicto no puede ser PASS si recordingOk es false | PASS | el criterio final ya incluye recordingOk |

## Veredicto

POC 7 Paso 8 — PASS

El `FAIL` impreso por el ejecutable durante esta prueba fue esperado porque `inferenceOk=false` como consecuencia directa del fail-injection del ASR. No debe interpretarse como fallo de Paso 8.

Se registraron los valores:

- captureOk=true
- queueOk=true
- inferenceOk=false
- recordingOk=true

El objetivo específico de Paso 8, la supervivencia y conservación íntegra de la grabación ante fallo del ASR, fue demostrado.

## Observación

Como observación separada, SIN modificarla:

El scheduler todavía realiza I/O para los WAV de ventana (`BuildWavAsync` / `File.WriteAllBytesAsync`). Esto no fue objeto de esta prueba y no invalida el aislamiento demostrado entre recording task y ASR. No debe convertirse esta observación en un fallo de Paso 8.

El texto del veredicto del ejecutable todavía dice "POC 7 Paso 5" aunque esta aceptación corresponde a Paso 8. Es una inconsistencia de nomenclatura pendiente, no un fallo de la prueba.

## Estado del repositorio

- Solo `AudioCapturePOC/EndToEndPOC/Program.cs` permanece como modificación tracked.
- Los demás elementos untracked ya existían antes de la prueba.
- No hubo git add.
- No hubo commit.
- No hubo git clean.
- No hubo modificaciones durante la prueba.
- whisper-server quedó restaurado.