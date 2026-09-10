# POC7 Paso 2 — Bounded Inference Queue
## Resultados de integración — 2026-09-10

**Status:** PASS

## 1. Objetivo

Validar la integración entre las ventanas reales producidas por el scheduler de POC7 y una cola de inferencia acotada, manteniendo la captura WASAPI y el ring buffer del Paso 1 sin modificaciones arquitectónicas.

El objetivo específico de este paso es comprobar que:

- las ventanas reales del scheduler pueden convertirse en trabajos de inferencia;
- los trabajos pueden ingresar a una cola con capacidad limitada;
- un consumidor puede procesarlos secuencialmente;
- la profundidad de la cola permanece dentro de su capacidad;
- la contabilidad de trabajos es consistente;
- la terminación de scheduler y consumidor puede completarse correctamente.

La política `DropOldest` se utiliza únicamente como política experimental en este POC. No se establece todavía como política definitiva de producción.

## 2. Flujo validado

~~~text
WASAPI Loopback
      ↓
Ring Buffer
      ↓
Scheduler
      ↓
Ventana de audio real
      ↓
Bounded Inference Queue
      ↓
Consumidor de inferencia simulado
~~~

En este paso todavía no se conecta el consumidor con `whisper-server`.

## 3. Configuración experimental

| Parámetro | Valor |
|---|---:|
| Captura | WASAPI Loopback |
| Sample rate | 48,000 Hz |
| Canales | 2 |
| Formato | 32-bit IEEE Float |
| Bytes por frame | 8 |
| Ring buffer | 20 s |
| Duración de prueba | 15 s |
| Ventana | 5 s |
| Solapamiento | 1 s |
| Paso | 4 s |
| Capacidad de cola | 3 jobs |
| Procesamiento simulado | 500 ms |
| Overflow experimental | DropOldest |

## 4. Corrección previa de terminación

Durante la primera ejecución del Paso 2 se detectó una condición de terminación en la que el consumidor podía permanecer esperando en `SemaphoreSlim.WaitAsync()` después de finalizar la captura.

La evidencia mostró:

~~~text
ANTES DE STOP
DESPUÉS DE STOP
Captura detenida.
SCHEDULER TERMINADO
~~~

sin llegar a:

~~~text
CONSUMIDOR TERMINADO
~~~

La causa identificada fue que el evento `RecordingStopped` actualizaba `captureStopped`, pero no despertaba al consumidor que podía estar esperando una señal de cola.

Se corrigió agregando una señal mediante:

~~~text
queueSignal.Release();
~~~

en `RecordingStopped`.

La corrección se compiló correctamente y posteriormente se ejecutó una prueba completa.

## 5. Ejecución validada

La ejecución válida produjo tres ventanas reales:

~~~text
VENTANA #0: 0.000s -> 5.000s | 1920000 bytes
VENTANA #1: 4.000s -> 9.000s | 1920000 bytes
VENTANA #2: 8.000s -> 13.000s | 1920000 bytes
~~~

Las tres ventanas fueron introducidas en la cola y procesadas:

~~~text
COLA PRODUCE #00
  INFERENCIA #00
  COMPLETADA #00

COLA PRODUCE #01
  INFERENCIA #01
  COMPLETADA #01

COLA PRODUCE #02
  INFERENCIA #02
  COMPLETADA #02
~~~

La terminación también se completó correctamente:

~~~text
ANTES DE STOP
DESPUÉS DE STOP
Captura detenida.
SCHEDULER TERMINADO
CONSUMIDOR TERMINADO
~~~

## 6. Resultado de captura

~~~text
Frames capturados: 719520
Bytes capturados: 5756160
Duración calculada: 14.990s
Frames descartados del ring buffer: 0
~~~

## 7. Resultado de la cola

~~~text
Jobs producidos: 3
Jobs procesados: 3
Jobs descartados: 0
Jobs pendientes: 0
Profundidad máxima: 1
~~~

## 8. Validación de contabilidad

La relación observada fue:

~~~text
3 = 3 + 0 + 0
~~~

Es decir:

~~~text
producidos = procesados + descartados + pendientes
~~~

Resultado:

~~~text
Contabilidad: 3 = 3 + 0 + 0 | OK
~~~

## 9. Validación de capacidad

La cola tenía capacidad máxima de:

~~~text
3 jobs
~~~

La profundidad máxima observada fue:

~~~text
1 job
~~~

Resultado:

~~~text
Capacidad máxima: 1 <= 3 | OK
~~~

## 10. Orden de procesamiento

Los trabajos fueron procesados en orden:

~~~text
#00
#01
#02
~~~

Esto corresponde al orden temporal de las ventanas:

~~~text
#00 → 0.0–5.0 s
#01 → 4.0–9.0 s
#02 → 8.0–13.0 s
~~~

## 11. Resultado

**POC7 Paso 2 — PASS**

El resultado valida la integración básica:

~~~text
WASAPI
  ↓
Ring Buffer
  ↓
Scheduler
  ↓
Bounded Inference Queue
  ↓
Sequential Consumer
~~~

bajo una carga que no produjo saturación de la cola.

## 12. Lo que todavía NO está validado

Este PASS no establece todavía:

- comportamiento de la cola bajo saturación;
- descarte real mediante `DropOldest`;
- política definitiva de overflow;
- conexión real con `whisper-server`;
- inferencia ASR real dentro de este flujo;
- transporte HTTP;
- adaptación de `verbose_json`;
- construcción de palabras dentro del flujo end-to-end;
- reconstrucción continua;
- latencia end-to-end;
- watchdog;
- recuperación del servidor;
- operación prolongada.

## 13. Limitación importante

En esta ejecución:

~~~text
Jobs producidos: 3
Jobs descartados: 0
Profundidad máxima: 1
~~~

Por lo tanto, `DropOldest` **no fue ejercitado bajo saturación**.

La política se mantiene solamente como mecanismo experimental heredado del POC de cola anterior.

No se debe interpretar este resultado como validación de que `DropOldest` sea la política correcta para producción.

## 14. Código

La implementación integrada se encuentra en:

~~~text
AudioCapturePOC/EndToEndPOC/Program.cs
~~~

El proyecto utiliza:

~~~text
NAudio 3.1.0
NAudio.Wasapi 3.1.0
.NET 10
~~~

## 15. Estado

**POC7 Paso 2 — PASS**

Siguiente paso:

Integrar la bounded inference queue con el `whisper-server` persistente real, utilizando las ventanas de audio producidas por el scheduler.

No se modifica todavía la geometría experimental de ventanas ni se establece una política definitiva de overflow.
