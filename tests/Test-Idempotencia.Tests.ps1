# PRUEBA — IDEMPOTENCIA
#
# Verifica que ejecutar Reconstruct-WhisperWindows dos veces sobre exactamente
# el mismo array de $windows produce un resultado identico en:
#   - Count
#   - Text (en orden)
#   - From (en orden)
#   - To (en orden)
#   - Orden relativo de las palabras
#   - Id
#
# Esto NO es una prueba formal de ausencia de estado oculto; es una prueba de
# regresion puntual sobre un input concreto. Reconstruct-WhisperWindows no usa
# variables script:/global:, por lo que no se detecto ninguna razon en el
# codigo para esperar no-idempotencia, pero se deja esta prueba para
# detectarla si aparece.
#
# Se reutiliza el mismo diseno de ventanas de Test-NoMatchThenMatch.Tests.ps1
# (MATCH -> SIN MATCH -> MATCH) para ejercitar tambien las rutas con estado
# (previousOverlapMap) mas propensas a acumular efectos entre llamadas.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA: IDEMPOTENCIA ==="

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

$w0 = [PSCustomObject]@{
    Start = 0.0
    End   = 10.0
    Tokens = @(
        New-TestToken 'uno' 0.1 0.9
        New-TestToken ' dos' 1.1 1.9
        New-TestToken ' tres' 2.1 2.9
        New-TestToken ' cuatro' 3.1 3.9
        New-TestToken ' cinco' 6.1 6.9
        New-TestToken ' seis' 7.1 7.9
        New-TestToken ' siete' 8.1 8.9
        New-TestToken ' ocho' 9.1 9.9
    )
}

$w1 = [PSCustomObject]@{
    Start = 5.0
    End   = 15.0
    Tokens = @(
        New-TestToken 'cinco' 6.1 6.9
        New-TestToken ' seis' 7.1 7.9
        New-TestToken ' siete' 8.1 8.9
        New-TestToken ' ocho' 9.1 9.9
        New-TestToken ' nueve' 10.1 10.9
        New-TestToken ' diez' 11.1 11.9
        New-TestToken ' once' 12.1 12.9
        New-TestToken ' doce' 13.1 13.9
    )
}

$w2 = [PSCustomObject]@{
    Start = 13.5
    End   = 20.0
    Tokens = @(
        New-TestToken 'palabraA' 14.1 14.9
        New-TestToken ' palabraB' 15.1 15.9
        New-TestToken ' palabraC' 16.1 16.9
        New-TestToken ' alpha' 17.1 17.9
        New-TestToken ' beta' 18.1 18.9
        New-TestToken ' gamma' 19.1 19.9
    )
}

$w3 = [PSCustomObject]@{
    Start = 14.0
    End   = 24.0
    Tokens = @(
        New-TestToken 'palabraA' 14.1 14.9
        New-TestToken ' palabraB' 15.1 15.9
        New-TestToken ' palabraC' 16.1 16.9
        New-TestToken ' alpha' 17.1 17.9
        New-TestToken ' beta' 18.1 18.9
        New-TestToken ' gamma' 19.1 19.9
        New-TestToken ' delta' 20.1 20.9
        New-TestToken ' epsilon' 21.1 21.9
    )
}

$windows = @($w0, $w1, $w2, $w3)

# Ejecucion 1
$null = Start-Transcript -Path (Join-Path $env:TEMP ("whisper-idem-1-" + [Guid]::NewGuid().ToString() + ".txt")) 
$result1 = Reconstruct-WhisperWindows $windows
Stop-Transcript | Out-Null

# Ejecucion 2 (mismo input, misma referencia de array)
$null = Start-Transcript -Path (Join-Path $env:TEMP ("whisper-idem-2-" + [Guid]::NewGuid().ToString() + ".txt"))
$result2 = Reconstruct-WhisperWindows $windows
Stop-Transcript | Out-Null

$words1 = @($result1)
$words2 = @($result2)

Write-Host "Ejecucion 1: $($words1.Count) palabras"
Write-Host "Ejecucion 2: $($words2.Count) palabras"
Write-Host ""

# 1. Count
if ($words1.Count -ne $words2.Count) {
    Write-Host "[FAIL] Count difiere: ejecucion1=$($words1.Count) vs ejecucion2=$($words2.Count)"
    $pass = $false
} else {
    Write-Host "[OK] Count identico: $($words1.Count)"
}

$minCount = [Math]::Min($words1.Count, $words2.Count)

# 2. Text, From, To, Id en orden
$textMismatches = 0
$fromMismatches = 0
$toMismatches = 0
$idMismatches = 0

for ($i = 0; $i -lt $minCount; $i++) {
    if ($words1[$i].Text -ne $words2[$i].Text) {
        Write-Host ("[FAIL] Text difiere en indice {0}: '{1}' vs '{2}'" -f $i, $words1[$i].Text, $words2[$i].Text)
        $textMismatches++
    }
    if ($words1[$i].From -ne $words2[$i].From) {
        Write-Host ("[FAIL] From difiere en indice {0}: {1} vs {2}" -f $i, $words1[$i].From, $words2[$i].From)
        $fromMismatches++
    }
    if ($words1[$i].To -ne $words2[$i].To) {
        Write-Host ("[FAIL] To difiere en indice {0}: {1} vs {2}" -f $i, $words1[$i].To, $words2[$i].To)
        $toMismatches++
    }
    if ($words1[$i].Id -ne $words2[$i].Id) {
        Write-Host ("[FAIL] Id difiere en indice {0}: '{1}' vs '{2}'" -f $i, $words1[$i].Id, $words2[$i].Id)
        $idMismatches++
    }
}

if ($textMismatches -eq 0) { Write-Host "[OK] Text identico en todos los indices comunes" } else { $pass = $false }
if ($fromMismatches -eq 0) { Write-Host "[OK] From identico en todos los indices comunes" } else { $pass = $false }
if ($toMismatches -eq 0) { Write-Host "[OK] To identico en todos los indices comunes" } else { $pass = $false }
if ($idMismatches -eq 0) { Write-Host "[OK] Id identico en todos los indices comunes" } else { $pass = $false }

# 3. Orden relativo (comparacion de la secuencia completa de Text como proxy de orden)
$order1 = ($words1 | ForEach-Object { $_.Text }) -join '|'
$order2 = ($words2 | ForEach-Object { $_.Text }) -join '|'

if ($order1 -ne $order2) {
    Write-Host "[FAIL] El orden de las palabras difiere entre ejecuciones"
    $pass = $false
} else {
    Write-Host "[OK] Orden de palabras identico entre ejecuciones"
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA IDEMPOTENCIA PASSED ==="
    exit 0
} else {
    Write-Host "=== PRUEBA IDEMPOTENCIA FAILED ==="
    exit 1
}
