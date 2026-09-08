. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== AUDIT ISSUE 1: UMBRAL MATCHES = 3 ===" -ForegroundColor Cyan

function W($text, $from, $to, $key) {
    [pscustomobject]@{
        Text = $text
        From = [double]$from
        To   = [double]$to
        Key  = $key
        Id   = "test-$from"
    }
}

$pass = $true

# Caso A: solamente 2 matches consecutivos.
# Debe NO considerarse MATCH con el umbral actual.
$prev2 = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b")
)

$curr2 = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b")
)

$r2 = Find-WordOverlap -previousWords $prev2 -currentWords $curr2

Write-Host ""
Write-Host "--- Caso A: exactamente 2 matches ---"
if ($null -eq $r2) {
    Write-Host "[OK] 2 matches NO producen MATCH (umbral actual >= 3)"
} else {
    Write-Host "[ERROR] 2 matches produjeron MATCH: Matches=$($r2.Matches)"
    $pass = $false
}

# Caso B: 3 matches consecutivos.
# Debe producir MATCH.
$prev3 = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b"),
    (W "C" 5.8 6.1 "c")
)

$curr3 = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b"),
    (W "C" 5.8 6.1 "c")
)

$r3 = Find-WordOverlap -previousWords $prev3 -currentWords $curr3

Write-Host ""
Write-Host "--- Caso B: exactamente 3 matches ---"
if ($null -ne $r3 -and $r3.Matches -eq 3) {
    Write-Host "[OK] 3 matches producen MATCH"
    Write-Host "    PreviousStart = $($r3.PreviousStart)"
    Write-Host "    CurrentStart  = $($r3.CurrentStart)"
} else {
    Write-Host "[ERROR] 3 matches NO produjeron el MATCH esperado"
    $pass = $false
}

# Caso C: 2 palabras reales coincidentes + una palabra distinta.
# Sirve para comprobar que no se está fabricando un MATCH artificial.
$prevC = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b"),
    (W "X" 5.8 6.1 "x")
)

$currC = @(
    (W "A" 5.0 5.3 "a"),
    (W "B" 5.4 5.7 "b"),
    (W "Y" 5.8 6.1 "y")
)

$rC = Find-WordOverlap -previousWords $prevC -currentWords $currC

Write-Host ""
Write-Host "--- Caso C: 2 matches + divergencia ---"
if ($null -eq $rC) {
    Write-Host "[OK] No se genero MATCH con solo 2 coincidencias"
} else {
    Write-Host "[ERROR] Se genero MATCH artificial con solo 2 coincidencias: Matches=$($rC.Matches)"
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "=== AUDIT ISSUE 1 PASSED ==="
    exit 0
}

Write-Host "=== AUDIT ISSUE 1 FAILED ===" -ForegroundColor Red
exit 1
