# PRUEBA ISSUE 6 — ESTADO DEL ANCLA DESPUES DE MATCH
#
# Reproduce el caso historico: despues de un MATCH, la reconstruccion puede
# descartar una palabra que estaba ANTES del ancla del MATCH en currentWords.
# Si esa palabra vuelve a aparecer como primera ancla de un MATCH posterior,
# previousOverlapMap no puede localizarla en finalWords.
#
# Escenario:
#   W0 [0,10] -> A B C
#   W1 [5,15] -> X A B C
#   W2 [8,18] -> X A B C D
#
# En W0->W1, X esta antes de A dentro del overlap [5,10], pero W0 no tiene X.
# Find-WordOverlap encuentra A B C como MATCH. Al reconstruir, currentMatch
# empieza en A, por lo que X de W1 queda descartada de finalWords.
#
# En W1->W2, el overlap es [8,15] y contiene X A B C en ambas ventanas.
# Ahora Find-WordOverlap encuentra X A B C como MATCH y X es el ancla.
# Como X fue descartada en la reconstruccion anterior, no existe en finalWords.
# El comportamiento defectuoso debe producir:
#   ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA
#
# Este test debe FALLAR con el comportamiento historico y PASAR solamente
# despues de corregir la conservacion/estado del ancla.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

Write-Host "=== PRUEBA ISSUE 6: ANCLA DESCARTADA -> MATCH POSTERIOR ==="
Write-Host ""

function New-TestToken {
    param(
        [string]$Text,
        [double]$From,
        [double]$To
    )

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
        Tokens = @($Tokens)
    }
}

function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

# W0 [0,10]: solo A B C.
$w0 = @(
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9)
)

# W1 [5,15]: X aparece ANTES de A dentro del primer overlap [5,10].
# W0 no tiene X, asi que el MATCH correcto es A B C.
# Al reconstruir desde A, X queda fuera de finalWords.
$w1 = @(
    (T ' X' 8.2 8.5),
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9)
)

# W2 [8,18]: X A B C estan ahora en el overlap [8,15].
# El MATCH posterior empieza en X, que ya fue descartada de finalWords.
$w2 = @(
    (T ' X' 8.2 8.5),
    (T ' A' 9.0 9.3),
    (T ' B' 9.4 9.7),
    (T ' C' 9.8 9.9),
    (T ' D' 11.0 11.4)
)

$windows = @(
    (New-TestWindow 0 10  $w0),
    (New-TestWindow 5 15  $w1),
    (New-TestWindow 8 18  $w2)
)

$transcriptPath = Join-Path $env:TEMP ("whisper-issue6-" + [Guid]::NewGuid().ToString() + ".txt")

try {
    Start-Transcript -Path $transcriptPath | Out-Null
    $result = @(Reconstruct-WhisperWindows -Windows $windows)
    Stop-Transcript | Out-Null
} catch {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host "[FAIL] Reconstruct-WhisperWindows lanzo excepcion: $_"
    Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue
    exit 1
}

$diagnostics = Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue

foreach ($line in $diagnostics) {
    Write-Host $line
}

$text = ($result | ForEach-Object { $_.Text }) -join ' '
Write-Host ""
Write-Host "Resultado: $text"
Write-Host "Palabras: $($result.Count)"

# La regresion debe completar el segundo MATCH sin perder el ancla X.
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

for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host "[FAIL] Orden temporal no monotono en indice $i"
        exit 1
    }
}

$errorLines = @($diagnostics | Where-Object { $_ -match 'ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA' })
if ($errorLines.Count -gt 0) {
    Write-Host "[FAIL] Se detecto el error historico: EL ELEMENTO DEL MATCH NO TIENE MAPA"
    exit 1
}

Write-Host "[OK] El ancla X sobrevivio al segundo MATCH"
Write-Host "[OK] Prefijo/historia conservados"
Write-Host "[OK] 5 palabras finales"
Write-Host "[OK] Orden temporal monotono"
Write-Host ""
Write-Host "=== PRUEBA ISSUE 6 PASSED ==="
exit 0
