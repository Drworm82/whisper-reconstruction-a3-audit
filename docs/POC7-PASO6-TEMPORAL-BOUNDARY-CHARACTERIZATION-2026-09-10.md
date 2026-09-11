# POC7 Paso 6 — Caracterización de frontera temporal

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`

## Objetivo

Determinar si la inversión temporal observada entre los anchors de un MATCH real implica necesariamente una inversión temporal en la reconstrucción.

## Evidencia

El patrón real `I -> 84` produce un MATCH léxico de `14/14` cuando se evalúa sin el guard temporal.

En ese patrón:

- anchor previo: `I @ 4.37s`;
- anchor actual: `I @ 4.00s`;
- el guard actual rechaza el MATCH porque `4.00 < 4.37`.

Sin embargo, la palabra anterior al MATCH en la secuencia previa es `And @ 2.84-4.00s`. Por tanto, la frontera inmediatamente anterior al bloque que se sustituiría está en `4.00s`.

La prueba `Find-WordOverlap.TemporalBoundary.RealJitter.Tests.ps1` deja esta relación explícita y verifica que:

1. el guard actual rechaza el candidato;
2. el anchor actual empieza exactamente en la frontera temporal de la palabra previa (`4.00s`);
3. por ello, `currentAnchor.From < previousAnchor.From` no basta por sí solo para demostrar que la inserción del bloque produciría una regresión temporal.

## Estado

**CARACTERIZACIÓN PASS.**

Esto no modifica la lógica de producción. Establece una distinción necesaria entre:

- orden de los anchors seleccionados por `Find-WordOverlap`;
- orden de la frontera del prefijo acumulado que `Reconstruct-WhisperWindows` conserva antes de insertar el MATCH.

## Próximo paso

Diseñar una prueba de reconstrucción que aplique el MATCH real sobre un prefijo acumulado y compruebe directamente si la sustitución produce o no una regresión temporal. Solo después de esa prueba se decidirá si el guard actual debe cambiarse.

## Commit

- `ca7160d` — Add temporal boundary characterization for real jitter
