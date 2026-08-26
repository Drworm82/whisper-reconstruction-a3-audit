# PRUEBA 1 — ORDEN TEMPORAL
# Verifica que el resultado final está ordenado por From ascendente

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-continuous-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

Write-Host "=== PRUEBA 1: ORDEN TEMPORAL ==="
Write-Host "Fixture: $fixturePath"
Write-Host "WindowDurationSeconds: 30"
Write-Host "OverlapDurationSeconds: 10"
Write-Host ""

try {
    $result = Invoke-WhisperReconstruction -WhisperXPath $fixturePath `
                                           -WindowDurationSeconds 30 `
                                           -OverlapDurationSeconds 10
    Write-Host "[OK] Pipeline completado sin excepcion"
} catch {
    Write-Host "[FAIL] Pipeline threw exception: $_"
    exit 1
}

$wordsArray = @($result)

if ($wordsArray.Count -eq 0) {
    Write-Host "[FAIL] Resultado vacio"
    exit 1
}

Write-Host "[OK] Resultado no nulo ($($wordsArray.Count) palabras)"

$missingFromTo = 0
for ($i = 0; $i -lt $wordsArray.Count; $i++) {
    $w = $wordsArray[$i]
    if (-not $w.PSObject.Properties.Match("From")) {
        Write-Host "[FAIL] Palabra indice $i ($($w.Text)): falta propiedad From"
        $missingFromTo++
    }
    if (-not $w.PSObject.Properties.Match("To")) {
        Write-Host "[FAIL] Palabra indice $i ($($w.Text)): falta propiedad To"
        $missingFromTo++
    }
}
if ($missingFromTo -eq 0) {
    Write-Host "[OK] Todas las palabras tienen From y To"
} else {
    exit 1
}

$invalidRange = 0
for ($i = 0; $i -lt $wordsArray.Count; $i++) {
    $w = $wordsArray[$i]
    if ($w.From -ge $w.To) {
        $fromVal = $w.From
        $toVal = $w.To
        Write-Host "[FAIL] Palabra indice $i ($($w.Text)): From=$fromVal >= To=$toVal"
        $invalidRange++
    }
}
if ($invalidRange -eq 0) {
    Write-Host "[OK] Todas las palabras tienen From < To"
} else {
    exit 1
}

$orderViolations = 0
$firstBadIndex = -1
for ($i = 1; $i -lt $wordsArray.Count; $i++) {
    $currFrom = $wordsArray[$i].From
    $prevFrom = $wordsArray[$i-1].From
    if ($currFrom -lt $prevFrom) {
        Write-Host ("[FAIL] Violacion de orden en indice {0}: From={1} < From previo={2}" -f $i, $currFrom, $prevFrom)
        $orderViolations++
        if ($firstBadIndex -eq -1) { $firstBadIndex = $i }
    }
}
if ($orderViolations -eq 0) {
    Write-Host "[OK] Resultado ordenado por From ascendente"
} else {
    Write-Host "[FAIL] Se encontraron $orderViolations violaciones de orden (primera en indice $firstBadIndex)"
    exit 1
}

Write-Host ""
Write-Host "=== PRUEBA 1 PASSED ==="
exit 0