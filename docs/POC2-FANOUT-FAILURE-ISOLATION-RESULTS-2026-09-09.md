# POC 2 — Fan-out y aislamiento ante fallo del ASR

**Fecha:** 2026-09-09  
**Estado:** PASS — aislamiento funcional validado; limitación de cola pendiente

## Objetivo

Validar que una captura WASAPI Loopback y su grabación completa puedan continuar aunque el consumidor ASR deje de funcionar.

La prueba se ejecutó en el POC aislado `AudioCapturePOC`, sin modificar todavía la arquitectura ni los módulos de reconstrucción del repositorio principal.

## Entorno

- Windows
- .NET 10.0.302
- NAudio 3.1.0
- NAudio.Wasapi 3.1.0
- Captura: `WasapiLoopbackCapture`
- Formato observado: 48 kHz, 2 canales, 32-bit IEEE Float

## Diseño de la prueba

La captura NAudio alimentó dos consumidores:

```text
                 ┌──→ WAV / grabación
WASAPI → NAudio ─┤
                 └──→ cola → ASR stub
                              X
                           fallo
```

El ASR stub fue configurado para detenerse intencionalmente después de procesar 100 buffers.

La captura se mantuvo activa durante 10 segundos adicionales antes de detener el POC.

## Resultado observado

El ASR llegó al buffer 100 y se produjo el fallo controlado:

```text
ASR stub recibió buffer #100: 7680 bytes

*** FALLO ASR INYECTADO ***
El consumidor ASR se detendrá.
La captura WASAPI debe continuar.

ASR stub finalizado.
```

Después de finalizar el consumidor ASR, la captura continuó avanzando:

```text
Captura: 550 buffers | ASR procesados: 100
Captura: 600 buffers | ASR procesados: 100
Captura: 650 buffers | ASR procesados: 100
Captura: 700 buffers | ASR procesados: 100
Captura: 750 buffers | ASR procesados: 100
Captura: 800 buffers | ASR procesados: 100
Captura: 850 buffers | ASR procesados: 100
```

Resultado final:

- Fallo ASR inyectado: `True`
- Buffers capturados: `877`
- Buffers procesados por ASR stub: `100`
- La captura alcanzó 877 buffers después de que el ASR dejó de consumir.
- Se generó el WAV `poc2-failure-test.wav`.
- El proceso terminó sin excepción de captura.

## Conclusión

### PASS — aislamiento funcional

La prueba demuestra que, dentro de este POC, el fallo del consumidor ASR **no detiene la captura WASAPI ni la ruta de grabación**.

Esto valida la decisión arquitectónica de mantener una ruta de grabación independiente de la ruta de procesamiento ASR.

La evidencia también demuestra que la captura no depende de que el ASR mantenga el mismo ritmo de procesamiento: en esta prueba el ASR procesó solamente 100 buffers mientras la captura continuó hasta 877.

## Limitación identificada

La cola utilizada en este POC es una `BlockingCollection<byte[]>` **sin capacidad máxima**.

Por lo tanto, si el consumidor ASR falla durante una sesión larga, los buffers destinados al ASR pueden acumularse indefinidamente en memoria.

Esto **no es aceptable como diseño final** para una sesión de varias horas.

El siguiente POC deberá definir y validar explícitamente:

1. capacidad máxima del buffer ASR;
2. comportamiento cuando el buffer se llena;
3. política de descarte o recuperación;
4. forma de reiniciar/reconectar el consumidor ASR;
5. preservación independiente de la grabación completa.

## Qué NO demuestra todavía

Este POC no demuestra todavía:

- integración con `whisper.cpp` real;
- latencia extremo a extremo de transcripción;
- operación sostenida durante 5 horas;
- recuperación de un proceso ASR independiente realmente terminado;
- recuperación ante desaparición/cambio del dispositivo de audio;
- equivalencia entre reconstrucción por lotes y reconstrucción incremental;
- comportamiento bajo carga real de Vulkan/GPU;
- política definitiva de backpressure del buffer ASR.

## Disposición arquitectónica

No se modifica todavía ningún módulo existente de reconstrucción.

Se conserva como objetivo de Phase 1:

```text
Windows system audio
        |
WASAPI Loopback
        |
      NAudio
        |
   early fan-out
      /      \
     v        v
recording   ASR buffer
              |
          whisper.cpp
              |
        normalized ASR data
              |
      windowing/reconstruction
              |
       continuous transcript
```

La grabación completa debe permanecer independiente del ASR para que un fallo del procesamiento no destruya la evidencia de la sesión.

## Siguiente gate

**POC 3 — bounded ASR buffer / backpressure.**

Antes de conectar `whisper.cpp`, se debe validar qué ocurre cuando el consumidor ASR es más lento que la captura y la cola alcanza una capacidad finita. El comportamiento debe ser explícito y medible, no depender de crecimiento ilimitado de memoria.
