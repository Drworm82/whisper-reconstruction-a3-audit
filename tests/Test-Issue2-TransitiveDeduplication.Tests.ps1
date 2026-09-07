# ============================================================
# PRUEBA — ISSUE 2: DEDUPLICACION TRANSITIVA
#
# Regresion minima del caso historico T1:
#   W0 [0,10] : ... X(8.5)
#   W1 [5,15] : ... (omite X)
#   W2 [8,18] : X(8.5) ...
#
# El evento X sobrevive en finalWords desde W0, pero no existe en
# la transcripcion inmediata W1. Level 1 no puede absorber W2.X;
# Level 2 debe comparar contra el transcript acumulado y conservar
# una sola representacion del evento.
# ============================================================

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-TestWindow {
    param(
        [double]$Start,
        [double]$End,
        [object[]]$Tokens
    )
    [PSCustomObject]@{
        Start  = $Start
        End    = $End
        Tokens = $Tokens
    }
}

function Get-Texts {
    param([object[]]$Words)
    (($Words | ForEach-Object { $_.Text }) -join ' ')
}

function Assert-OrderedTimestamps {
    param([object[]]$Words)
    for ($i = 1; $i -lt $Words.Count; $i++) {
        if ($Words[$i].From -lt $Words[$i - 1].From) {
            Write-Host ("[FAIL] Orden temporal: '{0}' ({1}) sigue a '{2}' ({3})" -f $Words[$i].Text, $Words[$i].From, $Words[$i - 1].Text, $Words[$i - 1].From)
            return $false
        }
    }
    return $true
}

function New-T1Windows {
    param([double]$FinalXFrom)

    $w0 = New-TestWindow 0.0 10.0 @(
        (New-TestToken 'uno'     0.6 1.2),
        (New-TestToken ' dos'    1.8 2.4),
        (New-TestToken ' tres'   3.0 3.6),
        (New-TestToken ' cuatro' 4.2 4.8),
        (New-TestToken ' cinco'  5.0 5.6),
        (New-TestToken ' seis'   6.0 6.6),
        (New-TestToken ' siete'  7.0 7.6),
        (New-TestToken ' X'      8.5 9.0)
    )

    $w1 = New-TestWindow 5.0 15.0 @(
        (New-TestToken 'seis'    6.0 6.6),
        (New-TestToken ' siete'  7.0 7.6),
        (New-TestToken ' ocho'   9.2 9.8),
        (New-TestToken ' nueve' 10.2 10.8)
    )

    $w2 = New-TestWindow 8.0 18.0 @(
        (New-TestToken 'X'       $FinalXFrom ($FinalXFrom + 0.5)),
        (New-TestToken ' alpha'  10.5 11.1),
        (New-TestToken ' beta'   11.5 12.1),
        (New-TestToken ' gamma'  12.5 13.1)
    )

    return @($w0, $w1, $w2)
}

Write-Host "=== PRUEBA ISSUE 2: DEDUPLICACION TRANSITIVA ==="
Write-Host ""

# ------------------------------------------------------------
# CASO A: T1, drift 0.0s — regresion minima
# ------------------------------------------------------------
Write-Host "--- CASO A: T1 sin drift ---"

$resultA = @(Reconstruct-WhisperWindows (New-T1Windows -FinalXFrom 8.5))
$textA = Get-Texts $resultA
$xsA = @($resultA | Where-Object { $_.Text.Trim().ToLower() -eq 'x' })

if ($resultA.Count -eq 12) {
    Write-Host "[OK] 12 palabras"
} else {
    Write-Host ("[FAIL] {0} palabras; esperado 12" -f $resultA.Count)
    $pass = $false
}

$expectedA = 'uno dos tres cuatro cinco seis siete X ocho nueve alpha beta gamma'
if ($textA -eq $expectedA) {
    Write-Host "[OK] Texto final exacto"
} else {
    Write-Host ("[FAIL] Texto obtenido: '{0}'" -f $textA)
    Write-Host ("       Esperado:       '{0}'" -f $expectedA)
    $pass = $false
}

if ($xsA.Count -eq 1 -and [math]::Abs($xsA[0].From - 8.5) -lt 0.0001) {
    Write-Host "[OK] X aparece una sola vez y conserva la ocurrencia acumulada de W0"
} else {
    Write-Host ("[FAIL] X aparece {0} veces o no conserva From=8.5" -f $xsA.Count)
    $pass = $false
}

