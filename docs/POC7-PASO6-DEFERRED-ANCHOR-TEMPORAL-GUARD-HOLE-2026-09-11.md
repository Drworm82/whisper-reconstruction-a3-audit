# POC7 Paso 6 — Deferred-anchor temporal guard: resolución

**Fecha:** 2026-09-11  
**Rama:** `poc7-paso6-temporal-guard-clean`  
**Estado:** Paso 6 implementado y validado; auditoría separada de ciclo de vida de deferred en caracterización.

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

## 4. Evidencia reproducible del guard temporal

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

## 5. Pruebas de regresión de Paso 6

La cobertura validada antes de la auditoría de ciclo de vida de deferred fue:

| Prueba | Resultado |
|---|---:|
| `Find-WordOverlap.TemporalPlacement.Tests.ps1` | 2/2 PASS |
| `Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.TemporalBoundaryCharacterization.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1` | 2/2 PASS |
| `Reconstruct-WhisperWindows.DeferredAnchorTemporal.Tests.ps1` | 1/1 PASS |
| **Total** | **9/9 PASS** |

## 6. Auditoría separada: ciclo de vida de deferred

Se introdujo una suite de caracterización independiente:

```text
tests/Reconstruct-WhisperWindows.DeferredLifecycle.Characterization.Tests.ps1
```

El primer caso reutiliza el patrón ya validado de ancla diferida y comprueba que la recuperación existente continúa produciendo exactamente una ocurrencia. Este caso pasó.

El segundo caso caracteriza un **deferred orphan**: `X` aparece antes del ancla seleccionada, entra en `$deferredWordsByText`, y las ventanas posteriores avanzan a una zona temporal donde `X` no vuelve a ser candidato de recuperación. La expectativa de caracterización es que `X` permanezca en el transcript final.

Resultado ejecutado en PowerShell/Pester 3.4.0:

```text
Describing Reconstruct-WhisperWindows deferred word lifecycle characterization
 [+] preserves the existing deferred-anchor recovery behavior 59ms
 [-] characterizes that a deferred occurrence can remain without recovery 18ms
   Expected: {1}
   But was:  {0}
Tests completed in 77ms
Passed: 1 Failed: 1 Skipped: 0 Pending: 0 Inconclusive: 0
```

La primera prueba confirma que la recuperación existente sigue funcionando. La segunda reproduce de forma determinista que la ocurrencia `X` no aparece en el resultado final.

Esto establece el hallazgo como **caracterización Pester reproducible de pérdida de un deferred no recuperado**, sin modificar todavía el código de producción.

## 7. Alcance y semántica aún abierta

La existencia del orphan y su pérdida están demostradas por la fixture. Lo que todavía debe decidirse es la política semántica correcta para un deferred que llega al final de su vida útil sin recuperación.

No se asume todavía que la solución correcta sea insertar automáticamente todos los deferred restantes en `finalWords`. Las alternativas a caracterizar incluyen una política explícita de finalización/expiración y sus efectos sobre duplicados, orden temporal y palabras que sean meramente candidatas a ancla.

También queda por medir la frecuencia del fenómeno con capturas reales de POC7. La fixture sintética demuestra posibilidad y pérdida, no frecuencia de producción.

## 8. Geometría de producción

La fixture de tres ventanas es deliberadamente sintética para alcanzar de forma controlada la rama de recuperación y el caso orphan. Con ventanas uniformes de duración `W` y paso `S`, la zona de overlap de la transición `i` es:

```text
zone_i = [i·S, (i-1)·S + W)
```

Para los parámetros documentados de producción (`W=5s`, `S=4s`):

```text
zone_i = [4i, 4i + 1)
```

Las zonas consecutivas están separadas por 3 segundos. La fixture demuestra pérdida cuando un deferred queda fuera de toda futura oportunidad de recuperación; la frecuencia real bajo la geometría de audio de producción permanece abierta.

## 9. Estado actual

Paso 6 queda **implementado y validado**.

La auditoría posterior encontró un problema independiente de ciclo de vida:

```text
accepted MATCH
  → words before selected anchor become deferred
  → deferred is omitted from newFinal
  → no later exact recovery
  → occurrence disappears silently
```

No se ha aplicado todavía una corrección de producción para este problema. El siguiente paso debe ser decidir y caracterizar la política correcta de finalización de deferred antes de modificar `Reconstruct-WhisperWindows.ps1`.
