# ============================================================
# PRUEBA — ISSUE 3: DERIVA TEMPORAL DE ASR /
# THRESHOLD ACROSS OVERLAPPING WINDOWS
#
# Escenario (mismo evento 'X' en tres ventanas solapadas, con
# deriva de timestamps tipica de ASR):
#   W0 [0,10] : uno dos tres cuatro X(8.1-8.5)
#   W1 [2,14] : X(9.3-9.7) nuevo texto
#   W2 [4,16] : X(8.6-9.0) cola final
#
# Cada transicion ve 1 match de Key (< umbral 3) -> SIN MATCH.
# La tolerancia fija +/-0.5s del dedup no absorbia la deriva de
# 1.2s entre W0 y W1 y 'X' quedaba duplicada.
#
# Esperado: una sola 'X' y 9 palabras en total.
#
# Control: el escenario de Test-EmptyKeyFalseMatch (dos
# ocurrencias legitimas del mismo texto de puntuacion dentro de
# la banda) NO debe perder ninguna palabra.
# ============================================================

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA ISSUE 3: DERIVA TEMPORAL DE ASR ==="
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function Assert-OrderedTimestamps {
    param([object[]]$words)
    for ($i = 1; $i -lt $words.Count; $i++) {
        if ($words[$i].From -lt $words[$i - 1].From) {
            Write-Host ("[FAIL] Violacion de orden temporal en indice {0}: '{1}' ({2}) sigue a '{3}' ({4})" -f $i, $words[$i].Text, $words[$i].From, $words[$i - 1].Text, $words[$i - 1].From)
            return $false
        }
    }
    Write-Host "[OK] Timestamps en orden temporal ascendente"
    return $true
}

# ------------------------------------------------------------
# CASO A: un unico 'X' transcrito en 3 ventanas (deriva)
# ------------------------------------------------------------
Write-Host "--- CASO A: un unico 'X' transcrito en 3 ventanas (deriva de 1.2s) ---"

$w0 = [PSCustomObject]@{
    Start = 0.0
    End   = 10.0
    Tokens = @(
        (New-TestToken 'uno'    0.6 1.2),
        (New-TestToken ' dos'   1.8 2.4),
        (New-TestToken ' tres'  3.0 3.6),
        (New-TestToken ' cuatro' 4.2 4.8),
        (New-TestToken ' X'     8.1 8.5)
    )
}

$w1 = [PSCustomObject]@{
    Start = 2.0
    End   = 14.0
    Tokens = @(
        (New-TestToken 'X'       9.3 9.7),
        (New-TestToken ' nuevo' 11.1 11.7),
        (New-TestToken ' texto' 12.1 12.7)
    )
}

$w2 = [PSCustomObject]@{
    Start = 4.0
    End   = 16.0
    Tokens = @(
        (New-TestToken 'X'      8.6 9.0),
        (New-TestToken ' cola' 13.1 13.7),
        (New-TestToken ' final' 14.1 14.7)
    )
}

$result = @(Reconstruct-WhisperWindows @($w0, $w1, $w2))

$resultText = (($result | ForEach-Object { $_.Text }) -join ' ')
$xs = @($result | Where-Object { $_.Text -eq 'X' })

Write-Host ("Texto obtenido ({0} palabras): {1}" -f $result.Count, $resultText)
Write-Host "Ocurrencias de 'X':"
foreach ($x in $xs) { Write-Host ("  X From={0} To={1} Id={2}" -f $x.From, $x.To, $x.Id) }

# A1. 'X' debe aparecer exactamente una vez
if ($xs.Count -eq 1) {
    Write-Host "[OK] 'X' aparece exactamente 1 vez"
} else {
    Write-Host ("[FAIL] 'X' aparece {0} veces (esperado 1)" -f $xs.Count)
    $pass = $false
}

# A2. Conteo exacto de 9 palabras
if ($result.Count -eq 9) {
    Write-Host "[OK] Resultado con exactamente 9 palabras"
} else {
    Write-Host ("[FAIL] Resultado con {0} palabras (esperado 9)" -f $result.Count)
    $pass = $false
}

# A3. Texto final exacto
$expectedText = 'uno dos tres cuatro X nuevo texto cola final'
if ($resultText -eq $expectedText) {
    Write-Host "[OK] Texto final coincide con el esperado"
} else {
    Write-Host ("[FAIL] Texto: se esperaba '{0}' y se obtuvo '{1}'" -f $expectedText, $resultText)
    $pass = $false
}

