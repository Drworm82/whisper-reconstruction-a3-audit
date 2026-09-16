# POC 7 — Paso 9A: Device Change / Endpoint Behavior Audit

**Fecha:** 2026-09-15  
**Estado:** CLOSED — characterization only  
**Scope:** observación del comportamiento actual, sin cambios de implementación

## Objetivo

Caracterizar qué ocurre con la captura WASAPI loopback existente cuando el endpoint de audio utilizado por la captura es deshabilitado y posteriormente habilitado mediante PnP.

Esta prueba **no implementa reconexión automática** ni pretende demostrar que el problema de cambio de dispositivo esté resuelto.

## Entorno

- Endpoint capturado: `Realtek Digital Output (Realtek(R) Audio)`
- Endpoint ID: `{0.0.0.00000000}.{f961f6d7-ccf4-4c01-9b9b-8e5919b590eb}`
- Formato: 32-bit IEEE Float, 48 kHz, 2 canales
- Bytes por frame: 8
- Duración configurada: 130 s
- whisper-server activo durante la prueba

## Procedimiento

1. Se inició `whisper-server` con el modelo `ggml-large-v3-turbo-q5_0.bin`.
2. Se inició `EndToEndPOC` capturando el endpoint Realtek Digital Output mediante `WasapiLoopbackCapture`.
3. Durante la ejecución se deshabilitó el endpoint mediante `Disable-PnpDevice` aproximadamente en t=40–43 s.
4. El endpoint permaneció deshabilitado hasta aproximadamente t=78–79 s.
5. Se volvió a habilitar el endpoint.
6. La aplicación se dejó terminar normalmente al alcanzar su duración configurada.

## Observaciones y evidencia

### FACT — la captura no se interrumpió

`DataAvailable` continuó llegando mientras el endpoint estaba marcado como `Error` por PnP. `RecordingStopped` no se disparó durante la deshabilitación; ocurrió únicamente durante el `StopRecording` normal al finalizar la ejecución.

El `session.wav` continuó creciendo durante la prueba.

### FACT — el recorder sobrevivió sin pérdidas de chunks

- Chunks producidos: 11,468
- Chunks escritos: 11,468
- Chunks descartados: 0
- Bytes producidos: 49,900,800
- Bytes escritos: 49,900,800
- Máxima profundidad de recording queue: 7
- `recordingTaskException`: null
- `recordingOk`: true

El archivo WAV fue válido y los bytes de audio coincidieron exactamente con los bytes capturados por el contador de frames.

### FACT — pequeño déficit de captura respecto a la duración nominal

- Frames capturados: 6,237,600
- Duración derivada: 129.950 s
- Duración esperada: 130.000 s
- Déficit: 2,400 frames = 50 ms

Este déficit no fue una pérdida de chunks del recorder; la contabilidad de producción/escritura fue exacta. El origen de esos 50 ms no quedó demostrado en esta prueba.

### FACT — ASR continuó procesando

La ejecución completó 32 jobs sin drops de la cola ASR. Se observaron incrementos de latencia alrededor de las ventanas 09–14; la inferencia de `window-09` llegó aproximadamente a 9.95 s y la cola alcanzó profundidad 2.

La reconstrucción mantuvo el orden de las ventanas y no presentó IDs duplicados en esta ejecución.

## Clasificación de resultados

### HECHO

El simple `Disable-PnpDevice`/`Enable-PnpDevice` del endpoint Realtek, mientras existía una instancia abierta de `WasapiLoopbackCapture`, **no provocó una interrupción observable del stream** en esta máquina y configuración.

### HECHO

La implementación actual no produjo una notificación de pérdida de captura derivada de ese evento: no ocurrió `RecordingStopped`, no hubo excepción del recorder y el archivo de sesión continuó recibiendo datos.

### HIPÓTESIS / NO DEMOSTRADO

Una desconexión física, reinicio de `audiosrv`, eliminación/recreación del endpoint o un cambio que realmente invalide la instancia WASAPI abierta puede tener un comportamiento diferente. Esta prueba no demuestra ese caso.

## Decisión

**Paso 9A: CLOSED como caracterización.**

No se modifica `Program.cs` a partir de esta prueba.

No se considera que el soporte de device change/reconnection esté implementado ni validado. El **Paso 9 general permanece OPEN** hasta determinar si hace falta una prueba adicional de pérdida real del endpoint y qué comportamiento de producto se requiere ante esa condición.

## Nota sobre 9B-1

La prueba propuesta de cambio de dispositivo de salida A→B **no fue ejecutada como experimento válido** en esta ejecución. Por tanto, no se registra como PASS ni como evidencia de comportamiento de reconexión.
