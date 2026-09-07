# ============================================================
# REGRESION — ISSUE 1 / E1: SIN MATCH seguido de MATCH
# Verifica que SIN MATCH no deje IDs de la ventana actual sin
# representante y que el transcript permanezca en orden temporal.
# ============================================================

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{ Text = $Text; From = $From; To = $To }
}

function New-TestWindow {
    param([double]$Start, [double]$End, [object[]]$Tokens)
    [PSCustomObject]@{ Start = $Start; End = $End; Tokens = $Tokens }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "[OK] $Message" }
    else { Write-Host "[FAIL] $Message"; $script:pass = $false }
}

function Get-Count {
    param([object[]]$Words, [string]$Text)
    @($Words | Where-Object { $_.Text.Trim().ToLower() -eq $Text.ToLower() }).Count
}

$pass = $true

$w0 = New-TestWindow 0 10 @(
    (New-TestToken 'A' 1 1.3),
    (New-TestToken ' B' 2 2.3),
    (New-TestToken ' C' 3 3.3),
    (New-TestToken ' M' 8 8.3),
    (New-TestToken ' N' 8.5 8.8),
    (New-TestToken ' Q' 9 9.3)
)

$w1 = New-TestWindow 5 15 @(
    (New-TestToken 'X' 0.5 0.8),
    (New-TestToken ' Y' 4 4.3),
    (New-TestToken ' Z' 5 5.3),
    (New-TestToken ' M' 8 8.3),
    (New-TestToken ' N' 8.5 8.8),
    (New-TestToken ' O' 9 9.3)
)

$w2 = New-TestWindow 8 18 @(
    (New-TestToken 'M' 8 8.3),
    (New-TestToken ' N' 8.5 8.8),
    (New-TestToken ' O' 9 9.3),
    (New-TestToken ' R' 11 11.4)
)

Write-Host '=== PRUEBA ISSUE 1 / E1: SIN MATCH -> MATCH ==='
$result = @(Reconstruct-WhisperWindows @($w0, $w1, $w2))

Assert-True ((Get-Count $result 'm') -eq 1) 'M aparece exactamente una vez'
Assert-True ((Get-Count $result 'n') -eq 1) 'N aparece exactamente una vez'
Assert-True ((Get-Count $result 'o') -eq 1) 'O aparece exactamente una vez'
Assert-True ((Get-Count $result 'r') -eq 1) 'R posterior al MATCH se conserva'
Assert-True ((Get-Count $result 'x') -eq 1) 'X anterior al transcript acumulado se conserva'
Assert-True ($result.Count -eq 11) 'Se conservan exactamente 11 palabras'

for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host ("[FAIL] Orden temporal: {0}@{1} sigue a {2}@{3}" -f $result[$i].Text, $result[$i].From, $result[$i-1].Text, $result[$i-1].From)
        $pass = $false
    }
}
Assert-True $pass 'Orden temporal monotono y sin perdida de contenido'

if ($pass) {
    Write-Host '=== PRUEBA ISSUE 1 / E1 PASSED ==='
    exit 0
}

Write-Host '=== PRUEBA ISSUE 1 / E1 FAILED ==='
exit 1
