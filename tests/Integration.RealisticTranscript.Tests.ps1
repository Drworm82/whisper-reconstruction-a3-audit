# Test de Integración: Transcripción Continua Realista
# Valida pipeline con ventanas solapadas generando texto sin duplicar bloques

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

# ============================================================
# CONFIGURACIÓN DEL TEST
# ============================================================

$testConfig = @{ 
    FixturePath = "tests/fixtures/whisperx-continuous-test.json"
    WindowDurationSeconds = 30
    OverlapDurationSeconds = 10
    ExpectedMinimumWords = 30
    Description = "Test de transcripción continua realista con ventanas solapadas"
}

# ============================================================
# FUNCIÓN DE VALIDACIÓN
# ============================================================

function Validate-ContinuousTranscript {
    param(
        [hashtable]$config
    )
    
    Write-Host "Test: $($config.Description)"
    Write-Host "Fixture: $($config.FixturePath)"
    Write-Host "Ventana: $($config.WindowDurationSeconds)s, Overlap: $($config.OverlapDurationSeconds)s"
    
    # Cargar fixture JSON
    $fixture = Get-Content -Path $config.FixturePath -Raw | ConvertFrom-Json
    
    # Ejecutar pipeline
    $result = Invoke-WhisperReconstruction -WhisperXPath $config.FixturePath `
                                                -WindowDurationSeconds $config.WindowDurationSeconds `
                                                -OverlapDurationSeconds $config.OverlapDurationSeconds
    
    # Validaciones
    $testsPassed = 0
    $totalTests = 0
    
    # Test 1: Pipeline termina sin error
    $totalTests++
    if ($result -ne $null) {
        Write-Host "✓ Pipeline completado sin excepción"
        $testsPassed++
    } else {
        Write-Host "✗ Pipeline devolvió null"
    }
    
    # Test 2: Resultado contiene palabras suficientes
    $totalTests++
    if ($result.Count -ge $config.ExpectedMinimumWords) {
        Write-Host "✓ Palabras finales: $($result.Count) (>= $($config.ExpectedMinimumWords))"
        $testsPassed++
    } else {
        Write-Host "✗ Palabras finales: $($result.Count) (< $($config.ExpectedMinimumWords))"
    }
    
    # Test 3: No hay bloques repetidos dentro del texto final
    $totalTests++
    $duplicateBlocksFound = $false
    
    # Buscar bloques de 3+ palabras consecutivas repetidas en el texto final
    $allWords = $result.Text
    $minBlockSize = 3
    
    for ($i = 0; $i -lt $allWords.Count - $minBlockSize; $i++) {
        $block = $allWords[$i..($i + $minBlockSize - 1)] -join ' '
        $blockNext = $allWords[($i + 1)..($i + $minBlockSize)] -join ' '

        if ($block -eq $blockNext) {
            $duplicateBlocksFound = $true
            Write-Host "✗ Bloque repetido detectado: $block"
            break
        }
    }
    
    if (-not $duplicateBlocksFound) {
        Write-Host "✓ No hay bloques repetidos detectados en el texto final"
        $testsPassed++
    } else {
        Write-Host "✗ Se encontraron bloques repetidos en el texto final"
    }
    # Test 4: El fixture tiene estructura de transcripción continua con overlaps
    $totalTests++
    $firstSegmentWords = $fixture.Segments[0].Words.Word
    $secondSegmentWords = $fixture.Segments[1].Words.Word
    
    # Verificar que el segmento 1 comparte al menos 5 palabras con el segmento 0
    $overlapWords = 0
    $maxCheck = [math]::Min($firstSegmentWords.Count, $secondSegmentWords.Count)
    if ($maxCheck -gt 10) { $maxCheck = 10 }

    # Buscar el principio del segmento 1 dentro del segmento 0
    for ($i = 0; $i -lt $firstSegmentWords.Count - $maxCheck + 1; $i++) {
        $matchCount = 0
        for ($j = 0; $j -lt $maxCheck; $j++) {
            if ($firstSegmentWords[$i + $j] -eq $secondSegmentWords[$j]) {
                $matchCount++
            } else {
                break
            }
        }
        if ($matchCount -gt $overlapWords) {
            $overlapWords = $matchCount
        }
    }
    
    if ($overlapWords -ge 5) {
        Write-Host "✓ Segmentos tienen suficiente continuidad (overlap de $overlapWords palabras)"
        $testsPassed++
    } else {
        Write-Host "✗ Poca continuidad entre segmentos (overlap de solo $overlapWords palabras)"
    }

    # Resultado final
    Write-Host ""
    Write-Host "Resultado: $testsPassed/$totalTests tests pasaron"
    
    if ($testsPassed -eq $totalTests) {
        Write-Host "Test de Transcripción Continua Completado"
        return $true
    } else {
        Write-Host "Test de Transcripción Continua Falló"
        return $false
    }
}

# ============================================================
# EJECUCIÓN DEL TEST
# ============================================================

# Cargar fixture para validación interna
$fixture = Get-Content -Path $testConfig.FixturePath -Raw | ConvertFrom-Json

# Ejecutar validación
$testResult = Validate-ContinuousTranscript -config $testConfig

if ($testResult) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "INTEGRATION REALISTIC TRANSCRIPT TEST PASSED"
    Write-Host "========================================"
    exit 0
} else {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "INTEGRATION REALISTIC TRANSCRIPT TEST FAILED"
    Write-Host "========================================"
    exit 1
}