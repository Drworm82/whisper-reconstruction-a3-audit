# POC7 Paso 6 — Prueba de frontera de colocación temporal

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** **PENDIENTE DE VALIDACIÓN LOCAL**

## Objetivo

Comprobar de forma determinista la hipótesis de que la seguridad temporal de un MATCH debe evaluarse contra la frontera del prefijo acumulado que precede al bloque reemplazado, y no únicamente contra el timestamp del anchor seleccionado en la ventana previa.

## Caso real de jitter

Datos observados en la prueba real:

- prefijo previo: `And @ 2.84-4.00s`;
- anchor previo seleccionado: `I @ 4.37-4.49s`;
- anchor actual: `I @ 4.00-4.11s`.

El anchor actual comienza antes que el anchor previo (`4.00 < 4.37`), por lo que el guard actual lo rechaza. Sin embargo, comienza exactamente en la frontera del prefijo (`4.00 >= 4.00`).

La prueba no modifica el algoritmo de producción. Construye explícitamente la secuencia que resultaría de `prefix + currentMatch` y comprueba sus invariantes temporales.

## Caso históricamente problemático

También se reproduce la forma del defecto que motivó el guard:

- prefijo acumulado termina en `participate @ 4.13s`;
- anchor previo: `in @ 4.86s`;
- anchor actual: `in @ 4.00s`.

Aquí el anchor actual comienza antes de la frontera del prefijo (`4.00 < 4.13`) y la sustitución produce una regresión temporal.

## Criterio

La caracterización debe demostrar simultáneamente:

1. el caso real puede ser cronológicamente colocable aunque sus anchors estén invertidos;
2. el caso históricamente problemático sigue siendo rechazable mediante la frontera del prefijo;
3. la comprobación se refiere a la secuencia que realmente se reconstruye, no a una comparación abstracta entre anchors.

## Restricción

No se modifica todavía:

- `src/Alignment/Find-WordOverlap.ps1`;
- `src/Reconstruction/Reconstruct-WhisperWindows.ps1`.

La modificación de producción queda condicionada al resultado de esta prueba y a la posterior prueba de reconstrucción.

## Próxima acción local

```powershell
git pull --rebase origin reconstruction-fixes
Invoke-Pester .\tests\Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1
```

No requiere captura de audio ni `whisper-server`.

## Commit

- `966ede3` — Characterize MATCH placement against accumulated prefix boundary
