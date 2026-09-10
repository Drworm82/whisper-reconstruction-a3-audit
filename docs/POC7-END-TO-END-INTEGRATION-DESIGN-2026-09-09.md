# POC7 - End-to-End Integration Design

**Fecha:** 2026-09-09  
**Rama:** `reconstruction-fixes`  
**Estado:** DISEÑO - NO EJECUTADO  
**Objetivo:** definir y validar la primera integración controlada entre captura WASAPI, scheduler, cola bounded y `whisper-server`.

---

## 1. Objetivo

POC7 debe comprobar que las piezas ya validadas de captura, scheduling, bounded inference queue y whisper-server pueden conectarse en un flujo end-to-end controlado.

El objetivo específico es demostrar el transporte de una ventana de audio real desde la captura hasta una respuesta de ASR estructurada.

El flujo a validar es:

```text
WASAPI Loopback
    |
    v
Ring Buffer
    |
    v
Scheduler
    |
    v
Bounded Inference Queue
    |
    v
Persistent whisper-server
    |
    v
verbose_json
    |
    v
Convert-WhisperServer
    |
    v
Build-WhisperWords
````

POC7 no pretende demostrar todavía que el sistema completo sea un transcriptor realtime continuo de producción.

---

## 2. Base experimental existente

POC7 reutiliza conceptos y componentes que ya fueron probados de forma aislada.

### POC4 - WASAPI Scheduler

POC4 validó:

* captura mediante `WasapiLoopbackCapture`;
* captura independiente del scheduler;
* ring buffer;
* extracción de ventanas mediante una línea temporal basada en frames;
* ventanas de 5 segundos;
* solapamiento de 1 segundo;
* paso de 4 segundos;
* ventanas de tamaño exacto;
* ausencia de frames descartados durante la prueba.

Configuración experimental de POC4:

```text
WindowDuration = 5.0 s
OverlapDuration = 1.0 s
Step = 4.0 s
RingBuffer = 20.0 s
```

POC7 utilizará inicialmente esta geometría únicamente como configuración de prueba.

No se considera todavía una decisión definitiva de geometría de producción.

---

## 3. Bounded Inference Queue

El POC de bounded inference queue validó conceptualmente:

* capacidad máxima;
* productor independiente del consumidor;
* consumidor secuencial;
* política `DropOldest`;
* contabilidad de jobs;
* medición de profundidad máxima.

POC7 debe trasladar este concepto a jobs que contengan audio real producido por el scheduler.

La cola deberá permanecer bounded.

No se permitirá una acumulación ilimitada de audio pendiente de inferencia.

---

## 4. whisper-server

POC7 utilizará el `whisper-server` persistente ya validado.

Endpoint:

```text
http://127.0.0.1:8080/inference
```

La integración utilizará HTTP para enviar cada ventana de audio.

La respuesta esperada será:

```text
response_format=verbose_json
```

La prueba anterior demostró que el servidor puede devolver:

* tarea;
* idioma;
* duración;
* texto;
* segmentos;
* unidades `words[]`;
* tiempos `start` y `end`.

POC7 no modificará ni recompilará `whisper-server`.

---

## 5. Normalización ASR

La respuesta de `whisper-server` será procesada mediante:

```text
src/Import/Convert-WhisperServer.ps1
```

Este adaptador convierte:

```text
segments[].words[]
```

al formato normalizado utilizado por el pipeline:

```text
Windows
  -> Start
  -> End
  -> Tokens
       -> Text
       -> From
       -> To
```

El adaptador deberá permanecer como frontera específica del transporte `whisper-server`.

No se modificarán:

```text
Build-WhisperWords.ps1
Reconstruct-WhisperWindows.ps1
Convert-WhisperCpp.ps1
```

para solucionar problemas específicos de esta integración.

---

## 6. Construcción de palabras

Después de la normalización se utilizará:

```text
src/Words/Build-WhisperWords.ps1
```

El objetivo de esta etapa será demostrar que las unidades `words[]` producidas por `whisper-server` pueden convertirse al modelo de palabras utilizado por la reconstrucción existente.

La prueba deberá conservar:

* texto;
* tiempos;
* orden;
* unidades léxicas;
* puntuación cuando corresponda.

---

## 7. Cola e inferencia

El consumidor de la cola será secuencial.

La intención es evitar inferencias concurrentes sobre la misma GPU durante este POC.

Conceptualmente:

```text
Scheduler
    |
    v
Bounded Queue
    |
    +----> Consumer
              |
              v
        HTTP whisper-server
              |
              v
        normalized result
```

La captura no deberá esperar a que termine una inferencia individual.

La llamada HTTP tampoco deberá ejecutarse dentro del callback `DataAvailable` de WASAPI.

---

## 8. Identidad temporal de las ventanas

Cada job deberá conservar como mínimo:

```text
WindowIndex
StartFrame
EndFrame
StartSeconds
EndSeconds
Audio
```

La identidad temporal pertenece a la ventana producida por el scheduler.

El resultado de ASR deberá poder asociarse inequívocamente con el job que lo originó.

POC7 no deberá sustituir esta identidad por el tiempo relativo interno del JSON de ASR.

Los timestamps contenidos en `words[]` describen la posición dentro de la ventana procesada; la integración deberá conservar por separado la posición de la ventana dentro de la captura.

---

## 9. Política de overflow

La política experimental de la cola será:

```text
DropOldest
```

Cuando la cola esté llena:

```text
oldest queued job
        |
        v
     dropped
        |
        v
