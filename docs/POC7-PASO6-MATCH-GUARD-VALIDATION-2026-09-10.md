# POC7 — Paso 6: integración del guard temporal de MATCH

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** **PASS — guard integrado y prueba de regresión 2/2**

## Evidencia previa

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

## Validación experimental del guard

Antes de integrarlo, el guard se ejecutó sobre los mismos tres JSON reales, sin nueva captura ni nuevas llamadas a `whisper-server`.

Resultado:

```text
ORDER VIOLATIONS: 0
DUPLICATE IDS: 0
FINAL WORD COUNT: 31
{"Windows":3,"ReconstructedWords":31,"DuplicateIds":0,"OrderViolations":0,"Pass":true}
```

El candidato problemático fue rechazado:

```text
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
Previous anchor: 'in' @ 4.86s
Current anchor:  'in' @ 4s
```

La reconstrucción continuó por su ruta existente de `SIN MATCH`.

## Integración

Se integró la misma condición validada directamente en:

`src/Alignment/Find-WordOverlap.ps1`

La implementación existente de selección de candidatos se conserva. Después de seleccionar `$best`, se valida el rango de índices y se comparan los anchors seleccionados. Si el anchor actual tiene un `From` anterior al anchor previo, `Find-WordOverlap` registra el rechazo y devuelve `$null`.

Esto evita que el candidato temporalmente invertido llegue a `Reconstruct-WhisperWindows`, sin modificar el núcleo de reconstrucción ya validado.

El archivo experimental separado `src/Alignment/Find-WordOverlap-MatchGuard.ps1` permanece como referencia de la prueba controlada y no forma parte del flujo integrado.

## Validación local post-integración

El harness `AudioCapturePOC/MatchDedupPOC/InspectMatchDedup.ps1` fue ejecutado después de sincronizar la integración. Este harness carga directamente `Find-WordOverlap.ps1` y no carga el guard experimental.

La ejecución produjo:

- transición `0 -> 1`: candidato MATCH encontrado con `15` matches y `14` textos exactos; evidencia temporal dentro de tolerancia (`0.33 s` de diferencia en `From`, `0.27 s` en `To`, allowance `1.5 s`);
- durante la reconstrucción `0s -> 2s`, el candidato problemático fue rechazado directamente por `Find-WordOverlap.ps1`;
- transición `2s -> 4s`: `SIN MATCH`;
- `ORDER VIOLATIONS: 0`;
- `DUPLICATE IDS: 0`;
- `FINAL WORD COUNT: 31`.

Mensaje observado durante la reconstrucción:

```text
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
Previous anchor: 'in' @ 4.86s
Current anchor:  'in' @ 4s
```

La salida final mantuvo la secuencia temporalmente ordenada, sin IDs duplicados, y conservó 31 palabras reconstruidas.

## Prueba de regresión aislada

Se creó `tests/Find-WordOverlap.TemporalPlacement.Tests.ps1` para cubrir explícitamente ambos comportamientos del guard:

1. **Rechazo:** un MATCH seleccionado cuyo anchor actual comienza antes que el anchor previo debe devolver `$null`.
2. **Aceptación:** un MATCH seleccionado cuyo anchor actual comienza después o en el mismo orden temporal debe conservarse.

El entorno local utiliza **Pester 3.4.0**. La primera ejecución de la prueba falló por incompatibilidad de sintaxis con Pester 5 (`BeforeAll`), por lo que la prueba fue adaptada a la versión real instalada. Esa incidencia no correspondió a un fallo de la lógica del guard.

Ejecución final:

```text
Describing Find-WordOverlap temporal MATCH placement guard
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
Previous anchor: 'uno' @ 4.86s
Current anchor:  'uno' @ 4s
 [+] rejects a selected MATCH whose current anchor starts earlier than the previous anchor 351ms
 [+] accepts a selected MATCH when the current anchor is chronologically valid 40ms
Tests completed in 392ms
Passed: 2 Failed: 0 Skipped: 0 Pending: 0 Inconclusive: 0
```

Resultado: **2/2 PASS**.

## Conclusión

**PASS.** La corrección integrada en `Find-WordOverlap.ps1` reproduce el comportamiento validado del guard experimental sobre los JSON reales de la prueba controlada y cuenta ahora con una prueba de regresión aislada que cubre tanto el rechazo de una inversión temporal como la conservación de un MATCH cronológicamente válido.

La corrección queda validada para este caso controlado y para la condición específica cubierta por la regresión. Esto no demuestra todavía que la regla sea suficiente para todas las geometrías de ventanas, todos los patrones de habla ni una ejecución de larga duración.

## Siguiente paso

Ejecutar la batería de pruebas de reconstrucción existente junto con la nueva regresión temporal antes de ampliar la geometría o avanzar al siguiente componente del pipeline.

## Commits

- `782997ed9a7b9b0f1305a1314af0c87d7600085c` — Add temporal MATCH placement guard for controlled validation
- `96da9944a27be0caaafbafdba182fd05adaac803` — Add guarded MATCH reconstruction validation harness
- `4ef4dc96ee4a76e26b1ffaca13a596e1e4619d06` — Update Step 6 validation documentation after guarded PASS
- `7458394a8f60ed7a4f4b3cd9f4b2fc642ffe42c2` — Integrate temporal MATCH placement guard into Find-WordOverlap
- `6ead848e4ee053d442fa992ea9ed009a10e39bec` — Add temporal MATCH placement regression test
- `824a758f8347bf9b5c1ee76923a8e9d1f68f2442` — Make temporal MATCH regression compatible with Pester 3.4.0
