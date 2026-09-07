# ============================================================
# PRUEBA — ISSUE 4: SELECCION DE MATCH CON COLISION DE KEYS
#
# Escenario:
#   W0 [0,10]:  uno dos tres cuatro | cinco seis siete
#               (bloque genuinamente compartido)
#               | bien-estar auto-escala vice-presidente
#                 tri-ciclo mono-tono a-gente
#               (run con claves colisionadas: Key==bienestar...)
#
#   W1 [5,15]:  bienestar autoescala vicepresidente triciclo
#               monotono agente (claves NO vacias que colisionan
#               con las anteriores por el guion)
#               | cinco seis siete | nueve diez once doce
#
# Dos candidatos compiten:
#   - genuino  : PreviousStart=0 CurrentStart=6 Matches=3
#                (identidad de texto y timing)
#   - colision : PreviousStart=3 CurrentStart=0 Matches=6
#                (solo coincidencia de claves despues del strip)
#
# El bug original (commit 5a1d4cc) seleccionaba la colision por
# "mas matches" y producia "cinco seis siete" duplicado + orden
# temporal roto. Este test exige que el bloque genuino gane.
# ============================================================

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA 4: SELECCION DE MATCH CON COLISION DE KEYS ==="
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

# ------------------------------------------------------------
# Ventana 0: Start=0, End=10
# ------------------------------------------------------------
$w0 = [PSCustomObject]@{
    Start = 0.0
    End   = 10.0
    Tokens = @(
        (New-TestToken 'uno'            0.1 0.7),
        (New-TestToken ' dos'           1.1 1.7),
        (New-TestToken ' tres'          2.1 2.7),
        (New-TestToken ' cuatro'        3.1 3.7),
        (New-TestToken ' cinco'         5.1 5.5),
        (New-TestToken ' seis'          6.1 6.5),
        (New-TestToken ' siete'         7.1 7.5),
        (New-TestToken ' bien-estar'       7.6 7.8),
        (New-TestToken ' auto-escala'      7.9 8.1),
        (New-TestToken ' vice-presidente'  8.2 8.4),
        (New-TestToken ' tri-ciclo'        8.5 8.7),
        (New-TestToken ' mono-tono'        8.8 9.0),
        (New-TestToken ' a-gente'          9.1 9.3)
    )
}

# ------------------------------------------------------------
# Ventana 1: Start=5, End=15
# ------------------------------------------------------------
$w1 = [PSCustomObject]@{
    Start = 5.0
    End   = 15.0
    Tokens = @(
        (New-TestToken ' bienestar'        5.0 5.2),
        (New-TestToken ' autoescala'       5.3 5.5),
        (New-TestToken ' vicepresidente'   5.6 5.8),
        (New-TestToken ' triciclo'         5.9 6.1),
        (New-TestToken ' monotono'         6.2 6.4),
        (New-TestToken ' agente'           6.5 6.7),
        (New-TestToken ' cinco'         7.1 7.5),
        (New-TestToken ' seis'          8.1 8.5),
        (New-TestToken ' siete'         9.1 9.5),
        (New-TestToken ' nueve'        11.1 11.7),
        (New-TestToken ' diez'         12.1 12.7),
        (New-TestToken ' once'         13.1 13.7),
        (New-TestToken ' doce'         14.1 14.7)
    )
}

$windows = @($w0, $w1)

# ------------------------------------------------------------
# 1. CONSTRUCCION DE WORDS Y KEYS
# ------------------------------------------------------------
$w0Words = @(Build-WhisperWords $w0.Tokens -WindowIndex 0)
$w1Words = @(Build-WhisperWords $w1.Tokens -WindowIndex 1)

Write-Host "--- KEYS DE LA VENTANA 0 (banda de solape) ---"
Write-Host ((($w0Words | ForEach-Object { "[$($_.Text)]:Key=$($_.Key)" }) -join ' '))
Write-Host ""
Write-Host "--- KEYS DE LA VENTANA 1 (banda de solape) ---"
Write-Host ((($w1Words | ForEach-Object { "[$($_.Text)]:Key=$($_.Key)" }) -join ' '))

# ------------------------------------------------------------
# 2. REGION DE SOLAPAMIENTO TEMPORAL
# ------------------------------------------------------------
$overlapStart = $w1.Start
$overlapEnd   = $w0.End

$prevOverlap = @(
    $w0Words |
    Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart }
)

$currOverlap = @(
    $w1Words |
    Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart }
)

Write-Host ""
Write-Host "prevOverlap ($($prevOverlap.Count)): " + (($prevOverlap | ForEach-Object { "[$($_.Text)]" }) -join ' ')
Write-Host "currOverlap ($($currOverlap.Count)): " + (($currOverlap | ForEach-Object { "[$($_.Text)]" }) -join ' ')

