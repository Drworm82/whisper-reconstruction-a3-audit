# POC7 — Paso 6: validación del guard temporal de MATCH

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** VALIDADO LOCALMENTE

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

La finalidad de este paso era comprobar experimentalmente si esta condición mínima elimina la regresión sin modificar la lógica validada de reconstrucción.

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

## Validación local

El usuario sincronizó correctamente la branch y ejecutó el harness sobre los JSON existentes.

Resultado observado:

- Window #0: `20` palabras construidas
- Window #1: `24` palabras construidas
- Window #2: `21` palabras construidas
- transición `0s -> 2s`: el guard rechazó explícitamente el candidato:
  - Previous anchor: `in @ 4.86s`
  - Current anchor: `in @ 4s`
- transición `2s -> 4s`: `SIN MATCH`
- `ORDER VIOLATIONS: 0`
- `DUPLICATE IDS: 0`
- `FINAL WORD COUNT: 31`
- resumen: `{"Windows":3,"ReconstructedWords":31,"DuplicateIds":0,"OrderViolations":0,"Pass":true}`

## Evaluación

El resultado respalda la hipótesis experimental: el candidato que previamente introducía la regresión temporal fue rechazado y los invariantes de esta prueba quedaron satisfechos.

El guard **todavía no se considera la corrección definitiva del núcleo**. Es deliberadamente conservador y compara los dos anchors seleccionados, no el límite temporal exacto del prefijo acumulado. Antes de modificar `Find-WordOverlap` o `Reconstruct-WhisperWindows`, hace falta una prueba de regresión focalizada que establezca la regla correcta y sus efectos sobre los casos ya validados.

## Siguiente paso

Crear una prueba de regresión específica para la condición de colocación temporal del MATCH. Con esa prueba se decidirá si la regla debe integrarse en `Find-WordOverlap`, en `Reconstruct-WhisperWindows`, o como una restricción más específica de selección de MATCH.

No modificar todavía los scripts validados del núcleo sin esa prueba adicional.

## Commits del cambio experimental

- `782997ed9a7b9b0f1305a1314af0c87d7600085c` — Add temporal MATCH placement guard for controlled validation
- `96da9944a27be0caaafbafdba182fd05adaac803` — Add guarded MATCH reconstruction validation harness
