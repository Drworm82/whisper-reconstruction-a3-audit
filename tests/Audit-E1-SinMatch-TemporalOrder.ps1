. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== AUDIT E1: SIN MATCH Y ORDEN TEMPORAL ===" -ForegroundColor Cyan
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-TestWindow {
    param([double]$Start, [double]$End, [object[]]$Tokens)
    [PSCustomObject]@{
        Start  = $Start
        End    = $End
        Tokens = @($Tokens)
    }
}

function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

# W0: palabras acumuladas
$w0 = @(
    (T ' A' 5.0 5.3),
    (T ' B' 6.0 6.3),
    (T ' C' 7.0 7.3)
)

# W1 contiene una palabra X temporalmente anterior a A,
# pero no comparte suficientes matches para producir MATCH.
#
# El objetivo es observar si SIN MATCH agrega X al final,
# rompiendo el orden temporal.
$w1 = @(
    (T ' X' 4.0 4.3),
    (T ' Y' 8.0 8.3),
    (T ' Z' 9.0 9.3)
)

$windows = @(
    (New-TestWindow 0 10 $w0),
    (New-TestWindow 5 15 $w1)
)

Write-Host "--- RECONSTRUCCION ---"

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)

    Write-Host ""
    Write-Host "Resultado:"
    foreach ($word in $result) {
        Write-Host "  '$($word.Text.Trim())' [$($word.From)-$($word.To)]"
    }

    Write-Host ""
    Write-Host "--- COMPROBACION TEMPORAL ---"

    $monotonic = $true

    for ($i = 1; $i -lt $result.Count; $i++) {
        if ($result[$i].From -lt $result[$i - 1].From) {
            Write-Host "[ERROR] Orden temporal roto:"
            Write-Host "  indice $($i-1): '$($result[$i-1].Text.Trim())' From=$($result[$i-1].From)"
            Write-Host "  indice $i    : '$($result[$i].Text.Trim())' From=$($result[$i].From)"
            $monotonic = $false
        }
    }

    if ($monotonic) {
        Write-Host "[OK] Orden temporal monotono."
        Write-Host "=== AUDIT E1 PASSED ==="
        exit 0
    }
    else {
        Write-Host "[FAIL] E1: SIN MATCH dejo finalWords fuera de orden." -ForegroundColor Red
        Write-Host "=== AUDIT E1 FAILED ==="
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Reconstruccion fallo: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "=== AUDIT E1 FAILED ==="
    exit 1
}
