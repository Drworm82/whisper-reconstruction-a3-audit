# PRUEBA 4 — KEY COLLISION
# Diagnóstico detallado de cada ocurrencia de "cómo"/"como"
# Key generado para ambos: "como" (lowercase, sin acentos ni puntuación)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-key-collision.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

Write-Host "=== PRUEBA 4: KEY COLLISION - DIAGNOSTICO DETALLADO ==="
Write-Host "Fixture: $fixturePath"
Write-Host "WindowDurationSeconds: 10"
Write-Host "OverlapDurationSeconds: 4"
Write-Host ""

# 1. Analizar fixture original
$fixture = Get-Content -Path $fixturePath -Raw | ConvertFrom-Json

Write-Host "--- FIXTURE ORIGINAL ---"
$occurrenceIndex = 0
for ($segIdx = 0; $segIdx -lt $fixture.Segments.Count; $segIdx++) {
    $seg = $fixture.Segments[$segIdx]
    Write-Host ("Segmento {0}: Start={1} End={2}" -f $segIdx, $seg.Start, $seg.End)
    foreach ($w in $seg.Words) {
        $key = $w.Word.ToLower() -replace '[^\p{L}\p{N}%]', ''
        if ($key -eq "como") {
            $occurrenceIndex++
            Write-Host ("  Ocurrencia #{0}: Text='{1}' From={2} To={3} Key='{4}' Segment={5}" -f $occurrenceIndex, $w.Word, $w.Start, $w.End, $key, $segIdx)
        }
    }
}

# 2. Ejecutar pipeline
try {
    $result = Invoke-WhisperReconstruction -WhisperXPath $fixturePath `
                                           -WindowDurationSeconds 10 `
                                           -OverlapDurationSeconds 4
    Write-Host "[OK] Pipeline completado sin excepcion"
} catch {
    Write-Host "[FAIL] Pipeline threw exception: $_"
    exit 1
}

$wordsArray = @($result)

if ($wordsArray.Count -eq 0) {
    Write-Host "[FAIL] Resultado vacio"
    exit 1
}

Write-Host "[OK] Resultado contiene $($wordsArray.Count) palabras"

# 3. Analizar ventanas generadas
Write-Host ""
Write-Host "--- VENTANAS GENERADAS (simuladas) ---"

. "$projectRoot\src\Import\Convert-WhisperX.ps1"
$segmentWindows = Convert-WhisperX -Path $fixturePath

$flatWords = @()
foreach ($window in $segmentWindows) {
    foreach ($token in $window.Tokens) {
        $flatWords += [PSCustomObject]@{
            Text = $token.Text.Trim()
            From = $token.From
            To   = $token.To
        }
    }
}
$flatWords = $flatWords | Sort-Object -Property From

Write-Host "Flat words (ordenados por From):"
$idx = 0
foreach ($w in $flatWords) {
    $key = $w.Text.ToLower() -replace '[^\p{L}\p{N}%]', ''
    $marker = ""
    if ($key -eq "como") { $marker = "  <-- KEY 'como'" }
    Write-Host ("  [{0}] Text='{1}' From={2} To={3} Key='{4}'{5}" -f $idx, $w.Text, $w.From, $w.To, $key, $marker)
    $idx++
}

. "$projectRoot\src\Windowing\New-WhisperWindows.ps1"
$windows = New-WhisperWindows -Words $flatWords -WindowDurationSeconds 10 -OverlapDurationSeconds 4

Write-Host ""
Write-Host "Ventanas (WindowDuration=10, Overlap=4, step=6):"
$wIdx = 0
foreach ($w in $windows) {
    $comoInWindow = $w.Tokens | Where-Object { ($_.Text.Trim().ToLower() -replace '[^\p{L}\p{N}%]', '') -eq "como" }
    Write-Host ("  Ventana {0}: Start={1} End={2} Tokens={3} Key='como'={4}" -f $wIdx, $w.Start, $w.End, $w.Tokens.Count, $comoInWindow.Count)
    foreach ($t in $comoInWindow) {
        Write-Host ("    -> Token: Text='{0}' From={1} To={2}" -f $t.Text.Trim(), $t.From, $t.To)
    }
    $wIdx++
}

