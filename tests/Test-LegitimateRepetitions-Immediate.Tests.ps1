# PRUEBA A3 — REPETICION LEGITIMA INMEDIATA EN RAMA SIN MATCH
#
# Hallazgo de auditoria (151dc76): Add-NewWordsWithTiming / Test-WordAlreadyExists
# (definidas dentro de Reconstruct-WhisperWindows.ps1, rama SIN MATCH) consideran
# duplicada cualquier palabra con mismo texto normalizado y |fromDiff|<=0.5s y
# |toDiff|<=0.5s, SIN distinguir si la comparacion es contra una repeticion
# legitima dentro de la misma ventana o contra ocurrencias historicas reales.
#
# Este test construye dos ventanas W0 -> W1 disenadas para forzar SIN MATCH
# (cero palabras compartidas en la zona de solapamiento), donde W1 contiene
# dos ocurrencias legitimas y consecutivas de "no":
#   "no" 10.00-10.30
#   "no" 10.35-10.60
#
# Comportamiento CORRECTO esperado: ambas ocurrencias de "no" sobreviven (count=2).
# Comportamiento ACTUAL (bug confirmado por auditoria estatica): la segunda
# ocurrencia es descartada por Test-WordAlreadyExists (fromDiff=0.35<=0.5,
# toDiff=0.30<=0.5), dejando count=1.
#
# Este test DEBE FALLAR (exit 1) mientras el bug exista. Es la prueba de
# regresion pendiente de corregir; no se modifica src/ en este paso.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA A3: REPETICION LEGITIMA INMEDIATA (SIN MATCH) ==="

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

# W0: ventana inicial. Incluye palabras "ancla" en la zona de overlap [8.0, 10.0)
# que NO existen en W1, para forzar SIN MATCH en la transicion W0 -> W1.
$w0 = [PSCustomObject]@{
    Start = 0.0
    End   = 10.0
    Tokens = @(
        New-TestToken 'hola'  0.1 0.4
        New-TestToken ' mundo' 0.5 0.9
        New-TestToken ' zzzancoreA' 8.1 8.4
        New-TestToken ' zzzancoreB' 8.5 8.8
        New-TestToken ' zzzancoreC' 8.9 9.2
    )
}

# W1: ventana siguiente. En la zona de overlap [8.0, 10.0) usa palabras distintas
# ("wwwancore*") para garantizar 0 coincidencias de Key con W0 -> SIN MATCH.
# Luego, ya fuera de la zona de overlap (>=10.0), incluye la repeticion legitima
# de "no" que es el objeto de esta prueba.
$w1 = [PSCustomObject]@{
    Start = 8.0
    End   = 20.0
    Tokens = @(
        New-TestToken 'wwwancoreA' 8.1 8.4
        New-TestToken ' wwwancoreB' 8.5 8.8
        New-TestToken ' wwwancoreC' 8.9 9.2
        New-TestToken ' no'   10.00 10.30
        New-TestToken ' no'   10.35 10.60
        New-TestToken ' fin'  11.0  11.3
    )
}

$windows = @($w0, $w1)

$transcriptPath = Join-Path $env:TEMP ("whisper-a3-" + [Guid]::NewGuid().ToString() + ".txt")
Start-Transcript -Path $transcriptPath | Out-Null

$result = Reconstruct-WhisperWindows $windows

Stop-Transcript | Out-Null

$diagnostics = Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue

# 1. Confirmar que efectivamente se disparo SIN MATCH (precondicion del test).
$sinMatchDetected = $false
foreach ($line in $diagnostics) {
    if ($line -match "SIN MATCH") {
        $sinMatchDetected = $true
        break
    }
}

if (-not $sinMatchDetected) {
    Write-Host "[FAIL] Precondicion no cumplida: no se detecto SIN MATCH en la transicion W0->W1."
    Write-Host "       El diseno de las ventanas de prueba debe forzar SIN MATCH; revisar zona de overlap."
    exit 1
} else {
    Write-Host "[OK] Precondicion cumplida: se detecto SIN MATCH en W0->W1"
}

# 2. Verificar que ambas ocurrencias de "no" sobreviven.
$wordsArray = @($result)
$noWords = @($wordsArray | Where-Object { $_.Text.ToLower().Trim() -eq "no" })

Write-Host "Ocurrencias de 'no' encontradas: $($noWords.Count)"
foreach ($w in $noWords) {
    Write-Host ("  Text='{0}' From={1} To={2}" -f $w.Text, $w.From, $w.To)
}

if ($noWords.Count -ne 2) {
    Write-Host "[FAIL] Se esperaban 2 ocurrencias de 'no' (10.00-10.30 y 10.35-10.60), se obtuvieron $($noWords.Count)."
    Write-Host "       Esto confirma el hallazgo A3: Test-WordAlreadyExists descarta repeticiones legitimas"
    Write-Host "       separadas por menos de 0.5s en From y To dentro de la rama SIN MATCH."
    $pass = $false
} else {
    Write-Host "[OK] Ambas ocurrencias de 'no' sobrevivieron"
}

# 3. Verificar tambien que el resto del contenido de W1 no fue afectado
$expectedOther = @("wwwancoreA", "wwwancoreB", "wwwancoreC", "fin")
$missingOther = @()
foreach ($expected in $expectedOther) {
    if (-not ($wordsArray.Text -contains $expected)) {
        $missingOther += $expected
    }
}
if ($missingOther.Count -gt 0) {
    Write-Host "[FAIL] Palabras inesperadamente perdidas (no relacionadas con el bug de 'no'): $($missingOther -join ', ')"
    $pass = $false
} else {
    Write-Host "[OK] Resto de palabras de W1 presentes"
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA A3 PASSED (bug corregido) ==="
    exit 0
} else {
    Write-Host "=== PRUEBA A3 FAILED (bug A3 confirmado: repeticion legitima descartada) ==="
    exit 1
}
