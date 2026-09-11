# POC7 Paso 6 — Deferred-anchor temporal guard: resolución

**Fecha:** 2026-09-11  
**Rama:** `poc7-paso6-temporal-guard-clean`  
**Estado:** implementado y validado.

## 1. Contexto

Paso 6 mueve la validación de colocación temporal desde `Find-WordOverlap.ps1` hacia `Reconstruct-WhisperWindows.ps1`, donde existe el estado acumulado necesario para decidir si un MATCH puede sustituir correctamente el prefijo reconstruido.

La regla temporal implementada es:

```powershell
$prefix.Count -gt 0 -and
$currentMatch.Count -gt 0 -and
$currentMatch[0].From -lt $prefix[-1].To
```

Si la condición es verdadera, el MATCH se rechaza (`$match = $null`) y el flujo continúa por la rama existente de `SIN MATCH`.

La comparación es estrictamente `<`: una coincidencia exacta con la frontera (`current.From == prefix[-1].To`) se acepta. Si no existe prefijo acumulado, el guard no rechaza el MATCH.

## 2. Hallazgo inicial: hueco con anclas diferidas

El análisis del flujo mostró que una validación temporal colocada antes de resolver completamente `$prefixCount` podía no disponer de la frontera real del prefijo cuando el ancla seleccionada había sido diferida por un MATCH anterior.

El fixture mínimo utilizado para caracterizar el caso fue de tres ventanas:

```text
W0: Uno, Dos, Tres, Cuatro, Cinco, Seis, Siete
W1: Extra, Cinco, Seis, Siete
W2: Extra, Cinco, Seis, Ocho
```

En W0 → W1, `Extra` queda antes del MATCH y se conserva en `$deferredWordsByText`. En W1 → W2, `Extra` vuelve a aparecer como ancla y puede recuperarse desde los diferidos.

La variante crítica utiliza:

```text
W1 Extra: 4.0 → 4.3
W2 Extra: 3.9 → 4.4
```

Después de la recuperación, el prefijo termina en `4.0`, mientras que el `From` del `Extra` actual es `3.9`; por tanto, la condición temporal debe rechazar el MATCH.

## 3. Corrección del flujo de control

La validación temporal se colocó **después de completar la resolución de `$prefixCount`**, incluida la recuperación desde `$deferredWordsByText`, y después de construir `$prefix` y `$currentMatch`.

El flujo relevante queda conceptualmente así:

```text
Find-WordOverlap
  → resolver ancla seleccionada
  → resolver prefixCount
       ├─ previousOverlapMap
       ├─ finalWords
       └─ deferredWordsByText
  → construir prefix/currentMatch
  → validar colocación temporal
  → si match == null: rama existente SIN MATCH
  → si no: continuación normal de MATCH
```

Esto es importante porque en PowerShell asignar `$match = $null` después de haber pasado por una rama anterior de `SIN MATCH` no hace que el flujo vuelva atrás para ejecutar esa rama. La solución, por tanto, no duplica `SIN MATCH`: establece un único punto de dispatch después de toda la validación de MATCH.

Se preserva la lógica existente de `SIN MATCH`, incluidos deduplicación, aliases, diferidos y orden cronológico.

## 4. Evidencia reproducible

La fixture diferida produjo los siguientes diagnósticos durante W1 → W2:

```text
TRANSICION 4s -> 4.1s
RECUPERADO ANCLA DIFERIDA: 'Extra'
MATCH REJECTED BY TEMPORAL PLACEMENT GUARD
Previous anchor: 'Extra' @ 4s
Current anchor:  'Extra' @ 3.9s
Accumulated prefix boundary: 4 s
SIN MATCH
```

La evidencia demuestra que el guard se ejecuta después de la recuperación del ancla diferida y que el MATCH inválido entra en la ruta existente de `SIN MATCH`.

## 5. Pruebas de regresión

La cobertura validada en la rama `poc7-paso6-temporal-guard-clean` es:

| Prueba | Resultado |
|---|---:|
| `Find-WordOverlap.TemporalPlacement.Tests.ps1` | 2/2 PASS |
| `Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.TemporalBoundaryCharacterization.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.DeferredAnchorTemporal.Tests.ps1` | 1/1 PASS |
| **Total** | **9/9 PASS** |

La prueba específica de ancla diferida verifica que:

- se recupera exactamente un ancla diferida;
- se produce exactamente un rechazo temporal;
- se entra exactamente una vez en `SIN MATCH`;
- se conserva el resultado esperado de 9 palabras;
- `Extra` recuperado conserva su posición inicial esperada;
- la reconstrucción termina con `Ocho` como última palabra del fixture.

## 6. Alcance arquitectónico

`Find-WordOverlap.ps1` permanece como capa de alineación léxica. No se reintroduce allí la regla temporal basada en el transcript acumulado.

`Reconstruct-WhisperWindows.ps1` es la capa que decide si el MATCH léxico es temporalmente válido frente al prefijo acumulado.

No se modifica como parte de esta resolución:

- la geometría de ventanas;
- `Build-WhisperWords`;
- la lógica histórica de `SIN MATCH`;
- la geometría de audio;
- las reglas de `Convert`/`Build` existentes.

## 7. Geometría de producción y alcance de la fixture

La fixture de tres ventanas es deliberadamente sintética para alcanzar de forma controlada la rama de recuperación diferida. No debe interpretarse como una demostración de que el mismo patrón tenga alta frecuencia bajo la geometría normal de producción.

Con ventanas uniformes de duración `W` y paso `S`, la zona de overlap de la transición `i` es:

```text
zone_i = [i·S, (i-1)·S + W)
```

Para los parámetros documentados de producción (`W=5s`, `S=4s`):

```text
zone_i = [4i, 4i + 1)
```

Las zonas consecutivas están separadas por 3 segundos. La alcanzabilidad de la rama diferida bajo esa geometría y las duraciones reales de tokens requiere una caracterización separada; no se afirma aquí que sea un caso frecuente en producción.

## 8. Cuestión separada: posibles diferidos huérfanos

El análisis sigue dejando una cuestión independiente: una palabra almacenada en `$deferredWordsByText` podría no volver a aparecer como ancla recuperable en una transición posterior bajo ciertas geometrías.

Esto **no forma parte de la resolución temporal de Paso 6** y queda como asunto separado para una auditoría posterior. No se introduce ninguna modificación para resolverlo en este paso.

## 9. Estado final

Paso 6 queda **implementado y validado** en `poc7-paso6-temporal-guard-clean`.

La resolución mantiene la separación de responsabilidades:

```text
Find-WordOverlap
  = alineación léxica

Reconstruct-WhisperWindows
  = validación temporal contra transcript acumulado
```

El guard temporal se ejecuta con el prefijo ya resuelto, incluyendo recuperación de anclas diferidas, y un MATCH rechazado entra por el único dispatch existente de `SIN MATCH`.

La batería de regresión ejecutada después de la corrección finaliza en **9/9 PASS**.