if (Assert-OrderedTimestamps $resultA) {
    Write-Host "[OK] Timestamps monotonicos"
} else {
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO B: T1 con drift transitorio de 0.3s — debe absorber
# ------------------------------------------------------------
Write-Host "--- CASO B: T1 con drift transitorio de 0.3s ---"

$resultB = @(Reconstruct-WhisperWindows (New-T1Windows -FinalXFrom 8.8))
$xsB = @($resultB | Where-Object { $_.Text.Trim().ToLower() -eq 'x' })

if ($xsB.Count -eq 1) {
    Write-Host "[OK] X aparece una sola vez con drift 0.3s"
} else {
    Write-Host ("[FAIL] X aparece {0} veces con drift 0.3s; esperado 1" -f $xsB.Count)
    $pass = $false
}

if ($resultB.Count -eq 12) {
    Write-Host "[OK] 12 palabras con drift 0.3s"
} else {
    Write-Host ("[FAIL] {0} palabras con drift 0.3s; esperado 12" -f $resultB.Count)
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO C: T1 con drift de 1.2s — NO debe absorber transitoriamente
# ------------------------------------------------------------
Write-Host "--- CASO C: T1 con drift transitorio de 1.2s ---"

$resultC = @(Reconstruct-WhisperWindows (New-T1Windows -FinalXFrom 9.7))
$xsC = @($resultC | Where-Object { $_.Text.Trim().ToLower() -eq 'x' })

if ($xsC.Count -eq 2) {
    Write-Host "[OK] X aparece 2 veces con drift 1.2s (limite transitorio 0.5s)"
} else {
    Write-Host ("[FAIL] X aparece {0} veces con drift 1.2s; esperado 2" -f $xsC.Count)
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO D: count mismatch — no deduplicar 2 eventos acumulados
# contra una sola ocurrencia actual.
# ------------------------------------------------------------
Write-Host "--- CASO D: count mismatch ---"

$d0 = New-TestWindow 0.0 10.0 @(
    (New-TestToken 'uno' 0.5 1.0),
    (New-TestToken ' X'  8.0 8.5),
    (New-TestToken ' X'  8.7 9.2)
)
$d1 = New-TestWindow 5.0 15.0 @(
    (New-TestToken 'uno' 5.5 6.0),
    (New-TestToken 'dos' 6.5 7.0)
)
$d2 = New-TestWindow 8.0 18.0 @(
    (New-TestToken 'X'   8.1 8.6),
    (New-TestToken ' fin' 10.0 10.5)
)

$resultD = @(Reconstruct-WhisperWindows @($d0, $d1, $d2))
$xsD = @($resultD | Where-Object { $_.Text.Trim().ToLower() -eq 'x' })

if ($xsD.Count -eq 3) {
    Write-Host "[OK] Count mismatch no fusiona las dos X acumuladas y conserva la X actual"
} else {
    Write-Host ("[FAIL] X aparece {0} veces; esperado 3" -f $xsD.Count)
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO E: dos eventos distintos separados 0.6s — no fusionar
# ------------------------------------------------------------
Write-Host "--- CASO E: eventos legitimos separados 0.6s ---"

$e0 = New-TestWindow 0.0 10.0 @(
    (New-TestToken 'inicio' 0.5 1.0),
    (New-TestToken ' X'     8.4 8.8),
    (New-TestToken ' X'     9.0 9.4)
)
$e1 = New-TestWindow 5.0 15.0 @(
    (New-TestToken 'inicio' 5.5 6.0),
    (New-TestToken 'medio'  6.5 7.0)
)
$e2 = New-TestWindow 8.0 18.0 @(
    (New-TestToken 'X'      8.4 8.8),
    (New-TestToken ' X'     9.0 9.4),
    (New-TestToken ' final' 10.0 10.5)
)

$resultE = @(Reconstruct-WhisperWindows @($e0, $e1, $e2))
$xsE = @($resultE | Where-Object { $_.Text.Trim().ToLower() -eq 'x' })

if ($xsE.Count -eq 2) {
    Write-Host "[OK] Dos eventos X separados 0.6s se conservan"
} else {
    Write-Host ("[FAIL] X aparece {0} veces; esperado 2" -f $xsE.Count)
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO F: puntuacion / Key vacia no debe activar Level 2
# ------------------------------------------------------------
Write-Host "--- CASO F: puntuacion / empty Key ---"

$f0 = New-TestWindow 0.0 10.0 @(
    (New-TestToken 'inicio' 0.5 1.0),
    (New-TestToken ' --'    8.0 8.3),
    (New-TestToken ' --'    8.8 9.1)
)
$f1 = New-TestWindow 5.0 15.0 @(
    (New-TestToken 'inicio' 5.5 6.0),
    (New-TestToken 'medio'  6.5 7.0)
)
$f2 = New-TestWindow 8.0 18.0 @(
    (New-TestToken '--'     8.0 8.3),
    (New-TestToken ' --'    8.8 9.1),
    (New-TestToken ' final' 10.0 10.5)
)

$resultF = @(Reconstruct-WhisperWindows @($f0, $f1, $f2))
$dashF = @($resultF | Where-Object { $_.Text.Trim() -eq '--' })

if ($dashF.Count -eq 4) {
    Write-Host "[OK] Las ocurrencias de puntuacion se conservan; Level 2 no actua sobre Key vacia"
} else {
    Write-Host ("[FAIL] Se obtuvieron {0} ocurrencias de '--'; esperado 4" -f $dashF.Count)
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA ISSUE 2 PASSED ==="
    exit 0
} else {
    Write-Host "=== PRUEBA ISSUE 2 FAILED ==="
    exit 1
}
