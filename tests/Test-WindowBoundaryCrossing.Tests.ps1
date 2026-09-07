$ErrorActionPreference = "Stop"

. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== PRUEBA: PALABRA QUE CRUZA EL LIMITE DE VENTANAS ===" -ForegroundColor Cyan

$words = @(
    [pscustomobject]@{ Text="inicio"; From=0.0; To=0.5 }
    [pscustomobject]@{ Text="LARGA"; From=4.0; To=12.0 }
    [pscustomobject]@{ Text="final"; From=25.0; To=25.5 }
)

$windows = New-WhisperWindows `
    -Words $words `
    -WindowDurationSeconds 10 `
    -OverlapDurationSeconds 3

Write-Host ""
Write-Host "Ventanas generadas: $($windows.Count)"

foreach ($window in $windows) {
    Write-Host ""
    Write-Host "Ventana $($window.Start) -> $($window.End)"
    foreach ($word in $window.Words) {
        Write-Host "  $($word.Text): $($word.From) -> $($word.To)"
    }
}

$found = $false

foreach ($window in $windows) {
    foreach ($word in $window.Words) {
        if ($word.Text -eq "LARGA") {
            $found = $true
        }
    }
}

Write-Host ""

if ($found) {
    Write-Host "[PASS] La palabra LARGA fue conservada." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "[FAIL] BUG CONFIRMADO: la palabra LARGA 4.0 -> 12.0 desaparecio de todas las ventanas." -ForegroundColor Red
    exit 1
}
