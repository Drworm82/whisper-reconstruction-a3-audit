# POC7 — Paso 6: prueba controlada de MATCH / DEDUP

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** diagnóstico temporal identificado; corrección pendiente de validación

## Objetivo

Obtener evidencia directa de que `Reconstruct-WhisperWindows` puede producir un `MATCH` real entre dos ventanas consecutivas cuando ambas contienen la misma habla dentro de su intervalo físico de solapamiento.

El Paso 5 validó el flujo end-to-end real, pero las dos transiciones de esa ejecución no proporcionaron evidencia de un `MATCH` lingüístico real. Este paso aísla esa pregunta sin modificar la geometría de producción del Paso 5.

## Geometría experimental

| Parámetro | Valor |
|---|---:|
| Captura | WASAPI Loopback |
| Duración | 14 s |
| Ventana | 10 s |
| Solapamiento | 8 s |
| Paso | 2 s |
| Endpoint | `http://127.0.0.1:8080/inference` |
| Formato ASR | `verbose_json` |

```text
#00 = 0-10 s
#01 = 2-12 s
#02 = 4-14 s
```

La geometría es experimental y no sustituye los parámetros de producción de Paso 5 (`5 s / 1 s overlap / 4 s step`).

## Resultado de la primera ejecución local

La ejecución del harness produjo:

```text
VENTANA #00 | segments=3 | serverWords=31 | tokens=31
VENTANA #01 | segments=3 | serverWords=30 | tokens=30
VENTANA #02 | segments=3 | serverWords=30 | tokens=30

BuildCounts = 20,24,21
ReconstructedWords = 28
DuplicateIds = 0
OrderViolations = 1
```

La inspección posterior de los JSON demostró que **sí existen candidatos de MATCH** en ambas transiciones. Por tanto, la ausencia de `MATCH` en la salida original del harness era un problema de visibilidad de `Write-Host`, no evidencia de ausencia de coincidencias.

## Evidencia directa de los candidatos

### Transición 0 → 1

`Find-WordOverlap` encontró:

```text
Matches = 15
ExactTextMatches = 14
PreviousStart = 0
CurrentStart = 0
PreviousConsumed = 15
CurrentConsumed = 15
DurationDifference = 0.33 s
```

El anchor anterior fue `is` en `1.67–2.09 s` y el actual `is` en `2.00–2.36 s`. La diferencia inicial es de `0.33 s`, compatible con la tolerancia de deriva usada por la reconstrucción para un overlap de 8 s.

### Transición 1 → 2

`Find-WordOverlap` encontró:

```text
Matches = 11
ExactTextMatches = 11
PreviousStart = 2
CurrentStart = 0
PreviousConsumed = 11
CurrentConsumed = 11
DurationDifference = 0.86 s
```

El anchor anterior fue `in` en `4.86–4.93 s` y el actual `in` en `4.00–4.22 s`.

La diferencia de inicio es `0.86 s`. Para un overlap de 8 s, la reconstrucción calcula una tolerancia máxima de `1.5 s`, por lo que el candidato lexical puede superar esa comprobación general. Sin embargo, la reconstrucción también necesita conservar el orden cronológico del transcript acumulado.

## Hallazgo: causa inmediata del OrderViolations = 1

La secuencia final observada fue:

```text
1-4  participate  4.13 s
2-0  in           4.00 s
```

El `OrderViolations = 1` es, por tanto, inequívoco: el `MATCH` de la transición `1 → 2` seleccionó como comienzo de la secuencia actual una palabra cuyo timestamp global (`4.00 s`) precede a la última palabra conservada del prefijo (`4.13 s`).

La reconstrucción actualmente consume el candidato lexical encontrado por `Find-WordOverlap` y conserva el prefijo hasta el anchor anterior; después inserta la secuencia actual desde `CurrentStart`. El resultado puede ser lexicalmente coincidente pero temporalmente no monótono.

Este hallazgo **no justifica todavía modificar `Find-WordOverlap`**. Primero debe probarse una corrección mínima en la frontera de consumo del MATCH que rechace o reajuste un candidato cuando su secuencia seleccionada no puede concatenarse cronológicamente con el prefijo acumulado.

## Diagnóstico añadido

`AudioCapturePOC/MatchDedupPOC/InspectMatchDedup.ps1` ahora imprime además:

- diferencia temporal entre anchors;
- tolerancia de deriva calculada para el overlap;
- si los anchors están dentro de esa tolerancia;
- advertencia explícita cuando un candidato lexical es temporalmente sospechoso.

El inspector sigue reutilizando los JSON existentes y no captura audio ni llama a `whisper-server`.

## Criterio de PASS

La prueba completa solo puede declararse PASS cuando una ejecución demuestra simultáneamente:

1. al menos un MATCH real directamente observable;
2. evidencia temporal suficiente para que el MATCH pueda concatenarse sin regresión;
3. la reconstrucción termina sin IDs duplicados;
4. el orden temporal no presenta regresiones;
5. el resultado reconstruido no duplica artificialmente la ocurrencia compartida.

## No cambios arquitectónicos

El diagnóstico no modifica:

- `Convert-WhisperServer.ps1`;
- `Build-WhisperWords.ps1`;
- `Find-WordOverlap.ps1`;
- `Reconstruct-WhisperWindows.ps1`;
- la geometría de Paso 5;
- el tratamiento de offsets globales.

## Siguiente paso

No repetir todavía la captura.

El siguiente cambio debe ser **mínimo y aislado**, sobre el consumo del MATCH en `Reconstruct-WhisperWindows.ps1`, con una prueba que demuestre que un candidato lexical cuya primera palabra cae antes del final del prefijo no produce una regresión temporal.

Antes de modificar esa lógica se debe preservar la evidencia de este caso controlado y añadir una regresión reproducible basada en estos timestamps.

## Commits

- `51e24614b617e1a6c2bb4ae757e99880109629a1` — Add controlled MATCH/DEDUP POC project
- `792779ce74c0ebaff921b795ddab0736afbc0387` — Add controlled MATCH/DEDUP POC harness
- `16773cc771e88c01e15fd149b64dc9fb0988b413` — Expose reconstruction MATCH logs in controlled POC
- `3a7b4d8429a3e06ea386e18c1a6ce8a887a5c4db` — Clarify MATCH logs are expected in stdout
- `1213c76124bd9ae60b1e7018eb34c529a789bdc4` — Add MATCH/DEDUP diagnostic inspector
- `32e909d05052e9f5cd89c78a2ccf4386aac4ff5e` — Add temporal MATCH diagnostics
