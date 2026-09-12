# POC7 Paso 6 — Conservación end-of-run de `deferredWordsByText`

**Fecha:** 2026-09-12
**Rama:** `poc7-paso6-temporal-guard-clean`
**Estado:** Solución implementada y validada por el test de especificación, la batería de regresión temporal y los caracterizadores deferred existentes.

Este documento registra la corrección del descarte silencioso de palabras deferred al finalizar la reconstrucción. La evidencia previa del fenómeno está en `docs/POC7-PASO6-DEFERRED-ORPHAN-REAL-AUDIO-2026-09-11.md` y `docs/POC7-PASO6-DEFERRED-ORPHAN-CHARACTERIZATION.md`; la caracterización es histórica y su addendum indica cómo cambia el comportamiento esperado.

## 1. Problema original

La rama `CurrentStart > 0` del bucle de conservación puede colocar una palabra en `$deferredWordsByText` cuando una palabra de la ventana actual precede al ancla seleccionado. Hasta esta corrección, el único camino de salida de una entrada deferred era la recuperación posterior por ancla: si ninguna transición posterior recuperaba la ocurrencia, la entrada permanecía en el mapa y se **descartaba silenciosamente** al terminar la función, sin aparecer en `finalWords` ni reportarse como no resuelta.

## 2. Evidencia con audio real

El experimento documentado en `POC7-PASO6-DEFERRED-ORPHAN-REAL-AUDIO-2026-09-11.md` (audio `tests/fixtures/real-course-test.wav`, whisper.cpp Vulkan, 121 ventanas de 5 s con paso de 1 s) registró:

- **Deferred creados: 44**
- **Deferred recuperados: 0**
- **Deferred pendientes al final: 44**

La recuperación existente exige la coincidencia de texto y timestamps del ancla con tolerancia `1e-6`; esa condición no se produjo en ninguna de las 120 transiciones.

Los 44 no se trataron como palabras perdidas en bloque:

- **21** tenían su contenido representado en `finalWords` por otra copia de otra ventana (redundancia normal del solape).
- **23** no tuvieron copia equivalente identificada.

La distinción 21/23 usó una **heurística externa del experimento**: búsqueda de texto normalizado con proximidad temporal de **±0.6 s**. Esa heurística es una limitación del análisis y no se convierte en propiedad del algoritmo.

## 3. Especificación adoptada

La solución se define por tres especificaciones, todas cubiertas por `tests/Reconstruct-WhisperWindows.DeferredEndOfRun.Spec.Tests.ps1`:

- **Especificación A (redundante):** si el deferred pendiente ya está representado en el resultado por otra copia con el mismo texto dentro de la tolerancia derivada, **no** se duplica.
- **Especificación B (huérfano):** si el deferred pendiente **no** está representado, se conserva **exactamente una** representación en `finalWords`.
- **Especificación C (orden cronológico):** la palabra conservada se inserta en posición cronológica según su `From`, preservando el orden temporal no decreciente del resultado.

## 4. Solución implementada: flush end-of-run

`Reconstruct-WhisperWindows.ps1` ejecuta, inmediatamente antes de `return @($finalWords)`, un flush sobre los buckets de `$deferredWordsByText`:

1. **Recolección:** se recorren todos los buckets y se omiten las ocurrencias con `Text` vacío o `Key` vacío.
2. **Orden determinista:** las pendientes se procesan ordenadas por `From`, `To`, `Id`.
3. **Tolerancia de la transición creadora:** el `Id` de la ocurrencia tiene la forma `<WindowIndex>-<WordIndex>`; del índice de ventana se deriva la geometría de la banda compartida con `windows[i-1]`:
   - `bandDuration = windows[i-1].End - windows[i].Start`
   - `driftAllowance = max(0.5, min(1.5, bandDuration * 0.2))`
   - Para la geometría real de 5 s con 4 s de overlap (banda de 4 s), `driftAllowance = 0.8 s`.
4. **Deduplicación (Especificación A):** la ocurrencia es equivalente si existe en `finalWords` una palabra con el mismo texto normalizado (minúsculas, sin espacios) y `|FromDiff| <= driftAllowance` y `|ToDiff| <= driftAllowance`. Si es equivalente, se omite.
5. **Inserción cronológica (Especificaciones B y C):** se busca el primer índice con `From > deferred.From` y se inserta ahí; si no existe, se anexa al final. Las entradas malformadas (Id no parseable o índice fuera del rango de `$windows`) se omiten.

## 5. Decisiones de diseño