# ------------------------------------------------------------
# 3. FIND-WORDOVERLAP
# ------------------------------------------------------------
Write-Host ""
Write-Host "--- FIND-WORDOVERLAP ---"
$match = Find-WordOverlap $prevOverlap $currOverlap

if ($null -eq $match) {
    Write-Host "[FAIL] SIN MATCH: se esperaba el bloque genuino"
    $pass = $false
} else {
    Write-Host ("  Matches            = {0}" -f $match.Matches)
    Write-Host ("  ExactTextMatches   = {0}" -f $match.ExactTextMatches)
    Write-Host ("  PreviousStart      = {0}" -f $match.PreviousStart)
    Write-Host ("  CurrentStart       = {0}" -f $match.CurrentStart)
    Write-Host ("  PreviousConsumed   = {0}" -f $match.PreviousConsumed)
    Write-Host ("  CurrentConsumed    = {0}" -f $match.CurrentConsumed)

    # Candidato genuino esperado: ancla en 'cinco' (indices 0 y 6)
    if (
        $match.PreviousStart -eq 0 -and
        $match.CurrentStart -eq 6 -and
        $match.Matches -eq 3
    ) {
        Write-Host "[OK] Selecciono el bloque genuino (PreviousStart=0 CurrentStart=6 Matches=3)"
    } else {
        Write-Host ("[FAIL] Seleccion NO correcta: PreviousStart={0} CurrentStart={1} Matches={2}" -f $match.PreviousStart, $match.CurrentStart, $match.Matches)
        $pass = $false
    }
}

# ------------------------------------------------------------
# 4. RECONSTRUCCION COMPLETA (consecuencia observable)
# ------------------------------------------------------------
Write-Host ""
Write-Host "--- RECONSTRUCCION ---"
$result = @(Reconstruct-WhisperWindows $windows)

Write-Host ""
Write-Host "Texto reconstruido ($($result.Count) palabras):"
Write-Host ("  " + (($result | ForEach-Object { $_.Text }) -join ' '))

$expectedWords = @(
    'uno', 'dos', 'tres', 'cuatro',
    'cinco', 'seis', 'siete',
    'nueve', 'diez', 'once', 'doce'
)

# 4a. El resultado debe ser exactamente la secuencia esperada
$resultTexts = @($result | ForEach-Object { $_.Text })
$expectedSequence = $expectedWords -join ' '
$actualSequence = $resultTexts -join ' '

if ($actualSequence -eq $expectedSequence) {
    Write-Host "[OK] Salida coincide exactamente con la esperada (splice en el bloque genuino)"
} else {
    Write-Host "[FAIL] Salida != esperada"
    Write-Host ("  Esperada : {0}" -f $expectedSequence)
    Write-Host ("  Obtenida : {0}" -f $actualSequence)
    $pass = $false
}

# 4b. Ninguna palabra esperada se pierde
$lostCount = 0
foreach ($expected in $expectedWords) {
    if ($resultTexts -notcontains $expected) {
        Write-Host ("[FAIL] Palabra esperada perdida: {0}" -f $expected)
        $lostCount++
    }
}
if ($lostCount -eq 0) {
    Write-Host "[OK] Ninguna palabra esperada se pierde"
} else {
    $pass = $false
}

# 4c. 'cinco seis siete' no debe duplicarse
$fiveBlockCount = 0
for ($i = 0; $i -le $resultTexts.Count - 3; $i++) {
    if (
        $resultTexts[$i]     -eq 'cinco' -and
        $resultTexts[$i + 1] -eq 'seis'  -and
        $resultTexts[$i + 2] -eq 'siete'
    ) {
        $fiveBlockCount++
    }
}
if ($fiveBlockCount -eq 1) {
    Write-Host "[OK] 'cinco seis siete' aparece una sola vez"
} else {
    Write-Host ("[FAIL] 'cinco seis siete' aparece {0} veces" -f $fiveBlockCount)
    $pass = $false
}

# 4d. Orden temporal estrictamente monotono
$orderOk = $true
for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host ("[FAIL] Violacion de orden temporal en indice {0}: '{1}' From={2} sigue a '{3}' From={4}" -f $i, $result[$i].Text, $result[$i].From, $result[$i - 1].Text, $result[$i - 1].From)
        $orderOk = $false
        break
    }
}
if ($orderOk) {
    Write-Host "[OK] Orden temporal monotonamente creciente"
} else {
    $pass = $false
}

# ------------------------------------------------------------
# 5. RESULTADO
# ------------------------------------------------------------
Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA 4 PASSED (el bloque genuino gana frente a la colision de claves) ==="
    exit 0
} else {
    Write-Host "=== PRUEBA 4 FAILED ==="
    exit 1
}