# POC7 Paso 6 — Deferred Orphan Reconciliation

**Fecha:** 2026-09-11  
**Rama:** `poc7-paso6-temporal-guard-clean`  
**HEAD documentado:** `4f4d89e`  
**Punto de bifurcación:** `63c4d14`

## 1. Propósito

Este documento reconcilia dos auditorías independientes sobre el estado del mecanismo `deferred`, el temporal placement guard y la historia de commits del POC7 Paso 6.

La conclusión principal es que debe distinguirse estrictamente entre la rama de trabajo `poc7-paso6-temporal-guard-clean` y la rama histórica que contiene `30a4c1b`.

## 2. Estado de la rama de trabajo

La rama `poc7-paso6-temporal-guard-clean` se bifurca desde `63c4d14` y **no contiene `30a4c1b` como ancestro**.

`30a4c1b` (`Guard MATCH replacement against prefix boundary`) pertenece a otra línea (`poc7-paso6-temporal-guard` / `reconstruction-fixes`). Ese commit sí eliminó en su propio estado tanto la creación de deferred como el splice normal de un MATCH aceptado, pero esa regresión **no describe la rama `-clean`**.

En `4f4d89e` se conservan:

- creación de candidatos deferred mediante `for ($k = 0; $k -lt $match.CurrentStart; $k++)`;
- almacenamiento en `$deferredWordsByText`;
- splice normal de MATCH mediante `prefix + currentMatch + after`;
- asignación del resultado a `$finalWords`.

Por tanto, no se debe hacer rollback ni reparación de MATCH sobre la rama `-clean` basándose en la regresión de `30a4c1b`.

## 3. Temporal guards

El historial de la rama contiene temporalmente una implementación en `Find-WordOverlap.ps1` basada en:

```powershell
Get-Variable -Name finalWords -Scope 1 -ValueOnly -ErrorAction SilentlyContinue
```

Esa implementación fue introducida en `04fe957` y posteriormente eliminada en `bbf3725`. **No está presente en el HEAD `4f4d89e`.**

El flujo de producción actual tiene un único temporal placement guard activo, en `Reconstruct-WhisperWindows.ps1`:

```powershell
$prefix.Count -gt 0 -and
$currentMatch.Count -gt 0 -and
$currentMatch[0].From -lt $prefix[-1].To
```

Existe además `src/Alignment/Find-WordOverlap-MatchGuard.ps1`, pero es experimental y no forma parte del pipeline integrado de reconstrucción.

## 4. Deferred orphan: qué está demostrado

La hipótesis de `deferred orphan` sigue siendo válida para la rama `-clean` porque la creación de deferred existe y la recuperación depende de una transición futura que seleccione la ocurrencia diferida como anchor recuperable.

La fixture sintética previamente documentada demuestra que una palabra puede entrar en deferred y quedar fuera de `finalWords` si nunca se produce una recuperación posterior. El mecanismo no tiene un `flush` final que reincorpore automáticamente todos los deferred pendientes.

Esto demuestra una **posibilidad estructural de pérdida**, pero no demuestra por sí mismo que Whisper real produzca esa situación.

## 5. Evidencia con datos reales

La ejecución previamente realizada sobre el fixture real local `whispercpp-real-full.json` reportó:

- 17 segmentos/windows nativas;
- 274 words construidas;
- 21 ventanas reconstruidas con geometría 10s/4s;
- `CurrentStart > 0`: 0;
- deferred creados: 0;
- deferred recuperados: 0;
- pérdidas observadas: 0;
- una ruta `SIN MATCH` por drift de retranscripción;
- salida trazada idéntica al baseline: 274 palabras.

Sin embargo, una auditoría independiente verificó que `tests/fixtures/whispercpp-real-full.json` **no está actualmente commiteado en GitHub ni es recuperable del historial del repositorio**. Por ello esos números no son evidencia reproducible desde el estado Git publicado y no deben utilizarse como prueba definitiva de comportamiento real.

La conclusión correcta es solamente que **en esa ejecución local reportada no apareció ningún `CurrentStart > 0`**, no que el mecanismo deferred haya sido validado exhaustivamente contra datos reales reproducibles.

## 6. Corrección de una afirmación histórica

Una auditoría independiente afirmó inicialmente que el commit `30a4c1b` provocaba una regresión de 21 palabras esperadas a 8. La revisión posterior de la historia completa determinó que:

- no existe en el historial del repositorio una aserción `Should -Be 21` correspondiente a ese supuesto;
- el test de integración relevante utiliza otras expectativas y otro fixture;
- `30a4c1b` no es ancestro de `poc7-paso6-temporal-guard-clean`.

Por tanto, la cifra `21 → 8` debe considerarse **descartada como descripción del repositorio/branch de trabajo**.

## 7. Separación de hechos e hipótesis

### Hechos confirmados

- `4f4d89e` es el HEAD documentado de `poc7-paso6-temporal-guard-clean`.
- `63c4d14` es su punto de bifurcación relevante.
- `30a4c1b` no pertenece a esta línea.
- MATCH aceptado conserva el splice `prefix + currentMatch + after`.
- La creación de deferred existe.
- El temporal guard activo está en `Reconstruct-WhisperWindows.ps1`.
- El `Get-Variable -Scope 1` histórico no está activo en el HEAD.
- La fixture sintética demuestra la posibilidad de orphan.

### No demostrado

- Que Whisper real produzca `CurrentStart > 0` en una ejecución reproducible con los fixtures actualmente versionados.
- Que exista pérdida real de palabras causada por deferred orphan en producción.
- Que la igualdad de timestamps dentro de `1e-6` sea el factor causante de una pérdida real.
- Que el temporal guard sea la causa dominante de deferred orphans.

## 8. Siguiente experimento aprobado

No se modifica código en esta etapa.

El siguiente paso es utilizar datos reales de POC7 que estén disponibles y auditables localmente y reproducir el pipeline:

```text
JSON real
  -> Convert-WhisperServer / adaptador correspondiente
  -> Build-WhisperWords
  -> aplicación de offsets absolutos
  -> Reconstruct-WhisperWindows
```

La observación prioritaria es encontrar transiciones con:

```text
CurrentStart > 0
```

Cuando aparezca una, debe seguirse la identidad de cada palabra diferida a través de las ventanas posteriores y determinar si es recuperada, queda huérfana o ya existe equivalentemente en `finalWords`.

Hasta obtener esa evidencia, el hallazgo debe clasificarse como:

**debilidad estructural demostrada / pérdida real en Whisper no demostrada.**

## 9. Decisión de ingeniería

No modificar `Find-WordOverlap.ps1` ni introducir un parche de `deferred` basándose únicamente en la fixture sintética.

No tocar MATCH normal por la regresión de `30a4c1b`, porque esa regresión pertenece a otra rama.

Primero reproducir el comportamiento sobre datos reales auditables. Solo después decidir si corresponde corregir el ciclo de vida de deferred, reforzar invariantes de conservación de palabras o mantener el diseño actual.
