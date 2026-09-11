# POC7 Paso 6 — Caracterización del guard temporal con patrón real

## Objetivo

Aislar el comportamiento del `Find-WordOverlap` integrado frente al patrón de timestamps observado en la prueba real de audio.

## Evidencia previa

La prueba `Find-WordOverlap.RealJitterCharacterization.Tests.ps1` demostró que, sin alterar los datos del patrón capturado, el algoritmo base encuentra el bloque completo `I` → `84`:

- `Matches = 14`
- `ExactTextMatches = 14`
- `PreviousStart = 0`
- `CurrentStart = 0`
- `PreviousEnd = 14`
- `CurrentEnd = 14`

Esto establece que el matching léxico del patrón es válido.

## Caracterización integrada

Se añade `tests/Find-WordOverlap.IntegratedTemporalGuard.RealJitter.Tests.ps1`, usando el mismo bloque `I` → `84` pero recortado al overlap relevante de la transición. Los anchors son:

- ventana previa: `I @ 4.37s`
- ventana actual: `I @ 4.00s`

La implementación integrada contiene el guard temporal después de seleccionar el mejor candidato. Si el anchor actual comienza antes que el anterior, devuelve `null`.

## Estado

**PENDIENTE DE VALIDACIÓN LOCAL.**

El siguiente paso es ejecutar el nuevo test con Pester 3.4.0. No se modifica todavía el algoritmo de selección ni la regla temporal.

## Próxima acción

```powershell
Invoke-Pester .\tests\Find-WordOverlap.IntegratedTemporalGuard.RealJitter.Tests.ps1
```
