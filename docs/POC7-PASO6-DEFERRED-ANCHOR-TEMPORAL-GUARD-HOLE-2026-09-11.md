# POC7 Paso 6 — Deferred-anchor temporal guard hole

**Fecha:** 2026-09-11  
**Rama:** `poc7-paso6-temporal-guard-clean`  
**Estado:** hallazgo caracterizado; no se propone todavía un cambio de producción.

## 1. Contexto

Paso 6 mueve la validación de colocación temporal desde `Find-WordOverlap.ps1` hacia `Reconstruct-WhisperWindows.ps1`, donde existe el estado acumulado necesario para decidir si un MATCH puede sustituir correctamente el prefijo reconstruido.

La regla temporal actualmente caracterizada es:

```powershell
$prefix.Count -gt 0 -and
$currentMatch.Count -gt 0 -and
$currentMatch[0].From -lt $prefix[-1].To
```

Si la condición es verdadera, el MATCH debe ser rechazado (`$match = $null`) para que continúe la rama existente de `SIN MATCH`.

La implementación actual del guard intenta resolver la frontera del prefijo mediante `$previousOverlapMap` y, como respaldo, mediante una búsqueda en `$finalWords`.

## 2. Fixture mínimo de tres ventanas

El siguiente fixture caracteriza específicamente la interacción con `$deferredWordsByText`.

### W0 — ventana base

```text
Uno    0.0 → 1.0
Dos    1.0 → 2.0
Tres   2.0 → 3.0
Cuatro 3.0 → 4.0
Cinco  4.0 → 5.0
Seis   5.0 → 6.0
Siete  6.0 → 7.0
```

### W1 — introduce `Extra` antes del MATCH

```text
Extra  4.0 → 4.3
Cinco  4.3 → 5.0
Seis   5.0 → 6.0
Siete  6.0 → 6.8
```

En W0 → W1, la zona de overlap es `[4.0, 7.0)`.

El mejor MATCH es:

```text
PreviousStart  = 0
CurrentStart   = 1
PreviousConsumed = 3
CurrentConsumed  = 3
```

Por tanto, `Extra` queda antes del MATCH y entra en `$deferredWordsByText` en lugar de `$finalWords`.

El guard no rechaza este MATCH porque la frontera acumulada es `4.0` y el primer elemento del MATCH es `Cinco`, cuyo `From` es `4.3`.

Estado conceptual tras W0 → W1:

```text
$finalWords = Uno, Dos, Tres, Cuatro, Cinco, Seis, Siete
$deferredWordsByText["extra"] = Extra(4.0 → 4.3, Id "1-0")
```

### W2 — recupera `Extra` como ancla

Para forzar la ruta de recuperación diferida, W2 comienza en `4.1`:

```text
Extra  3.9 → 4.4
Cinco  4.4 → 5.1
Seis   5.1 → 6.1
Ocho   6.1 → 7.0
```

El `From=3.9` de `Extra` es intencional. El `To=4.4` se mantiene para que `Extra` permanezca dentro de la zona de overlap `[4.1, 9.0)`.

En W1 → W2, el mejor MATCH es:

```text
PreviousStart = 0
CurrentStart  = 0
CurrentConsumed = 3
```

El ancla previa es `Extra` de W1, con Id `"1-0"`.

## 3. Hueco demostrado en el guard

En el momento en que se ejecuta el guard:

```text
$guardMatchedWord = $prevOverlap[0] = Extra (Id "1-0")
```

Pero ese Id no existe en `$previousOverlapMap`, porque `$finalWords` todavía no contiene `Extra`.

Tampoco aparece mediante el escaneo de `$finalWords`.

Consecuencia:

```text
$guardPrefixCount = $null
```

y el guard termina sin evaluar ninguna comparación temporal.

Posteriormente, la lógica normal de MATCH sí dispone de un tercer mecanismo: consulta `$deferredWordsByText`, encuentra el `Extra` diferido, lo recupera y lo inserta en `$finalWords`.

Esto demuestra una divergencia entre la información que utiliza el guard y la información que utiliza la resolución real de `$prefixCount`.

## 4. Violación temporal reproducible

Con W2.`Extra.From = 3.9`, después de la recuperación diferida, la reconstrucción tiene conceptualmente:

```text
$prefix = Uno, Dos, Tres, Cuatro
$prefix[-1].To = 4.0

$currentMatch[0] = Extra(W2)
$currentMatch[0].From = 3.9
```

Por tanto:

```text
3.9 < 4.0
```

La regla temporal es verdadera, pero el guard que se ejecuta antes de la recuperación diferida nunca llega a evaluarla.

El resultado sintético observado es una secuencia cuyo orden temporal de inicio contiene:

```text
Cuatro  3.0 → 4.0
Extra   3.9 → 4.4
```

Es decir, `Extra` comienza antes de que termine el prefijo acumulado. Este caso caracteriza una violación real de la regla temporal en la rama de recuperación diferida.

## 5. Geometría de producción

Con ventanas uniformes de duración `W` y paso `S`, la zona de overlap de la transición `i` es:

```text
zone_i = [i·S, (i-1)·S + W)
```

y la siguiente:

```text
zone_(i+1) = [(i+1)·S, i·S + W)
```

Para los parámetros documentados de producción (`W=5s`, `S=4s`):

```text
zone_i     = [4i, 4i + 1)
zone_i+1   = [4i + 4, 4i + 5)
```

Las zonas consecutivas están separadas por 3 segundos.

Esto hace que el fixture anterior sea una construcción sintética para alcanzar la rama diferida consecutiva. La existencia del hueco lógico está demostrada independientemente de su frecuencia de activación en producción.

No se establece en este documento que la rama sea alcanzable con palabras normales de Whisper bajo la geometría de producción. Esa cuestión requiere una caracterización separada del filtro de overlap, la posición posible del diferido dentro de la ventana y las duraciones máximas plausibles de los tokens.

## 6. Hallazgo arquitectónico

El guard temporal actual duplica parcialmente la resolución de `$prefixCount`:

```text
Guard:
  previousOverlapMap
  └── búsqueda en finalWords

Resolución real de MATCH:
  previousOverlapMap
  ├── búsqueda en finalWords
  └── recuperación desde deferredWordsByText
```

Por tanto, el guard puede carecer del estado que la reconstrucción utiliza posteriormente para establecer la frontera temporal real.

Este documento **no prescribe todavía** si la solución correcta es ampliar el guard para conocer los diferidos o trasladar la validación a un punto posterior de la reconstrucción, una vez resuelto definitivamente el prefijo. Esa decisión queda pendiente de la auditoría del flujo completo.

## 7. Hallazgo separado: posibles diferidos huérfanos

El mismo análisis revela una cuestión independiente: bajo la geometría actual de producción, una palabra que se almacena en `$deferredWordsByText` puede no volver a aparecer como ancla recuperable en una transición posterior.

Esto no se clasifica aquí como parte del bug temporal de Paso 6. Debe analizarse por separado como posible pérdida silenciosa de palabras diferidas.

## 8. Alcance y estado

Este documento caracteriza un hueco de cobertura del guard y un caso sintético reproducible de violación temporal en la rama diferida.

No modifica:

- `Find-WordOverlap.ps1`
- `Reconstruct-WhisperWindows.ps1`
- la geometría de ventanas
- `Build-WhisperWords`
- la lógica existente de `SIN MATCH`

La implementación de Paso 6 permanece en el estado validado del commit `bbf3725` hasta que se determine el punto correcto de validación y se añadan las pruebas correspondientes.
