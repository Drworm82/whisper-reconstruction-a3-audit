# PRUEBA 3 — REPETICIONES LEGITIMAS
# Verifica que palabras cortas repetidas legítimamente (y, de, la) no se eliminan incorrectamente

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-legitimate-repetitions.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

Write-Host "=== PRUEBA 3: REPETICIONES LEGITIMAS ==="
Write-Host "Fixture: $fixturePath"
Write-Host "WindowDurationSeconds: 15"
Write-Host "OverlapDurationSeconds: 5"
Write-Host ""

try {
    $result = Invoke-WhisperReconstruction -WhisperXPath $fixturePath `
                                           -WindowDurationSeconds 15 `
                                           -OverlapDurationSeconds 5
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

Write-Host "[OK] Resultado contiene $($wordsArray.Count) palabras"

$countY = 0
$countDe = 0
$countLa = 0

foreach ($w in $wordsArray) {
    $text = $w.Text.ToLower().Trim()
    if ($text -eq "y") { $countY++ }
    if ($text -eq "de") { $countDe++ }
    if ($text -eq "la") { $countLa++ }
}

Write-Host "Ocurrencias en resultado: 'y'=$countY, 'de'=$countDe, 'la'=$countLa"

$fixture = Get-Content -Path $fixturePath -Raw | ConvertFrom-Json
$origY = 0
$origDe = 0
$origLa = 0

foreach ($seg in $fixture.Segments) {
    foreach ($w in $seg.Words) {
        $text = $w.Word.ToLower().Trim()
        if ($text -eq "y") { $origY++ }
        if ($text -eq "de") { $origDe++ }
        if ($text -eq "la") { $origLa++ }
    }
}

Write-Host "Ocurrencias en fixture (todos segmentos): 'y'=$origY, 'de'=$origDe, 'la'=$origLa"

$minExpectedY = 3
$minExpectedDe = 2
$minExpectedLa = 3

$lost = $false

if ($countY -lt $minExpectedY) {
    Write-Host "[FAIL] PERDIDA: 'y' en resultado ($countY) < minimo esperado ($minExpectedY) - posible eliminacion incorrecta"
    $lost = $true
} else {
    Write-Host "[OK] 'y': $countY ocurrencias (esperado >= $minExpectedY)"
}

if ($countDe -lt $minExpectedDe) {
    Write-Host "[FAIL] PERDIDA: 'de' en resultado ($countDe) < minimo esperado ($minExpectedDe) - posible eliminacion incorrecta"
    $lost = $true
} else {
    Write-Host "[OK] 'de': $countDe ocurrencias (esperado >= $minExpectedDe)"
}

if ($countLa -lt $minExpectedLa) {
    Write-Host "[FAIL] PERDIDA: 'la' en resultado ($countLa) < minimo esperado ($minExpectedLa) - posible eliminacion incorrecta"
    $lost = $true
} else {
    Write-Host "[OK] 'la': $countLa ocurrencias (esperado >= $minExpectedLa)"
}

$allText = $wordsArray.Text
$minBlockSize = 3
$duplicateBlocks = $false

for ($i = 0; $i -le $allText.Count - $minBlockSize; $i++) {
    $block = $allText[$i..($i + $minBlockSize - 1)] -join ' '
    $blockNext = $allText[($i + 1)..($i + $minBlockSize)] -join ' '
    if ($block -eq $blockNext) {
        Write-Host "[FAIL] Bloque repetido detectado: $block"
        $duplicateBlocks = $true
        break
    }
}

if (-not $duplicateBlocks) {
    Write-Host "[OK] No hay bloques de 3+ palabras repetidas consecutivamente"
}

if ($lost) {
    Write-Host ""
    Write-Host "=== PRUEBA 3: POSIBLE BUG DETECTADO - Se perdieron ocurrencias legitimas ==="
    exit 1
}

if ($duplicateBlocks) {
    Write-Host ""
    Write-Host "=== PRUEBA 3: POSIBLE BUG DETECTADO - Hay duplicados reales ==="
    exit 1
}

Write-Host ""
Write-Host "=== PRUEBA 3 PASSED ==="
exit 0