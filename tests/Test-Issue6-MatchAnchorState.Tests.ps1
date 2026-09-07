# PRUEBA ISSUE 6 — ANCLA DESCARTADA -> MATCH POSTERIOR

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

Write-Host "=== PRUEBA ISSUE 6: ANCLA DESCARTADA -> MATCH POSTERIOR ==="
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{ Text = $Text; From = $From; To = $To }
}

function New-TestWindow {
    param([double]$Start, [double]$End, [object[]]$Tokens)
    [PSCustomObject]@{ Start = $Start; End = $End; Tokens = @($Tokens) }
}

function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

$w0 = @(
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9)
)

$w1 = @(
    (T ' X' 8.2 8.5),
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9)
)

$w2 = @(
    (T ' X' 8.2 8.5),
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9),
    (T ' D' 11.0 11.4)
)

$windows = @(
    (New-TestWindow 0 10 $w0),
    (New-TestWindow 5 15 $w1),
    (New-TestWindow 8 18 $w2)
)

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)
} catch {
    Write-Host "[FAIL] Reconstruct-WhisperWindows lanzo una excepcion: $_"
    exit 1
}

$text = ($result | ForEach-Object { $_.Text }) -join ' '
Write-Host "Resultado: $text"
Write-Host "Palabras: $($result.Count)"

$expected = 'X A B C D'
if ($text -ne $expected) {
    Write-Host "[FAIL] Texto final inesperado"
    Write-Host "Esperado: $expected"
    Write-Host "Obtenido: $text"
    exit 1
}

if ($result.Count -ne 5) {
    Write-Host "[FAIL] Conteo inesperado: $($result.Count), esperado 5"
    exit 1
}

$xWords = @($result | Where-Object { $_.Text -eq 'X' })
if ($xWords.Count -ne 1) {
    Write-Host "[FAIL] Se esperaban 1 ocurrencia de X, se obtuvieron $($xWords.Count)"
    exit 1
}

if ([math]::Abs($xWords[0].From - 8.2) -gt 0.000001 -or [math]::Abs($xWords[0].To - 8.5) -gt 0.000001) {
    Write-Host "[FAIL] X recuperada con timestamps incorrectos: From=$($xWords[0].From) To=$($xWords[0].To)"
    exit 1
}

for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host "[FAIL] Orden temporal no monotono en indice $i"
        exit 1
    }
}

Write-Host "[OK] El segundo MATCH se completo sin perder el ancla X"
Write-Host "[OK] X aparece exactamente una vez con el timing esperado"
Write-Host "[OK] Historia y contenido posterior conservados"
Write-Host "[OK] 5 palabras finales"
Write-Host "[OK] Orden temporal monotono"
Write-Host ""
Write-Host "=== PRUEBA ISSUE 6 PASSED ==="
exit 0
