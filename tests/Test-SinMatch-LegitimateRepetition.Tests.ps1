# PRUEBA A3 (REGRESION) — REPETICION LEGITIMA DENTRO DE RAMA SIN MATCH
#
# Hallazgo que se intenta demostrar:
#   Reconstruct-WhisperWindows.ps1, dentro de la rama "if ($null -eq $match)"
#   (SIN MATCH), define Test-WordAlreadyExists / Add-NewWordsWithTiming, que
#   consideran duplicada cualquier palabra con el mismo texto y con diferencias
#   de From y de To <= 0.5s respecto a una palabra ya aceptada en $finalWords
#   (incluyendo palabras aceptadas en la MISMA pasada de la ventana actual).
#
#   Esto puede borrar repeticiones legitimas e inmediatas de una misma palabra
#   (ej. "no, no", tartamudeos, enfasis) cuando ocurren dentro de una ventana
#   que dispara SIN MATCH.
#
# Diseno del caso:
#   - W0 y W1 estan separadas en el tiempo sin solapamiento alguno
#     (W0.End = 5.0, W1.Start = 8.0), por lo que prevOverlap y currOverlap
#     son necesariamente arrays vacios, Find-WordOverlap(...) devuelve $null
#     de forma garantizada, y la transicion SIEMPRE cae en la rama SIN MATCH.
#     Esto hace el test independiente de cualquier coincidencia de vocabulario.
#   - W1 contiene dos ocurrencias consecutivas y legitimas de "no":
#       "no" 10.00-10.30
#       "no" 10.35-10.60
#     Diferencia de From = 0.35s (<=0.5), diferencia de To = 0.30s (<=0.5)
#     -> dispara exactamente la condicion de "duplicado" del codigo actual.
#
# Resultado esperado (comportamiento CORRECTO): 2 ocurrencias de "no" en el
# resultado final, 8 palabras en total.
#
# Este test debe FALLAR (exit 1) con el codigo actual si el bug A3 existe.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$pass = $true

Write-Host "=== PRUEBA A3: REPETICION LEGITIMA EN RAMA SIN MATCH ==="

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

# W0: vocabulario totalmente ajeno a W1, termina en 5.0
$w0 = [PSCustomObject]@{
    Start = 0.0
    End   = 5.0
    Tokens = @(
        New-TestToken 'alpha' 0.1 0.9
        New-TestToken ' beta' 1.1 1.9
        New-TestToken ' gamma' 2.1 2.9
        New-TestToken ' delta' 3.1 3.9
    )
}

# W1: empieza en 8.0 (sin solapamiento temporal con W0), contiene "no" "no" legitimos
$w1 = [PSCustomObject]@{
    Start = 8.0
    End   = 15.0
    Tokens = @(
        New-TestToken 'no' 10.00 10.30
        New-TestToken ' no' 10.35 10.60
        New-TestToken ' zeta' 11.00 11.50
        New-TestToken ' eta' 12.00 12.50
    )
}

$windows = @($w0, $w1)

# Capturamos diagnostico para CONFIRMAR que realmente se ejecuto la rama SIN MATCH
# (y no dar el test por valido si por algun motivo hubo MATCH).
$transcriptPath = Join-Path $env:TEMP ("whisper-a3-" + [Guid]::NewGuid().ToString() + ".txt")
Start-Transcript -Path $transcriptPath | Out-Null
$result = Reconstruct-WhisperWindows $windows
Stop-Transcript | Out-Null

$diagnostics = Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue

$sawSinMatch = $false
foreach ($line in $diagnostics) {
    if ($line -match "SIN MATCH") { $sawSinMatch = $true }
}

if (-not $sawSinMatch) {
    Write-Host "[FAIL] La transicion no cayo en la rama SIN MATCH; el caso de prueba no es valido tal como esta construido"
    $pass = $false
} else {
    Write-Host "[OK] Se confirma que la transicion ejecuto la rama SIN MATCH"
}

$wordsArray = @($result)

Write-Host ""
Write-Host "Resultado obtenido ($($wordsArray.Count) palabras):"
foreach ($w in $wordsArray) {
    Write-Host ("  Text='{0}' From={1} To={2} Id={3}" -f $w.Text, $w.From, $w.To, $w.Id)
}

# 1. Conteo de "no"
$noOccurrences = @($wordsArray | Where-Object { $_.Text.ToLower().Trim() -eq "no" })

Write-Host ""
Write-Host ("Ocurrencias de 'no' en resultado: {0} (esperado: 2)" -f $noOccurrences.Count)

if ($noOccurrences.Count -ne 2) {
    Write-Host "[FAIL] Se esperaban 2 ocurrencias de 'no', se obtuvieron $($noOccurrences.Count) -> BUG A3 CONFIRMADO (repeticion legitima eliminada por deduplicacion de timing)"
    $pass = $false
} else {
    Write-Host "[OK] Las 2 ocurrencias de 'no' sobreviven"
}

# 2. Verificar que los timestamps de ambas ocurrencias de "no" se preservaron exactamente
if ($noOccurrences.Count -eq 2) {
    $expectedPairs = @(
        @{ From = 10.00; To = 10.30 },
        @{ From = 10.35; To = 10.60 }
    )
    for ($k = 0; $k -lt 2; $k++) {
        $actual = $noOccurrences[$k]
        $expected = $expectedPairs[$k]
        if ([math]::Abs($actual.From - $expected.From) -gt 0.0001 -or [math]::Abs($actual.To - $expected.To) -gt 0.0001) {
            Write-Host "[FAIL] Ocurrencia 'no' #$k tiene timestamps incorrectos: From=$($actual.From) To=$($actual.To) (esperado From=$($expected.From) To=$($expected.To))"
            $pass = $false
        } else {
            Write-Host "[OK] Ocurrencia 'no' #$k conserva timestamps originales"
        }
    }
}

# 3. Conteo total de palabras (4 de W0 + 4 de W1 = 8)
Write-Host ""
Write-Host ("Total de palabras en resultado: {0} (esperado: 8)" -f $wordsArray.Count)
if ($wordsArray.Count -ne 8) {
    Write-Host "[FAIL] Conteo total incorrecto: esperado 8, obtenido $($wordsArray.Count)"
    $pass = $false
} else {
    Write-Host "[OK] Conteo total correcto"
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA A3 PASSED (bug no reproducido / ya corregido) ==="
    exit 0
} else {
    Write-Host "=== PRUEBA A3 FAILED — BUG A3 REPRODUCIDO: repeticion legitima 'no'/'no' eliminada por Test-WordAlreadyExists en la rama SIN MATCH ==="
    exit 1
}