# 4. Analizar resultado final
Write-Host ""
Write-Host "--- RESULTADO FINAL ---"
$finalComo = @()
foreach ($w in $wordsArray) {
    $key = $w.Text.ToLower() -replace '[^\p{L}\p{N}%]', ''
    if ($key -eq "como") {
        $finalComo += $w
    }
}

Write-Host ("Palabras con Key 'como' en resultado final: {0}" -f $finalComo.Count)
foreach ($w in $finalComo) {
    Write-Host ("  Text='{0}' From={1} To={2} Id={3}" -f $w.Text, $w.From, $w.To, $w.Id)
}

# 5. Comparar: qué ocurrencias del fixture llegaron al resultado
Write-Host ""
Write-Host "--- COMPARACION: FIXTURE vs RESULTADO ---"
$fixtureComo = @()
for ($segIdx = 0; $segIdx -lt $fixture.Segments.Count; $segIdx++) {
    $seg = $fixture.Segments[$segIdx]
    foreach ($w in $seg.Words) {
        $key = $w.Word.ToLower() -replace '[^\p{L}\p{N}%]', ''
        if ($key -eq "como") {
            $fixtureComo += [PSCustomObject]@{
                Text = $w.Word
                From = $w.Start
                To   = $w.End
                Segment = $segIdx
            }
        }
    }
}

Write-Host ("Ocurrencias en fixture: {0}" -f $fixtureComo.Count)
Write-Host ("Ocurrencias en resultado: {0}" -f $finalComo.Count)

if ($fixtureComo.Count -gt $finalComo.Count) {
    $lost = $fixtureComo.Count - $finalComo.Count
    Write-Host ("[WARN] Se perdieron {0} ocurrencias con Key 'como' en el pipeline" -f $lost)
    Write-Host "       Posibles causas: windowing (fuera de rango), deduplicacion, Find-WordOverlap, u otra etapa"
} elseif ($fixtureComo.Count -eq $finalComo.Count) {
    Write-Host "[OK] Todas las ocurrencias del fixture llegaron al resultado"
} else {
    Write-Host "[INFO] Hay mas ocurrencias en resultado que en fixture (inesperado)"
}

# 6. Verificar orden temporal
$prevFrom = -1
$orderOk = $true
foreach ($w in $finalComo) {
    if ($w.From -lt $prevFrom) {
        Write-Host ("[FAIL] Violacion de orden en Key 'como': From={0} < {1}" -f $w.From, $prevFrom)
        $orderOk = $false
    }
    $prevFrom = $w.From
}
if ($orderOk) { Write-Host "[OK] Orden temporal correcto en Key 'como'" }

# 7. Verificar bloques repetidos
$allText = $wordsArray.Text
$minBlockSize = 3
$duplicateBlocks = $false
for ($i = 0; $i -le $allText.Count - $minBlockSize; $i++) {
    $block = $allText[$i..($i + $minBlockSize - 1)] -join ' '
    $blockNext = $allText[($i + 1)..($i + $minBlockSize)] -join ' '
    if ($block -eq $blockNext) {
        Write-Host ("[FAIL] Bloque repetido: {0}" -f $block)
        $duplicateBlocks = $true
    }
}
if (-not $duplicateBlocks) { Write-Host "[OK] No hay bloques repetidos" }

Write-Host ""
Write-Host "=== DIAGNOSTICO KEY COLLISION COMPLETADO ==="
Write-Host "Nota: Este test reporta diagnostico; no declara PASS/FAIL automaticamente."
Write-Host "Revisar la salida para determinar si la colision causa bug real."
exit 0