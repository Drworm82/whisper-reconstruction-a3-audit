# POC7 Paso 3 — Integración real con whisper-server

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Repositorio:** `Drworm82/whisper-reconstruction-a3-audit`

## 1. Objetivo

Validar el primer flujo integrado con inferencia ASR real:

```text
WASAPI Loopback
    ->
Ring Buffer
    ->
Scheduler
    ->
Bounded Inference Queue
    ->
Consumidor secuencial
    ->
whisper-server persistente
    ->
verbose_json
```

El objetivo de este paso fue sustituir la inferencia simulada del POC7 Paso 2 por una petición HTTP real a `whisper-server` y comprobar que las ventanas de audio producidas por el scheduler reciben una respuesta ASR válida.

`Convert-WhisperServer`, `Build-WhisperWords` y `Reconstruct-WhisperWindows` no forman parte de esta validación del flujo en tiempo de ejecución.

## 2. Configuración experimental

| Parámetro | Valor |
|---|---:|
| Captura | WASAPI Loopback |
| Sample rate | 48,000 Hz |
| Canales | 2 |
| Formato | 32-bit IEEE Float |
| Bytes por frame | 8 |
| Ring buffer | 20 s |
| Duración solicitada | 15 s |
| Ventana | 5 s |
| Solapamiento | 1 s |
| Paso | 4 s |
| Capacidad de cola | 3 jobs |
| Overflow experimental | `DropOldest` |
| Consumidor | Secuencial |
| Servidor | `http://127.0.0.1:8080/inference` |
| Temperatura | `0.0` |
| Formato de respuesta | `verbose_json` |

El proyecto utiliza .NET 10 y NAudio 3.1.0. La comunicación HTTP utiliza `HttpClient` del runtime.

## 3. Precondición: servidor disponible

Antes de la prueba end-to-end se comprobó:

```text
HTTP 200
```

para `GET http://127.0.0.1:8080/`.

También se realizó una prueba independiente de `POST /inference` con `poc3-bounded-buffer.wav`, solicitando `verbose_json`. La respuesta fue JSON válido con:

- `task=transcribe`;
- `language=english`;
- duración `14.980062... s`;
- `4` segmentos;
- `text` presente;
- `56` unidades `words[]`.

Estas comprobaciones establecieron la disponibilidad del transporte y del formato de respuesta antes de integrar el consumidor en POC7.

## 4. Primera ejecución del Paso 3

La primera ejecución produjo dos ventanas y completó dos inferencias correctamente, pero la captura terminó con una duración calculada de `10.720 s`.

Resultado relevante:

- Jobs producidos: `2`.
- Jobs procesados: `2`.
- Jobs descartados: `0`.
- Jobs pendientes: `0`.
- Inferencias exitosas: `2`.
- Inferencias fallidas: `0`.
- Máxima profundidad de cola: `1`.
- HTTP: `200` para ambas inferencias.

Esta ejecución no se utilizó como evidencia final de cobertura temporal porque la duración efectiva de captura fue inferior a la duración de prueba solicitada.

El servidor fue comprobado posteriormente y continuó respondiendo `HTTP 200`.

## 5. Segunda ejecución — resultado utilizado para validación

La segunda ejecución reprodujo la configuración completa y alcanzó `14.960 s` de audio capturado.

### Captura

- Frames capturados: `718,080`.
- Bytes capturados: `5,744,640`.
- Duración calculada: `14.960 s`.
- Frames descartados del ring buffer: `0`.

### Ventanas producidas

- Ventana `#0`: `0.000-5.000 s` — `1,920,000` bytes.
- Ventana `#1`: `4.000-9.000 s` — `1,920,000` bytes.
- Ventana `#2`: `8.000-13.000 s` — `1,920,000` bytes.

### Inferencia real

| Job | Ventana | HTTP | Tiempo | Segmentos | Words | Respuesta |
|---|---|---:|---:|---:|---:|---:|
| `#00` | 0-5 s | 200 | 333.9 ms | 2 | 13 | 4,401 bytes |
| `#01` | 4-9 s | 200 | 1,017.9 ms | 2 | 16 | 4,576 bytes |
| `#02` | 8-13 s | 200 | 287.4 ms | 1 | 7 | 3,628 bytes |

Todas las respuestas HTTP fueron `200` y todas pasaron la validación estructural de `verbose_json` (`task`, `language`, `segments` y `text`).

### Cola

- Jobs producidos: `3`.
- Jobs procesados: `3`.
- Jobs descartados: `0`.
- Jobs pendientes: `0`.
- Profundidad máxima: `1`.
- Contabilidad: `3 = 3 + 0 + 0` — `OK`.
- Capacidad: `1 <= 3` — `OK`.
- Contabilidad de inferencia: `3 = 3 + 0` — `OK`.
- Orden de procesamiento: `#00`, `#01`, `#02`.

El scheduler y el consumidor terminaron correctamente.

## 6. Criterios de PASS

### PASS

- [x] Captura WASAPI real.
- [x] Scheduler produjo las ventanas esperadas `0-5`, `4-9` y `8-13 s`.
- [x] Las ventanas conservaron el tamaño esperado de `1,920,000` bytes.
- [x] La cola permaneció dentro de su capacidad.
- [x] Los jobs fueron procesados secuencialmente.
- [x] Cada job procesado recibió HTTP `200`.
- [x] Cada respuesta procesada fue JSON válido con estructura `verbose_json` mínima.
- [x] No hubo errores de inferencia.
- [x] No hubo jobs descartados ni pendientes en la ejecución utilizada para validar.
- [x] El scheduler y el consumidor terminaron limpiamente.

**Resultado: POC7 Paso 3 — PASS.**

## 7. Qué demuestra este PASS

Queda validado experimentalmente el siguiente hand-off:

```text
WASAPI Loopback
    ->
Ring Buffer
    ->
Scheduler
    ->
Bounded Inference Queue
    ->
Consumidor secuencial
    ->
HTTP POST /inference
    ->
whisper-server persistente
    ->
verbose_json válido
```

El servidor permaneció disponible después de las pruebas.

## 8. Qué NO queda validado

Este PASS no establece:

- integración en tiempo de ejecución con `Convert-WhisperServer`;
- integración con `Build-WhisperWords` dentro del consumidor live;
- reconstrucción continua;
- MATCH/DEDUP real sobre habla repetida en ventanas solapadas;
- saturación de la cola con inferencia real;
- política definitiva de overflow;
- latencia end-to-end de producción;
- watchdog/restart;
- reconexión o cambio de dispositivo WASAPI;
- operación prolongada/soak test;
- geometría final de ventanas;
- integración de LLM, detección de preguntas o contexto.

La prueba se realizó bajo carga no saturada: la profundidad máxima de cola fue `1`, por lo que `DropOldest` no fue ejercitado mediante overflow real.

## 9. Nota sobre la primera ejecución

La primera ejecución produjo solo `10.720 s` de captura efectiva. Una segunda ejecución alcanzó `14.960 s` y produjo las tres ventanas esperadas. Por tanto, la primera ejecución se considera una variación puntual no reproducida en la validación final y no se utiliza para declarar un fallo del scheduler.

No se realizó ninguna modificación de la geometría del scheduler para compensarla.

## 10. Siguiente paso

El siguiente paso controlado debe abordar la frontera:

```text
verbose_json
    ->
Convert-WhisperServer
    ->
Build-WhisperWords
```

La reconstrucción continua todavía debe mantenerse fuera de ese primer paso de integración para conservar el aislamiento experimental.

POC7 continúa siendo una secuencia experimental; el sistema todavía no se declara como producto realtime de producción.
