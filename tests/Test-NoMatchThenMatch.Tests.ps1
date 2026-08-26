# PRUEBA 2 — REGRESION: MATCH -> SIN MATCH -> MATCH
# Verifica que el estado de reconstrucción (previousOverlapMap / prefixCount)
# se preserve correctamente a través de la secuencia MATCH -> SIN MATCH -> MATCH,
# sin truncar el historial previo ni duplicar palabras.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA 2: REGRESION MATCH -> SIN MATCH -> MATCH ==="

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

# Configuración de 4 ventanas para forzar:
# Transición 1 (W0 -> W1): MATCH en 'cinco seis siete ocho'
# Transición 2 (W1 -> W2): SIN MATCH (W1 tiene 'nueve diez once doce', W2 tiene 'palabraA palabraB palabraC')
# Transición 3 (W2 -> W3): MATCH en 'palabraA palabraB palabraC alpha beta gamma'

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

$transcriptPath = Join-Path $env:TEMP ("whisper-regress-" + [Guid]::NewGuid().ToString() + ".txt")
Start-Transcript -Path $transcriptPath | Out-Null

$result = Reconstruct-WhisperWindows $windows

Stop-Transcript | Out-Null

$diagnostics = Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue

# 1. Verificar secuencia de transiciones
$transitions = @()
$currentTransition = $null

foreach ($line in $diagnostics) {
    if ($line -match "TRANSICION\s+([\d.]+)s\s+->\s+([\d.]+)s") {
        if ($currentTransition) { $transitions += $currentTransition }
        $currentTransition = @{
            From = $matches[1]
            To = $matches[2]
            Type = "UNKNOWN"
            PrefixCount = -1
        }
    } elseif ($line -match "SIN MATCH") {
        if ($currentTransition) { $currentTransition.Type = "SIN_MATCH" }
    } elseif ($line -match "PreviousStart\s+:\s+\d+") {
        if ($currentTransition) { $currentTransition.Type = "MATCH" }
    } elseif ($line -match "PrefixCount\s+:\s+(\d+)") {
        if ($currentTransition) { $currentTransition.PrefixCount = [int]$matches[1] }
    }
}
if ($currentTransition) { $transitions += $currentTransition }

Write-Host "Transiciones evaluadas: $($transitions.Count)"
for ($t = 0; $t -lt $transitions.Count; $t++) {
    Write-Host "  Transicion $t ($($transitions[$t].From)s -> $($transitions[$t].To)s): $($transitions[$t].Type) (PrefixCount=$($transitions[$t].PrefixCount))"
}

if ($transitions.Count -ne 3) {
    Write-Host "[FAIL] Se esperaban 3 transiciones, se obtuvieron $($transitions.Count)"
    $pass = $false
} else {
    if ($transitions[0].Type -ne "MATCH") {
        Write-Host "[FAIL] Transicion 0 debia ser MATCH, fue $($transitions[0].Type)"
        $pass = $false
    } else {
        Write-Host "[OK] Transicion 0: MATCH"
    }

    if ($transitions[1].Type -ne "SIN_MATCH") {
        Write-Host "[FAIL] Transicion 1 debia ser SIN_MATCH, fue $($transitions[1].Type)"
        $pass = $false
    } else {
        Write-Host "[OK] Transicion 1: SIN_MATCH"
    }

    if ($transitions[2].Type -ne "MATCH") {
        Write-Host "[FAIL] Transicion 2 debia ser MATCH, fue $($transitions[2].Type)"
        $pass = $false
    } else {
        Write-Host "[OK] Transicion 2: MATCH"
    }
}

# 2. Verificar contenido exacto y que no se trunco el prefijo
$expectedWords = @(
    "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
    "palabraA", "palabraB", "palabraC", "alpha", "beta", "gamma",
    "delta", "epsilon"
)
$expectedText = $expectedWords -join ' '

$actualWords = @($result | ForEach-Object { $_.Text })
$actualText = $actualWords -join ' '

Write-Host ""
Write-Host "Verificacion de contenido:"
Write-Host "Esperado ($($expectedWords.Count) palabras): $expectedText"
Write-Host "Obtenido ($($actualWords.Count) palabras): $actualText"

if ($actualWords.Count -ne $expectedWords.Count) {
    Write-Host "[FAIL] Conteo de palabras incorrecto: esperado $($expectedWords.Count), obtenido $($actualWords.Count)"
    $pass = $false
} else {
    Write-Host "[OK] Conteo de palabras: $($actualWords.Count)"
}

if ($actualText -ne $expectedText) {
    Write-Host "[FAIL] Texto reconstruido no coincide exactamente con el esperado"
    $pass = $false
} else {
    Write-Host "[OK] Texto reconstruido coincide exactamente con el esperado"
}

# 3. Verificar que las palabras previas al SIN MATCH (W0 y W1) estan completas
$earlyExpected = @("uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce")
$missingEarly = @()
foreach ($w in $earlyExpected) {
    if ($actualWords -notcontains $w) {
        $missingEarly += $w
    }
}

if ($missingEarly.Count -gt 0) {
    Write-Host "[FAIL] Se perdieron palabras previas al SIN MATCH: $($missingEarly -join ', ')"
    $pass = $false
} else {
    Write-Host "[OK] Todas las palabras previas al SIN MATCH estan presentes"
}

# 4. Verificar orden temporal ascendente
$orderOk = $true
for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host ("[FAIL] Violacion de orden temporal en indice {0}: {1} ({2}) < {3} ({4})" -f $i, $result[$i].Text, $result[$i].From, $result[$i - 1].Text, $result[$i - 1].From)
        $orderOk = $false
        $pass = $false
        break
    }
}
if ($orderOk) {
    Write-Host "[OK] Orden temporal monótonamente creciente"
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA 2 PASSED ==="
    exit 0
} else {
    Write-Host "=== PRUEBA 2 FAILED ==="
    exit 1
}