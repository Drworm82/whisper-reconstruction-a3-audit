# POC6 — Bounded Inference Queue

## Resultados — 2026-09-09

### Objetivo

Validar de forma aislada la mecánica de una cola de inferencia acotada (bounded) para el futuro flujo de ASR persistente con `whisper-server`.

La prueba evalúa:

- capacidad máxima fija de la cola;
- comportamiento ante producción más rápida que el consumidor;
- política explícita `DropOldest`;
- procesamiento secuencial del consumidor;
- contabilidad completa de trabajos producidos, procesados, descartados y pendientes.

Esta POC no valida todavía la integración completa WASAPI → cola → `whisper-server`.

### Configuración

| Parámetro | Valor |
|---|---:|
| Capacidad de cola | 3 jobs |
| Intervalo del productor | 100 ms |
| Tiempo de procesamiento del consumidor | 500 ms/job |
| Duración de la prueba | 5000 ms |
| Política de overflow | `DropOldest` |
| Implementación | `Queue<InferenceJob>` + `lock` + `SemaphoreSlim` |
| Target | .NET 10 |

### Resultado

```text
Capacity:              3
Producer interval:     100 ms
Consumer processing:   500 ms
Duration:              5000 ms
Overflow policy:       DropOldest

Jobs produced:         46
Jobs processed:        13
Jobs dropped:          33
Jobs pending:            0
Max queue depth:         3

Accounting:
46 = 13 + 33 + 0 | OK

Capacity:
3 <= 3 | OK

POC6 PASS