# A4. Palabras unicas de W1 (nuevo, texto) y W2 (cola, final) no se pierden
foreach ($w in @('nuevo', 'texto', 'cola', 'final')) {
    if (($result | ForEach-Object { $_.Text }) -contains $w) {
        Write-Host "[OK] '$w' presente"
    } else {
        Write-Host "[FAIL] '$w' se perdio"
        $pass = $false
    }
}

# A5. Orden temporal monotono
if (-not (Assert-OrderedTimestamps -words $result)) {
    $pass = $false
}

Write-Host ""

# ------------------------------------------------------------
# CASO B (control): dos ocurrencias legitimas del mismo texto
# dentro de la banda de overlap (escenario
# Test-EmptyKeyFalseMatch) no deben colapsar.
# ------------------------------------------------------------
Write-Host "--- CASO B: dos ocurrencias legitimas del mismo texto (control) ---"

$b0 = [PSCustomObject]@{
    Start = 0.0
    End   = 10.0
    Tokens = @(
        (New-TestToken 'alpha'  0.1 0.9),
        (New-TestToken ' beta'  1.1 1.9),
        (New-TestToken ' gamma' 2.1 2.9),
        (New-TestToken ' delta' 3.1 3.9),
        (New-TestToken ' --'    7.0 7.3),
        (New-TestToken ' ...'   7.4 7.7),
        (New-TestToken ' ?'     7.8 8.1),
        (New-TestToken ' --'    8.2 8.5),
        (New-TestToken ' !'     8.6 8.9),
        (New-TestToken ' ...'   9.0 9.3),
        (New-TestToken ' ultimo' 9.4 9.9)
    )
}

$b1 = [PSCustomObject]@{
    Start = 5.0
    End   = 15.0
    Tokens = @(
        (New-TestToken '('    5.0 5.3),
        (New-TestToken ' )'   5.4 5.7),
        (New-TestToken ' ,'   5.8 6.1),
        (New-TestToken ' --'  6.2 6.5),
        (New-TestToken ' ?'   6.6 6.9),
        (New-TestToken ' !'   7.0 7.3),
        (New-TestToken ' zeta'   11.1 11.9),
        (New-TestToken ' eta'    12.1 12.9),
        (New-TestToken ' theta'  13.1 13.9),
        (New-TestToken ' iota'   14.1 14.9)
    )
}

$b0Words = @(Build-WhisperWords $b0.Tokens -WindowIndex 0)
$b1Words = @(Build-WhisperWords $b1.Tokens -WindowIndex 1)

$resultB = @(Reconstruct-WhisperWindows @($b0, $b1))

$expectedB = $b0Words.Count + $b1Words.Count

Write-Host ("Texto obtenido ({0} palabras): {1}" -f $resultB.Count, (($resultB | ForEach-Object { $_.Text }) -join ' '))

# B1. Conteo total preservado (concatenacion)
if ($resultB.Count -eq $expectedB) {
    Write-Host "[OK] Se conservan las $expectedB palabras esperadas"
} else {
    Write-Host ("[FAIL] Se obtuvieron {0} palabras (esperado {1}) - una ocurrencia legitima fue absorbida" -f $resultB.Count, $expectedB)
    $pass = $false
}

# B2. La segunda ocurrencia legitima de '--' (From=6.2) se conserva
$legitSecondDash = @($resultB | Where-Object { $_.Text -eq '--' -and [math]::Abs($_.From - 6.2) -lt 0.0001 })
if ($legitSecondDash.Count -eq 1) {
    Write-Host "[OK] La segunda ocurrencia legitima de '--' (From=6.2) se conserva"
} else {
    Write-Host "[FAIL] La segunda ocurrencia legitima de '--' (From=6.2) se perdio"
    $pass = $false
}

# B3. Ninguna palabra de la ventana 0 se pierde
$lostB = @()
foreach ($word in $b0Words) {
    $found = $false
    foreach ($r in $resultB) {
        if ($r.Text -eq $word.Text -and [math]::Abs($r.From - $word.From) -lt 0.0001) {
            $found = $true
            break
        }
    }
    if (-not $found) {
        $lostB += $word
    }
}
if ($lostB.Count -eq 0) {
    Write-Host "[OK] Ninguna palabra de la ventana 0 se pierde"
} else {
    Write-Host ("[FAIL] Se perdieron palabras de la ventana 0: {0}" -f (($lostB | ForEach-Object { $_.Text }) -join ', '))
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA ISSUE 3 PASSED ==="
    exit 0
} else {
    Write-Host "=== PRUEBA ISSUE 3 FAILED ==="
    exit 1
}