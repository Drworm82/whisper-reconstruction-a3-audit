# POC7 — Paso 6: validación del guard temporal de MATCH

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** preparado para validación local

## Hallazgo previo

La inspección de los JSON reales de la primera ejecución controlada demostró que `Find-WordOverlap` sí encuentra coincidencias reales:

- transición `0 -> 1`: `15` matches, `14` textos exactos;
- transición `1 -> 2`: `11` matches, `11` textos exactos.

La segunda coincidencia seleccionó como anchor anterior `in @ 4.86s` y como anchor actual `in @ 4.00s`. La reconstrucción consumió el MATCH sustituyendo una secuencia acumulada que ya terminaba en `participate @ 4.13s` por una secuencia que comenzaba en `in @ 4.00s`, produciendo una regresión temporal.

Resultado observado antes del guard:

```text
OrderViolations = 1
DuplicateIds = 0
FinalWordCount = 28
```

## Corrección experimental mínima

No se modifica todavía `Reconstruct-WhisperWindows.ps1`.

Se añadió:

`src/Alignment/Find-WordOverlap-MatchGuard.ps1`

El guard conserva la implementación existente de `Find-WordOverlap` y rechaza únicamente un candidato cuyo `CurrentStart` tenga un timestamp `From` anterior al `PreviousStart` seleccionado.

Cuando el candidato es rechazado, devuelve `$null`. Esto hace que `Reconstruct-WhisperWindows` entre por su ruta existente de `SIN MATCH`, incluyendo su deduplicación temporal y ordenamiento ya implementados.

La finalidad de este paso es comprobar experimentalmente si esta condición mínima elimina la regresión sin modificar la lógica validada de reconstrucción.

## Harness

Se añadió:

`AudioCapturePOC/MatchDedupPOC/InspectMatchDedupGuarded.ps1`

El harness reutiliza los tres JSON crudos de la captura anterior. No captura audio y no realiza nuevas llamadas a `whisper-server`.

Flujo:

```text
JSON existente
  -> Convert-WhisperServer
  -> offset global
  -> Build-WhisperWords
  -> Find-WordOverlap original + guard temporal
  -> Reconstruct-WhisperWindows existente
  -> invariantes finales
```

## Criterio de validación

El guard solo se considera prometedor si la ejecución local demuestra:

- `OrderViolations = 0`;
- `DuplicateIds = 0`;
- reconstrucción sin excepción;
- conservación del contenido reconstruido esperado para esta prueba.

Esta prueba no constituye todavía un cambio definitivo en `Find-WordOverlap` ni en `Reconstruct-WhisperWindows`. Primero debe validarse con los JSON reales.

## Siguiente comando local

Después de sincronizar los nuevos commits:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AudioCapturePOC\MatchDedupPOC\InspectMatchDedupGuarded.ps1
```

No se debe volver a ejecutar la captura antes de evaluar este resultado.

## Commits

- `782997ed9a7b9b0f1305a1314af0c87d7600085c` — Add temporal MATCH placement guard for controlled validation
- `96da9944a27be0caaafbafdba182fd05adaac803` — Add guarded MATCH reconstruction validation harness
