# PRUEBA A2 — PERDIDA DE PALABRA EN EL HUECO DEL WINDOWING
#
# Hallazgo de auditoria (151dc76): New-WhisperWindows.ps1 solo incluye una
# palabra en una ventana si TODO su intervalo [From, To] cabe dentro de
# [windowStart, windowEnd]. Con WindowDurationSeconds=10, OverlapDurationSeconds=3
# (step=7), cualquier palabra con duracion d tal que step < d < WindowDuration
# (7 < d < 10) puede caer en una posicion donde ningun windowStart_k satisface
# la condicion de inclusion, desapareciendo de TODAS las ventanas.
#
# Este test usa una palabra "LARGA" con From=4.0, To=12.0 (duracion=8s,
# 7 < 8 < 10), que segun el trazado manual de la auditoria no debe aparecer
# en ninguna de las ventanas generadas.
#
# IMPORTANTE (segun instruccion explicita): este test documenta el
# comportamiento DEFECTUOSO actual. La asercion correcta es que "LARGA" SI
# deberia aparecer en al menos una ventana; como el codigo actual la pierde,
# el test debe terminar en FAIL (exit 1), no en PASS. Un PASS aqui solo debe
# ocurrir una vez que el bug este corregido en New-WhisperWindows.ps1.
#
# No se modifica src/Windowing/New-WhisperWindows.ps1 en este paso.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Windowing\New-WhisperWindows.ps1"

$pass = $true

Write-Host "=== PRUEBA A2: PERDIDA DE PALABRA EN EL HUECO DEL WINDOWING ==="
Write-Host "WindowDurationSeconds=10, OverlapDurationSeconds=3 (step=7)"
Write-Host ""

$words = @(
    [PSCustomObject]@{ Text = "ancla_inicio"; From = 0.0;  To = 0.5 }
    [PSCustomObject]@{ Text = "LARGA";        From = 4.0;  To = 12.0 }   # duracion=8s -> 7 < 8 < 10
    [PSCustomObject]@{ Text = "ancla_fin";    From = 25.0; To = 25.5 }
)

Write-Host "Palabra bajo prueba: 'LARGA' From=4.0 To=12.0 (duracion=8.0s)"
Write-Host ""

try {
    $windows = New-WhisperWindows -Words $words -WindowDurationSeconds 10 -OverlapDurationSeconds 3
    Write-Host "[OK] New-WhisperWindows ejecuto sin excepcion"
} catch {
    Write-Host "[FAIL] New-WhisperWindows lanzo excepcion: $_"
    exit 1
}

Write-Host "Ventanas generadas: $($windows.Count)"
$wIdx = 0
$foundInWindows = @()
foreach ($w in $windows) {
    $texts = @($w.Tokens | ForEach-Object { $_.Text.Trim() })
    $hasLarga = $texts -contains "LARGA"
    Write-Host ("  Ventana {0}: Start={1} End={2} Tokens=[{3}] ContieneLARGA={4}" -f $wIdx, $w.Start, $w.End, ($texts -join ', '), $hasLarga)
    if ($hasLarga) { $foundInWindows += $wIdx }
    $wIdx++
}

Write-Host ""

if ($foundInWindows.Count -eq 0) {
    Write-Host "[FAIL] 'LARGA' (From=4.0, To=12.0) no aparece en NINGUNA ventana."
    Write-Host "       Esto confirma el hallazgo A2: perdida total de palabra por diseno de"
    Write-Host "       New-WhisperWindows.ps1 (word.From -ge windowStart AND word.To -le windowEnd)"
    Write-Host "       cuando step < duracion(palabra) < WindowDurationSeconds."
    $pass = $false
} else {
    Write-Host "[OK] 'LARGA' aparece en la(s) ventana(s): $($foundInWindows -join ', ')"
}

# Verificacion adicional: las palabras ancla (duracion normal, muy por debajo del step)
# deben sobrevivir sin problema, para aislar el defecto especificamente a la duracion larga.
$anchorWordsOk = $true
foreach ($w in $windows) {
    $texts = @($w.Tokens | ForEach-Object { $_.Text.Trim() })
}
$allTexts = @()
foreach ($w in $windows) {
    $allTexts += @($w.Tokens | ForEach-Object { $_.Text.Trim() })
}
if (-not ($allTexts -contains "ancla_inicio")) {
    Write-Host "[FAIL] 'ancla_inicio' tambien se perdio (inesperado, revisar diseno del test)"
    $anchorWordsOk = $false
}
if (-not ($allTexts -contains "ancla_fin")) {
    Write-Host "[FAIL] 'ancla_fin' tambien se perdio (inesperado, revisar diseno del test)"
    $anchorWordsOk = $false
}
if ($anchorWordsOk) {
    Write-Host "[OK] Palabras ancla de duracion normal sobreviven (el defecto es especifico de duracion larga)"
} else {
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "=== PRUEBA A2 PASSED (bug corregido) ==="
    exit 0
} else {
    Write-Host "=== PRUEBA A2 FAILED (bug A2 confirmado: perdida de palabra en el hueco del windowing) ==="
    exit 1
}
