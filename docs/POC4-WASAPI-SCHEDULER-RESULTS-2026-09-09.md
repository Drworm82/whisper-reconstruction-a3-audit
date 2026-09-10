# POC 4 — WASAPI Loopback + Ring Buffer + Audio Scheduler

**Fecha:** 2026-09-09
**Estado:** PASS

## Objetivo

Validar un scheduler de audio basado en WASAPI Loopback que capture audio del sistema, lo mantenga en un ring buffer y genere ventanas temporales solapadas para el procesamiento posterior por ASR.

## Configuración

- Captura: WASAPI Loopback
- Formato: 32-bit IEEE Float
- Sample rate: 48,000 Hz
- Canales: 2
- Bytes por frame: 8
- Ring buffer: 20 s
- Duración de prueba: 15 s
- Ventana: 5 s
- Solapamiento: 1 s
- Paso: 4 s

## Resultado

La ejecución produjo correctamente:

| Ventana | Intervalo | Tamaño |
|---|---|---:|
| #0 | 0.000–5.000 s | 1,920,000 bytes |
| #1 | 4.000–9.000 s | 1,920,000 bytes |
| #2 | 8.000–13.000 s | 1,920,000 bytes |

Métricas finales:

- Frames capturados: 720,960
- Bytes capturados: 5,767,680
- Duración calculada: 15.020 s
- Frames descartados del ring buffer: 0
- Ventanas generadas: 3
- Tamaño de las tres ventanas: OK

## Corrección aplicada

La primera ejecución mostró que el scheduler podía quedar esperando indefinidamente al exigir exactamente 15 segundos de frames.

Se modificó la terminación para utilizar el evento real `RecordingStopped` de WASAPI mediante el estado `captureStopped`.

El scheduler ahora:

1. Espera ventanas completas mientras la captura está activa.
2. Detecta la finalización real de la captura.
3. Procesa las ventanas completas que ya estén disponibles.
4. Termina sin depender de que se hayan recibido exactamente 720,000 frames.

La segunda ejecución terminó automáticamente y mostró `POC 4 finalizado.` sin intervención manual.

## Validación

**PASS**

La POC demuestra que el componente de captura/scheduler puede:

- capturar audio mediante WASAPI Loopback;
- mantenerlo en un ring buffer;
- generar ventanas de 5 s con 1 s de solapamiento;
- conservar el tamaño esperado de cada ventana;
- no descartar frames durante esta prueba;
- finalizar limpiamente después de detener la captura.

## Limitaciones

Esta POC todavía no valida:

- inferencia ASR dentro del scheduler;
- cola de inferencia;
- comportamiento bajo saturación;
- múltiples ventanas procesadas por whisper-server;
- reconstrucción continua;
- watchdog de whisper-server;
- operación prolongada.

La geometría de ventanas 5 s / 1 s se conserva como configuración de prueba y no se considera todavía una decisión definitiva de producción.