newest job enters queue
```

Esto evita que una acumulación de trabajo antiguo produzca una latencia creciente indefinida.

POC7 deberá registrar explícitamente:

* jobs producidos;
* jobs procesados;
* jobs descartados;
* jobs pendientes;
* profundidad máxima.

La política no se considera todavía una decisión definitiva de producción.

---

## 10. Alcance de POC7

POC7 debe validar solamente la integración básica.

### Dentro del alcance

* WASAPI Loopback;
* ring buffer;
* scheduler;
* ventanas reales;
* bounded inference queue;
* procesamiento secuencial;
* conexión HTTP con `whisper-server`;
* recepción de `verbose_json`;
* `Convert-WhisperServer`;
* `Build-WhisperWords`;
* asociación entre job y resultado;
* métricas básicas de producción/procesamiento/descarte.

### Fuera del alcance

No se pretende validar todavía:

* reconstrucción continua en tiempo real;
* calidad final de transcripción;
* latencia final del producto;
* prompt/context injection;
* LLM;
* detección de preguntas;
* watchdog;
* reinicio automático del servidor;
* reconexión después de fallo;
* soak test de varias horas;
* geometría definitiva de ventanas;
* política definitiva de overflow;
* despliegue de producción.

---

## 11. Criterios de PASS

POC7 podrá considerarse PASS únicamente si se demuestra mediante ejecución real que:

1. WASAPI captura audio correctamente.
2. El scheduler genera ventanas reales.
3. Las ventanas llegan a la cola bounded.
4. La cola nunca supera su capacidad configurada.
5. La captura no se bloquea esperando una inferencia.
6. El consumidor procesa los jobs secuencialmente.
7. `whisper-server` acepta las ventanas y responde correctamente.
8. Las respuestas contienen el formato esperado.
9. `Convert-WhisperServer.ps1` normaliza correctamente las respuestas.
10. `Build-WhisperWords.ps1` produce palabras válidas.
11. Cada resultado puede asociarse con la ventana que lo produjo.
12. La contabilidad de la cola es consistente:

```text
produced = processed + dropped + remaining
```

13. Los fallos observados se registran como PASS, FAIL o LIMITATION según evidencia.

No se declarará PASS únicamente porque el programa compile o porque el servidor responda a una prueba independiente.

---

## 12. Criterios de FAIL

POC7 deberá considerarse FAIL si se demuestra cualquiera de los siguientes problemas fundamentales:

* pérdida de la identidad temporal de una ventana;
* bloqueo del callback de captura esperando inferencia;
* crecimiento ilimitado de la cola;
* procesamiento concurrente no intencionado;
* respuesta ASR que no puede asociarse con su ventana;
* JSON incompatible con el adaptador;
* palabras que no pueden convertirse al modelo normalizado;
* contabilidad inconsistente de la cola;
* excepción no controlada que detenga la captura por un fallo de inferencia.

Un fallo de una pieza experimental no deberá interpretarse automáticamente como un fallo de toda la arquitectura; deberá aislarse la causa.

---

## 13. Instrumentación mínima

POC7 deberá registrar:

```text
WindowIndex
StartSeconds
EndSeconds
QueueDepth
Produced
Processed
Dropped
InferenceStart
InferenceEnd
InferenceDuration
ASR success/failure
Word count
```

La instrumentación debe permitir reconstruir qué ocurrió con cada ventana.

No se requiere todavía una métrica de calidad lingüística automatizada.

---

## 14. Principio de aislamiento

POC7 debe ser un experimento controlado.

No se modificará el comportamiento validado de:

```text
src/Reconstruction/
src/Windowing/
src/Words/
src/Import/Convert-WhisperCpp.ps1
```

salvo que una prueba posterior aporte evidencia concreta de que una modificación es necesaria.

El código específico de integración deberá permanecer aislado inicialmente en:

```text
AudioCapturePOC/EndToEndPOC/
```

---

## 15. Resultado esperado

El resultado esperado de POC7 no es todavía:

```text
"realtime transcription validated"
```

El resultado esperado es una demostración controlada de:

```text
real audio
    ->
scheduled window
    ->
bounded queue
    ->
persistent ASR server
    ->
structured ASR result
    ->
normalized words
```

Si esta cadena funciona, el siguiente trabajo podrá concentrarse en la integración con reconstrucción continua y en la evaluación de latencia y comportamiento bajo carga.

---

## 16. Estado

**Estado actual: DISEÑO.**

POC7 todavía no ha sido ejecutado.

No existen resultados PASS/FAIL de POC7 en esta fecha.

La implementación deberá comenzar únicamente después de versionar esta especificación y actualizar `docs/PROJECT-STATE.md`.


