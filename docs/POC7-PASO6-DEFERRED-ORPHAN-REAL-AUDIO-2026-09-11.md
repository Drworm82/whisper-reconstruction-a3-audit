# POC7 Paso 6 — Deferred orphan reproducido con audio real de habla

**Fecha:** 2026-09-11  
**Rama:** `poc7-paso6-temporal-guard-clean`  
**Estado:** Hallazgo confirmado con datos reales. Documentación del fenómeno; este documento no prescribe una solución.

## 1. Objetivo

Comprobar si la rama `CurrentStart > 0` y el ciclo de vida de `deferred` ocurren con **audio real de habla** y no solamente con fixtures sintéticos.

El experimento ejecuta el pipeline POC7 actual sobre un fragmento de audio grabado, con ventanas generadas por el scheduler de producción y tokens reales de whisper.cpp.

## 2. Audio y ASR utilizados

| Ítem | Valor |
|---|---|
| Archivo | `tests/fixtures/real-course-test.wav` |
| Codificación | PCM `s16le` |
| Frecuencia | 16 kHz |
| Canales | mono |
| Duración | 125.034688 s |
| ASR | `whisper-cli` |
| Modelo | `ggml-base.en.bin` |
| Dispositivo | Vulkan — AMD Radeon RX 6600 XT |

Se utilizó **una invocación de ASR por ventana**, no una transcripción completa del audio en una sola llamada.

Verificación empírica previa: los `offsets` de token devueltos por whisper-cli con `-ot` (desplazamiento de ventana) son **milisegundos absolutos**, es decir, ya están referenciados al inicio del archivo. Por tanto los tiempos de token **no requieren sumar nuevamente el offset de la ventana**; la conversión a segundos la realiza el adapter `Convert-WhisperCpp`.

## 3. Geometría de ventanas

```text
WindowDuration = 5 s
Overlap        = 4 s
Step           = 1 s

W_i = [i, i + 5]
i   = 0..120
```

Se procesaron **121 ventanas** y se evaluaron **120 transiciones**.

## 4. Resultados de MATCH

| Evento | Conteo |
|---|---:|
| MATCH | 114 |
| SIN MATCH | 73 |
| Rechazos por temporal placement guard | 67 |

Nota: estos contadores son **eventos de ejecución** y no constituyen necesariamente una partición uno-a-uno de las 120 transiciones.

## 5. Rama `CurrentStart > 0`

**36 MATCH events** se registraron con `CurrentStart > 0`.

Esto confirma que la rama `k < CurrentStart` del bucle de conservación de words anteriores al ancla se **ejecuta con datos reales**, y no es exclusiva de fixtures sintéticos.

Ejemplo `tn = 15`:

```text
PreviousStart   = 0
CurrentStart    = 3
Matches         = 9
ExactTextMatches= 9
```

Ejemplo `tn = 71`:

```text
PreviousStart   = 8
CurrentStart    = 6
```

## 6. Deferred

| Métrica | Valor |
|---|---:|
| Deferred creados | 44 |
| Deferred recuperados | 0 |
| Deferred pendientes al final | 44 |

**Ninguna** de las 44 entradas deferred fue recuperada durante el run. El mecanismo de recuperación existente exige que un ancla posterior coincida en texto **y** en timestamps idénticos (`From`/`To` con tolerancia `1e-6`) con una entrada pendiente; esa condición no se produjo en ninguna de las 120 transiciones.

## 7. Redundancia vs pérdida

Los 44 deferred **no deben denominarse palabras perdidas** en bloque. Se distingue entre redundancia normal del solape y pérdida de contenido:

- **21 deferred** tienen su contenido representado posteriormente en `finalWords` por **otra copia** (otra ventana). Son compatibles con la redundancia esperada del solapamiento de ventanas.
- **23 deferred** no tienen **copia equivalente** encontrada.

Los 23 se documentan como:

> orphan real bajo el criterio de supervivencia utilizado en el experimento.

**Criterio de supervivencia utilizado:** búsqueda en `finalWords` de una palabra con el mismo texto normalizado y proximidad temporal de **±0.6 segundos**.

Esta tolerancia es una **heurística del experimento y debe tratarse como limitación**, no como propiedad formal del algoritmo de reconstrucción.

## 8. Caso concreto: `tn = 114`

Deferred creados en la transición 114:

```text
and   [114.02 → 114.52]
that  [114.52 → 115.21]
```

Las transiciones posteriores no encontraron un ancla con esos timestamps, y ambas entradas permanecieron **pendientes al final** de la reconstrucción.

- No aparecieron en `finalWords` por su `Id`.
- Tampoco se encontró una copia equivalente por texto normalizado y proximidad temporal bajo el criterio de supervivencia.

## 9. Identidad global

| Métrica | Valor |
|---|---:|
| Input words | 2194 |
| Final words | 379 |
| Missing por `Id|Text|From|To` | 1815 |
| Duplicados | 0 |
| Cambios de posición | 364 |

`missing = 1815` **no significa** 1815 palabras de contenido perdidas. La entrada contiene aproximadamente **cinco copias de cada palabra** a causa del solapamiento; la eliminación de copias individuales durante la reconstrucción es comportamiento esperable.

El indicador relevante de pérdida no es el conteo de `missing` por clave exacta, sino los **deferred** combinados con el **análisis de supervivencia** descrito en la sección 7.

## 10. Limitaciones

- `base.en` es un modelo pequeño; algunos candidatos podrían ser errores o alucinaciones del reconocimiento.
- El criterio de supervivencia de **±0.6 segundos** es heurístico, no una propiedad formal.
- Los contadores de MATCH y SIN MATCH son **eventos de ejecución** y no necesariamente una partición uno-a-uno de las 120 transiciones.
- Todavía **no se ha demostrado** cuál debe ser la política correcta para deferred pendientes al final de la reconstrucción.
- **No se ha implementado ningún flush** ni ninguna otra corrección de producción.

## 11. Regeneración del experimento

El tooling de diagnóstico (runner y verificación de supervivencia) quedó fuera del repositorio en `%TEMP%\opencode\`; los artefactos JSON de ASR por ventana y los logs del run se conservaron junto al runner. El repositorio no fue modificado por el experimento.

Este experimento no agregó ni modificó código de producción, tests ni fixtures.

## 12. Conclusión

Con audio real de habla, ventanas reales de 5 segundos con paso de 1 segundo y la implementación actual de POC7:

1. Se reprodujo la rama `CurrentStart > 0`.
2. Se crearon deferred.
3. Se observaron deferred que **no fueron recuperados**.

Bajo el criterio de supervivencia utilizado, **23 de los 44** deferred presentan pérdida de contenido no representado por otra copia equivalente.

Por tanto, el **deferred orphan deja de ser únicamente una posibilidad observada en fixtures sintéticos** y queda **reproducido en el pipeline con datos reales**.

## 13. Estado y alcance

Este documento **no prescribe todavía una solución**.

La política correcta para resolver deferred pendientes al finalizar la reconstrucción queda **pendiente de auditoría arquitectónica**.

Fuera de alcance de este hallazgo:

- NO implementar flush.
- NO cambiar `deferredWordsByText`.
- NO cambiar `Find-WordOverlap`.
- NO cambiar `Reconstruct-WhisperWindows`.
- NO agregar tests.
- NO cambiar fixtures.
- NO hacer refactor.