- **No se usa la heurística externa de ±0.6 s como constante.** La tolerancia se deriva por ocurrencia desde la transición creadora.
- **No se reutiliza el temporal placement guard** en el flush; el guard de colocación temporal sigue siendo exclusivo del recorrido de transiciones.
- **No se reutiliza `Add-NewWordsWithTiming` de forma literal** en el flush; solo se comparte el predicado de equivalencia (texto normalizado + `From`/`To` dentro de tolerancia).
- **No se modifica la recuperación normal** de anclas deferidas.
- **No se modifica MATCH/SIN MATCH**, ni el alias mapping, ni el guard temporal, ni `Find-WordOverlap`.
- No se añaden propiedades nuevas a los objetos ni hashtables paralelas; la inserción reutiliza el patrón de concatenación del propio archivo.

## 6. Naturaleza del flush

El flush es una **política de conservación/deduplicación al finalizar la reconstrucción**, no una validación semántica de la transcripción: determina qué ocurrencias pendientes merecen una representación y dónde insertarla, pero **no** juzga si el contenido es verdadero.

## 7. Riesgos residuales

- Un deferred puede ser una **salida espuria del ASR** (error o alucinación del reconocimiento). El flush no establece por sí mismo que el contenido sea verdadero; solo decide conservarlo cuando no hay copia equivalente.
- Los 23 deferred sin equivalente en el experimento real **pueden incluir errores de ASR**, por lo que su inserción no garantiza ganancia de calidad lingüística.
- La geometría de la banda y la derivación de `driftAllowance` suponen ventanas solapadas con extremos disponibles en `$windows`; geometrías futuras distintas pueden requerir revisar la fórmula.
- Las pruebas son sintéticas y de spec; la validación sobre audio real completo continúa pendiente.

## 8. Validación realizada

Comandos de validación locales (Pester 3.4.0, PowerShell 5.1):

- `tests/Reconstruct-WhisperWindows.DeferredEndOfRun.Spec.Tests.ps1` — **2/2 PASS** (spec A y spec B).
- Cinco tests temporales de regresión — **9/9 PASS**:
  - `tests/Find-WordOverlap.TemporalPlacement.Tests.ps1` — 2/2.
  - `tests/Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1` — 2/2.
  - `tests/Reconstruct-WhisperWindows.TemporalBoundaryCharacterization.Tests.ps1` — 2/2.
  - `tests/Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1` — 2/2.
  - `tests/Reconstruct-WhisperWindows.DeferredAnchorTemporal.Tests.ps1` — 1/1.
- Caracterizadores deferred que cambian de resultado por diseño y ahora pasan:
  - `tests/Reconstruct-WhisperWindows.DeferredOrphanCharacterization.Tests.ps1` — PASS.
  - `tests/Reconstruct-WhisperWindows.DeferredLifecycle.Characterization.Tests.ps1` — 2/2 PASS.
- Caracterizadores que siguen fallando **idénticamente antes y después** del flush (fallos preexistentes, verificados contra HEAD; no son regresiones de esta solución):
  - `tests/Reconstruct-WhisperWindows.DeferredRecovery.Characterization.Tests.ps1` — espera `RECUPERADO ANCLA DIFERIDA` y no lo produce.
  - `tests/Reconstruct-WhisperWindows.DeferredDuplicate.Characterization.Tests.ps1` — idéntico patrón.
  - `tests/Reconstruct-WhisperWindows.DeferredRecovery.Minimal.Tests.ps1` y `tests/Reconstruct-WhisperWindows.DeferredRecovery.Isolated.Tests.ps1` — idéntico patrón.
  - `tests/Reconstruct-WhisperWindows.Deferred.Orphan.{Characterization,Clean,Observed}.Tests.ps1` — fallan por queries con espacio (`Text -eq ' Y'`/`' A'`) que no matchean la salida recortada de `Build-WhisperWords`; misma conducta en HEAD.

No se modificó ningún test existente. El audio real completo **no** se ejecutó en esta etapa.

## 9. Archivos de la solución

- `src/Reconstruction/Reconstruct-WhisperWindows.ps1`: flush end-of-run.
- `tests/Reconstruct-WhisperWindows.DeferredEndOfRun.Spec.Tests.ps1`: test de especificación (commiteado previamente).
- `docs/POC7-PASO6-DEFERRED-END-OF-RUN-PRESERVATION-2026-09-12.md`: este documento.
- `docs/POC7-PASO6-DEFERRED-ORPHAN-CHARACTERIZATION.md`: addendum que clarifica el cambio de comportamiento esperado (evidencia histórica conservada).