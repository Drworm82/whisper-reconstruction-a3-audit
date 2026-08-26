# PRUEBA 2 — SIN MATCH -> MATCH
# Verifica que después de un SIN MATCH la siguiente transición puede volver a producir MATCH
# sin "ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-match-sinmatch-match.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

Write-Host "=== PRUEBA 2: SIN MATCH -> MATCH ==="
Write-Host "Fixture: $fixturePath"
Write-Host "WindowDurationSeconds: 10"
Write-Host "OverlapDurationSeconds: 4"
Write-Host ""

# Ejecutar pipeline y capturar salida completa
$output = @()
$sb = [System.Text.StringBuilder]::new()

try {
    $result = Invoke-WhisperReconstruction -WhisperXPath $fixturePath `
                                           -WindowDurationSeconds 10 `
                                           -OverlapDurationSeconds 4
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

# Re-ejecutar para capturar la salida de consola (Write-Host del pipeline)
# Usamos PowerShell para capturar stdout
$cmd = "cd '$projectRoot'; . .\src\Load-WhisperReconstruction.ps1; Invoke-WhisperReconstruction -WhisperXPath '.\tests\fixtures\whisperx-match-sinmatch-match.json' -WindowDurationSeconds 10 -OverlapDurationSeconds 4"
$processOutput = powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1

# Analizar salida para detectar secuencia MATCH/SIN MATCH
$transitions = @()
$currentTransition = $null

foreach ($line in $processOutput) {
    if ($line -match "TRANSICION\s+([\d.]+)s\s+->\s+([\d.]+)s") {
        if ($currentTransition) { $transitions += $currentTransition }
        $currentTransition = @{
            From = $matches[1]
            To = $matches[2]
            Type = "UNKNOWN"
            HasErrorNoMap = $false
        }
    } elseif ($line -match "SIN MATCH") {
        if ($currentTransition) { $currentTransition.Type = "SIN_MATCH" }
    } elseif ($line -match "PreviousStart\s+:\s+\d+") {
        if ($currentTransition) { $currentTransition.Type = "MATCH" }
    } elseif ($line -match "ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA") {
        if ($currentTransition) { $currentTransition.HasErrorNoMap = $true }
    }
}
if ($currentTransition) { $transitions += $currentTransition }

Write-Host "Transiciones detectadas: $($transitions.Count)"
foreach ($t in $transitions) {
    $errMsg = ""
    if ($t.HasErrorNoMap) { $errMsg = " (ERROR NO MAPA)" }
    Write-Host "  $($t.From)s -> $($t.To)s : $($t.Type)$errMsg"
}

# Verificar secuencia: MATCH -> SIN MATCH -> MATCH
$hasMatchBefore = $false
$hasSinMatch = $false
$hasMatchAfter = $false
$errorNoMap = $false

foreach ($t in $transitions) {
    if ($t.Type -eq "MATCH" -and -not $hasSinMatch) {
        $hasMatchBefore = $true
    }
    if ($t.Type -eq "SIN_MATCH") {
        $hasSinMatch = $true
    }
    if ($t.Type -eq "MATCH" -and $hasSinMatch) {
        $hasMatchAfter = $true
    }
    if ($t.HasErrorNoMap) {
        $errorNoMap = $true
    }
}

Write-Host ""
Write-Host "Verificaciones:"

if ($hasMatchBefore) {
    Write-Host "[OK] Hubo al menos un MATCH antes del SIN MATCH"
} else {
    Write-Host "[FAIL] No hubo MATCH antes del SIN MATCH"
}

if ($hasSinMatch) {
    Write-Host "[OK] Hubo al menos un SIN MATCH"
} else {
    Write-Host "[FAIL] No hubo SIN MATCH"
}

if ($hasMatchAfter) {
    Write-Host "[OK] Hubo al menos un MATCH despues del SIN MATCH"
} else {
    Write-Host "[FAIL] No hubo MATCH despues del SIN MATCH"
}

if ($errorNoMap) {
    Write-Host "[FAIL] Aparecio 'ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA'"
} else {
    Write-Host "[OK] No aparecio 'ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA'"
}

# Verificar zonas temporales
$hasZone1 = $false  # 0-10s
$hasZone2 = $false  # 6-12s (seg2)
$hasZone3 = $false  # 16-22s (seg3)
$hasZone4 = $false  # 18-28s (seg4)

foreach ($w in $wordsArray) {
    if ($w.From -ge 0 -and $w.To -le 11) { $hasZone1 = $true }
    if ($w.From -ge 5 -and $w.To -le 13) { $hasZone2 = $true }
    if ($w.From -ge 15 -and $w.To -le 23) { $hasZone3 = $true }
    if ($w.From -ge 17 -and $w.To -le 29) { $hasZone4 = $true }
}

if ($hasZone1) { Write-Host "[OK] Zona 0-10s presente" } else { Write-Host "[FAIL] Falta zona 0-10s" }
if ($hasZone2) { Write-Host "[OK] Zona 6-12s presente" } else { Write-Host "[FAIL] Falta zona 6-12s" }
if ($hasZone3) { Write-Host "[OK] Zona 16-22s presente" } else { Write-Host "[FAIL] Falta zona 16-22s" }
if ($hasZone4) { Write-Host "[OK] Zona 18-28s presente" } else { Write-Host "[FAIL] Falta zona 18-28s" }

if (-not $hasZone1 -or -not $hasZone2 -or -not $hasZone3 -or -not $hasZone4) {
    Write-Host "[FAIL] No se conservaron todas las zonas relevantes"
}

# Verificar que no se perdió historial anterior al SIN MATCH
# El SIN MATCH ocurre en transición 6.1->12.1 (W1->W2)
# Las palabras de W0 (0-10s) y W1 (6-16s) deben estar en el resultado
$earlyWords = $wordsArray | Where-Object { $_.From -lt 12 }
if ($earlyWords.Count -gt 0) {
    Write-Host "[OK] Historial anterior al SIN MATCH conservado ($($earlyWords.Count) palabras con From < 12s)"
} else {
    Write-Host "[FAIL] Se perdio historial anterior al SIN MATCH"
}

$allPassed = $hasMatchBefore -and $hasSinMatch -and $hasMatchAfter -and (-not $errorNoMap) -and $hasZone1 -and $hasZone2 -and $hasZone3 -and $hasZone4 -and ($earlyWords.Count -gt 0)

Write-Host ""
if ($allPassed) {
    Write-Host "=== PRUEBA 2 PASSED ==="
    exit 0
} else {
    Write-Host "=== PRUEBA 2 FAILED ==="
    exit 1
}