# POC7 — Paso 6: integración del guard temporal de MATCH

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** integrado; pendiente de validación local post-integración

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

## Estado de validación

La integración remota está realizada, pero todavía requiere validación local después del `git pull`.

La prueba local debe confirmar como mínimo:

- `OrderViolations = 0`;
- `DuplicateIds = 0`;
- ausencia de excepciones;
- conservación del contenido reconstruido esperado;
- rechazo del candidato temporalmente invertido directamente desde `Find-WordOverlap.ps1`.

## Siguiente comando local

Después de sincronizar:

```text
git pull --rebase origin reconstruction-fixes
```

Después ejecutar el harness integrado. No se debe cargar `Find-WordOverlap-MatchGuard.ps1`; la prueba debe demostrar que la corrección ya vive en `Find-WordOverlap.ps1`.

## Commits

- `782997ed9a7b9b0f1305a1314af0c87d7600085c` — Add temporal MATCH placement guard for controlled validation
- `96da9944a27be0caaafbafdba182fd05adaac803` — Add guarded MATCH reconstruction validation harness
- `4ef4dc96ee4a76e26b1ffaca13a596e1e4619d06` — Update Step 6 validation documentation after guarded PASS
- `7458394a8f60ed7a4f4b3cd9f4b2fc642ffe42c2` — Integrate temporal MATCH placement guard into Find-WordOverlap
