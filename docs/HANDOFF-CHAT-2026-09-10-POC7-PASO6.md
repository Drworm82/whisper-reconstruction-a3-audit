# Handoff de continuidad — POC7 Paso 6

**Fecha:** 2026-09-10  
**Rama:** `reconstruction-fixes`  
**Repositorio:** `Drworm82/whisper-reconstruction-a3-audit`

## 1. Punto exacto de continuidad

El trabajo está en **POC7 Paso 6**, investigando una regresión de reconstrucción temporal en MATCH/DEDUP entre ventanas ASR solapadas.

La decisión arquitectónica en curso es separar:

- **alineación lexical:** responsabilidad de `Find-WordOverlap.ps1`;
- **validación temporal contra el transcript acumulado:** responsabilidad de `Reconstruct-WhisperWindows.ps1`.

No avanzar todavía al POC de audio hasta cerrar esta regresión determinista.

## 2. Evidencia histórica que originó el cambio

En una prueba real de audio con geometría experimental de 10 s de ventana, 8 s de overlap y 2 s de paso, `Find-WordOverlap` encontró matches lexicalmente válidos pero la selección podía producir una inversión temporal.

Caso histórico relevante:

- ancla anterior: `in @ 4.86–4.93 s`;
- ancla actual: `in @ 4.00–4.22 s`;
- la frontera del prefijo acumulado era aproximadamente `4.13 s`;
- aceptar el MATCH producía una regresión temporal.

En otra ejecución real:

- anterior: `I @ 4.37–4.49 s`;
- actual: `I @ 4.00–4.11 s`;
- el guard temporal rechazó el candidato.

También se obtuvo evidencia de jitter legítimo donde el MATCH actual comenzaba exactamente en la frontera del prefijo y debía aceptarse.

## 3. Diagnóstico de arquitectura

Se consultó una segunda opinión técnica. La conclusión fue:

1. No hacer que `Find-WordOverlap` conozca el transcript acumulado.
2. `Find-WordOverlap` debe devolver el mejor MATCH lexical.
3. `Reconstruct-WhisperWindows` debe decidir si ese MATCH puede colocarse temporalmente.
4. La condición correcta, cuando existe prefijo, es conceptualmente:

```text
currentMatch[0].From >= prefix[-1].To
```

5. Si `currentMatch[0].From < prefix[-1].To`, el MATCH debe rechazarse y la reconstrucción debe seguir por la ruta existente de `SIN MATCH`.
6. No se debe relajar arbitrariamente el umbral: el caso histórico (~0.86 s de inversión) y el jitter observado (~0.84 s de diferencia de anclas) hacen peligroso ocultar el problema aumentando tolerancias.

## 4. Cambios realizados antes de este handoff

### `Find-WordOverlap.ps1`

Se retiró el guard temporal que producía:

```text
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
```

La función vuelve a comportarse como alineador lexical y devuelve el MATCH seleccionado incluso si el `From` actual es anterior al `From` del ancla anterior.

Commit correspondiente:

- `e32a20f` — Move temporal MATCH validation to reconstruction layer

### Pruebas lexicales

`tests/Find-WordOverlap.TemporalPlacement.Tests.ps1` fue migrada para comprobar únicamente la alineación lexical.

La prueba ahora demuestra que `Find-WordOverlap` devuelve MATCH en ambos casos, incluyendo el caso donde el ancla actual comienza antes que el ancla anterior.

## 5. Pruebas locales ejecutadas más recientemente

El usuario sincronizó correctamente:

```powershell
git pull --rebase origin reconstruction-fixes
```

hasta `16ad86b`.

Resultados:

### `Find-WordOverlap.TemporalPlacement.Tests.ps1`

**2/2 PASS**

- devuelve MATCH lexical aunque el ancla actual comience antes;
- acepta MATCH lexical cronológicamente válido.

### `Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1`

**2/2 PASS**

- acepta jitter real cuando `current.From == prefix boundary`;
- identifica correctamente que el caso histórico comienza antes del prefijo.

### `Reconstruct-WhisperWindows.TemporalBoundaryCharacterization.Tests.ps1`

**2/2 PASS**

- frontera exacta: sin violación;
- comienzo anterior a la frontera: una violación.

### `Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1`

**1/2 PASS**

Caso válido:

- **PASS** — acepta el MATCH lexical cuando el bloque actual comienza en la frontera del prefijo.

Caso histórico:

- **FAIL** — esperaba `SIN MATCH = 1`, obtuvo `0`.

Salida exacta relevante:

```text
[-] does not accept a lexical MATCH when the current block begins before the accumulated prefix boundary
Expected: {1}
But was:  {0}
```

Esto demuestra que **todavía no existe en producción la validación temporal dentro de `Reconstruct-WhisperWindows`**.

## 6. Estado real del código

`Reconstruct-WhisperWindows.ps1` actualmente hace, en esencia:

```text
$match = Find-WordOverlap $prevOverlap $currOverlap

if ($null -eq $match) {
    # SIN MATCH existente
}
else {
    # calcula matchedWord
    # recupera deferred anchor si aplica
    # calcula prefix
    # construye currentMatch
    # construye after
    # reemplaza finalWords = prefix + currentMatch + after
}
```

La validación temporal todavía falta justo antes de aceptar el reemplazo.

La ubicación conceptual correcta es después de tener `$prefix` y `$currentMatch`, y antes de construir/asignar `$newFinal`.

Debe evitarse una modificación que destruya el estado de deferred anchors o altere las correcciones de reconstrucción ya validadas.

## 7. Correcciones históricas que NO deben rehacerse

Preservar:

- `151dc76` — reconstruction state after SIN MATCH
- `0f2c49b` — window assignment crossing boundaries
- `5a1d4cc` — empty-key false matches
- `7ee5902` — key collision selection
- `585bc42` — timing drift in SIN MATCH dedup
- `700065b` — transitive dedup across omitted windows
- `54108ec` — Issue 6 deferred MATCH anchors
- `42dfb9e` — Issue 1 E1 aliases after SIN MATCH

La reconstrucción había tenido anteriormente una batería de 23 pruebas relevantes con 23/23 PASS.

## 8. Regla de trabajo con el usuario

El flujo acordado es estricto:

1. El asistente modifica código directamente en GitHub.
2. El asistente actualiza documentación en GitHub.
3. El asistente hace commits descriptivos.
4. El usuario sincroniza el repositorio local.
5. El usuario ejecuta las pruebas/comandos en PowerShell.
6. El usuario devuelve la salida exacta.
7. El asistente analiza la evidencia y decide el siguiente cambio.

**El usuario no debe editar código ni documentación localmente.**

No asumir que el árbol local está limpio salvo que el usuario lo demuestre.

## 9. Siguiente trabajo obligatorio

Implementar en `Reconstruct-WhisperWindows.ps1` la validación de frontera temporal del MATCH seleccionado.

Requisitos:

- `Find-WordOverlap` permanece lexical.
- Si `$prefix.Count -eq 0`, no existe frontera previa y el MATCH no debe rechazarse por esta regla.
- Si existe prefijo y `$currentMatch.Count -gt 0`:

```text
currentMatch[0].From < prefix[-1].To
```

debe significar rechazo temporal.

- El rechazo debe seguir la semántica existente de `SIN MATCH`, no un `continue` que abandone la transición sin reconciliar estado.
- El rechazo no debe perder/deformar `$deferredWordsByText` de forma irreversible.
- El caso válido con igualdad exacta de frontera debe permanecer aceptado.
- No cambiar `Build-WhisperWords.ps1`.
- No cambiar `Convert-WhisperServer.ps1`.
- No cambiar geometría de audio todavía.

Después de modificar producción, actualizar/ajustar la prueba de integración para que valide comportamiento real y ejecutar primero la batería determinista. Solo después de PASS proceder al audio.

## 10. Audio: evidencia previa útil, pero NO siguiente prueba inmediata

POC7 Paso 6 real-audio anterior:

- WASAPI Loopback;
- 48 kHz;
- 2 canales;
- IEEE Float;
- ventana 10 s;
- overlap 8 s;
- paso 2 s;
- captura ~13.99 s produjo solo dos ventanas completas: `0–10` y `2–12`;
- window #0: 21 Build words;
- window #1: 19 Build words;
- se detectó un MATCH lexical real y el guard anterior lo rechazó:
  `Previous 'I' @ 4.37s; Current 'I' @ 4s`;
- resultado final: 29 palabras, 0 IDs duplicados, 0 violaciones temporales;
- no se consideró PASS porque no hubo MATCH aceptado.

No repetir esta captura hasta cerrar la integración determinista.

## 11. whisper.cpp / ASR ya validado estructuralmente

Entorno local:

- Windows;
- `C:\whisper.cpp`;
- AMD Radeon RX 6600 XT;
- Vulkan;
- `ggml-large-v3-turbo-q5_0.bin` disponible;
- `whisper-server.exe` en `C:\whisper.cpp\build-server-test\bin\Release\whisper-server.exe`;
- endpoint: `http://127.0.0.1:8080/inference`;
- whisper-server usa `no_context=true`;
- benchmark previo ~0.522 s para ~15 s de audio en una prueba de referencia;
- POC7 Paso 3/5 ya validó captura + servidor + conversión estructural.

`Convert-WhisperServer.ps1` está validado para agregar todos los segmentos de una respuesta HTTP en una única ventana lógica y conservar timestamps relativos a esa WAV. El offset global se aplica fuera del adapter mediante `job.StartSeconds`.

## 12. Prompt maestro para el nuevo chat

Usar el siguiente prompt como primer mensaje del nuevo chat. Debe tratar este documento como estado persistente del proyecto y continuar desde el punto exacto, sin rehacer trabajo validado.
