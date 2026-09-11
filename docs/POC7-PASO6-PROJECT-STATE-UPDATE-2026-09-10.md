# POC7 — Paso 6: Project State Checkpoint

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** **PASS — validado localmente post-integración**

## Estado alcanzado

POC7 Paso 6 identificó una regresión temporal real durante una reconstrucción con ventanas solapadas: un candidato MATCH seleccionado por `Find-WordOverlap` tenía un anchor actual cuyo `From` (`4.00 s`) era anterior al anchor previo (`4.86 s`). La reconstrucción resultante produjo una regresión temporal (`OrderViolations = 1`).

Se validó primero un guard experimental y posteriormente se integró la misma condición directamente en:

`src/Alignment/Find-WordOverlap.ps1`

La integración conserva la selección existente de candidatos. Después de seleccionar el candidato `$best`, si el anchor actual tiene un `From` anterior al anchor previo, el candidato es rechazado y la función devuelve `$null`, permitiendo que `Reconstruct-WhisperWindows` continúe por su ruta existente de `SIN MATCH`.

`Reconstruct-WhisperWindows.ps1` no fue modificado.

## Evidencia local post-integración

Se ejecutó:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AudioCapturePOC\MatchDedupPOC\InspectMatchDedup.ps1
```

Resultado observado:

- transición `0 -> 1`: `15` matches, `14` textos exactos; diferencias de anchor de `0.33 s` en `From` y `0.27 s` en `To`, dentro de allowance de `1.5 s`;
- durante la reconstrucción `0s -> 2s`: el candidato temporalmente invertido fue rechazado por el guard integrado;
- transición `2s -> 4s`: `SIN MATCH`;
- `OrderViolations = 0`;
- `DuplicateIds = 0`;
- `FinalWordCount = 31`.

Mensaje clave observado:

```text
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
Previous anchor: 'in' @ 4.86s
Current anchor:  'in' @ 4s
```

## Conclusión de checkpoint

El guard temporal integrado queda **validado para el caso controlado utilizado en POC7 Paso 6**.

Esta validación no demuestra todavía suficiencia universal de la regla para todas las geometrías de ventanas, patrones de habla o ejecuciones prolongadas. Antes de ampliar la geometría o avanzar de componente se requiere una prueba de regresión aislada que cubra tanto el rechazo de un candidato temporalmente invertido como la conservación de un MATCH cronológicamente válido.

## Próximo paso

Crear y ejecutar la prueba de regresión aislada para la condición de placement temporal junto con las pruebas de reconstrucción existentes. No realizar una nueva captura de audio hasta que esa regresión esté implementada y evaluada.

## Referencias

- `docs/POC7-PASO6-MATCH-GUARD-VALIDATION-2026-09-10.md` — evidencia detallada de la validación experimental y post-integración.
- `src/Alignment/Find-WordOverlap.ps1` — guard temporal integrado.
- `src/Reconstruction/Reconstruct-WhisperWindows.ps1` — núcleo de reconstrucción preservado sin cambios para esta corrección.

## Commits relevantes

- `7458394a8f60ed7a4f4b3cd9f4b2fc642ffe42c2` — Integrate temporal MATCH placement guard into Find-WordOverlap
- `a57baed690bafb90ca47a1ab59a548bd483640c9` — Record local PASS for integrated temporal MATCH guard
