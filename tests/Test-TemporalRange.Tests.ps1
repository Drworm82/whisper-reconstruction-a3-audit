# PRUEBA 5 — RANGO Y COHERENCIA TEMPORAL
# Verifica coherencia temporal del resultado

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-continuous-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

Write-Host "=== PRUEBA 5: RANGO Y COHERENCIA TEMPORAL ==="
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

Write-Host "[OK] Resultado contiene $($wordsArray.Count) palabras"

$fixture = Get-Content -Path $fixturePath -Raw | ConvertFrom-Json
$minTime = [double]::MaxValue
$maxTime = [double]::MinValue

foreach ($seg in $fixture.Segments) {
    foreach ($w in $seg.Words) {
        if ($w.Start -lt $minTime) { $minTime = $w.Start }
        if ($w.End -gt $maxTime) { $maxTime = $w.End }
    }
}

Write-Host "Rango temporal fixture: $minTime - $maxTime"

$outOfRange = 0
foreach ($w in $wordsArray) {
    if ($w.From -lt $minTime - 1 -or $w.To -gt $maxTime + 1) {
        $fromVal = $w.From
        $toVal = $w.To
        Write-Host "[FAIL] Palabra fuera de rango: '$($w.Text)' From=$fromVal To=$toVal (rango valido: $minTime-$maxTime)"
        $outOfRange++
    }
}
if ($outOfRange -eq 0) {
    Write-Host "[OK] Todas las palabras dentro del rango temporal valido"
} else {
    exit 1
}

$invalidRange = 0
foreach ($w in $wordsArray) {
    if ($w.From -ge $w.To) {
        $fromVal = $w.From
        $toVal = $w.To
        Write-Host "[FAIL] From >= To: '$($w.Text)' From=$fromVal To=$toVal"
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
        Write-Host ("[FAIL] Indice {0}: From={1} < From previo={2}" -f $i, $currFrom, $prevFrom)
        $orderViolations++
        if ($firstBadIndex -eq -1) { $firstBadIndex = $i }
    }
}
if ($orderViolations -eq 0) {
    Write-Host "[OK] From es monotonicamente creciente"
} else {
    Write-Host "[FAIL] $orderViolations violaciones de orden (primera en indice $firstBadIndex)"
    exit 1
}

$badTimestamps = 0
for ($i = 0; $i -lt $wordsArray.Count; $i++) {
    $w = $wordsArray[$i]
    if ($null -eq $w.From -or $null -eq $w.To) {
        Write-Host "[FAIL] Timestamp null en indice $i"
        $badTimestamps++
    } elseif ([double]::IsNaN($w.From) -or [double]::IsNaN($w.To)) {
        Write-Host "[FAIL] Timestamp NaN en indice $i"
        $badTimestamps++
    } elseif ([double]::IsInfinity($w.From) -or [double]::IsInfinity($w.To)) {
        Write-Host "[FAIL] Timestamp Infinity en indice $i"
        $badTimestamps++
    }
}
if ($badTimestamps -eq 0) {
    Write-Host "[OK] Sin timestamps NaN/null/undefined"
} else {
    exit 1
}

$zone1 = $false
$zone2 = $false
$zone3 = $false
$zone4 = $false

foreach ($w in $wordsArray) {
    if ($w.From -ge 0 -and $w.To -le 35) { $zone1 = $true }
    if ($w.From -ge 15 -and $w.To -le 55) { $zone2 = $true }
    if ($w.From -ge 35 -and $w.To -le 75) { $zone3 = $true }
    if ($w.From -ge 55 -and $w.To -le 95) { $zone4 = $true }
}

Write-Host "Zonas temporales presentes: Zona1(0-30)=$zone1, Zona2(20-50)=$zone2, Zona3(40-70)=$zone3, Zona4(60-90)=$zone4"

$missingZones = 0
if (-not $zone1) { Write-Host "[FAIL] Falta zona 0-30s"; $missingZones++ }
if (-not $zone2) { Write-Host "[FAIL] Falta zona 20-50s"; $missingZones++ }
if (-not $zone3) { Write-Host "[FAIL] Falta zona 40-70s"; $missingZones++ }
if (-not $zone4) { Write-Host "[FAIL] Falta zona 60-90s"; $missingZones++ }

if ($missingZones -eq 0) {
    Write-Host "[OK] Resultado conserva palabras de todas las regiones temporales"
} else {
    Write-Host "[FAIL] Faltan $missingZones zonas temporales"
    exit 1
}

Write-Host ""
Write-Host "=== PRUEBA 5 PASSED ==="
exit 0