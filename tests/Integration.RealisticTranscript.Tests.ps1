# Test de Integración: Transcripción Continua Realista
# Valida pipeline con ventanas solapadas generando texto sin duplicar bloques

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
    $result = Reconstruct-WhisperWindows -windows $fixture.Segments
    
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
    
    # Buscar cualquier palabra que aparezca no consecutivamente (repetida)
    $allWords = $result.Text
    $wordGroups = @{}
    
    foreach ($word in $allWords) {
        if (-not $wordGroups.ContainsKey($word)) {
            $wordGroups[$word] = @()
        }
        $wordGroups[$word] += $word
    }
    
    # Verificar duplicados para cada palabra
    foreach ($word in $wordGroups.Keys) {
        $occurrences = $wordGroups[$word]
        if ($occurrences.Count -gt 1) {
            # Encontrar posiciones
            $positions = @()
            for ($i = 0; $i -lt $allWords.Count; $i++) {
                if ($allWords[$i] -eq $word) {
                    $positions += $i
                }
            }
            
            if ($positions.Count -gt 1) {
                # Si hay posiciones no consecutivas, es un duplicado
                for ($i = 0; $i -lt $positions.Count - 1; $i++) {
                    if ($positions[$i] -ne $positions[$i + 1] - 1) {
                        $duplicateBlocksFound = $true
                        Write-Host "✗ Palabra '$word' aparece repetidamente en posiciones: $($positions -join ', ')"
                        break
                    }
                }
            }
        }
    }
    
    if (-not $duplicateBlocksFound) {
        Write-Host "✓ No hay bloques repetidos detectados en el texto final"
        $testsPassed++
    } else {
        Write-Host "✗ Se encontraron bloques repetidos en el texto final"
    }
    
    # Test 4: Descripción coherente (continuación natural)
    $totalTests++
    $firstSegmentText = $fixture.Segments[0].Tokens.Text -join " "
    $lastSegmentText = $fixture.Segments[-1].Tokens.Text -join " "
    
    # Verificar que el texto continua lógicamente
    $textContinuity = $true
    if (-not $firstSegmentText.Contains($lastSegmentText.Substring(0, [math]::Min(10, $lastSegmentText.Length)))) {
        # Verificar overlap de al menos 5 palabras
        $firstWords = $fixture.Segments[0].Tokens.Text
        $secondWords = $fixture.Segments[1].Tokens.Text
        
        $overlapWords = 0
        for ($i = 0; $i -lt [math]::Min($firstWords.Count, $secondWords.Count); $i++) {
            if ($firstWords[$i] -eq $secondWords[$i]) {
                $overlapWords++
            } else {
                break
            }
        }
        
        if ($overlapWords -ge 5) {
            Write-Host "✓ Segmentos tienen suficiente continuidad (overlap de $overlapWords palabras)"
            $testsPassed++
        } else {
            Write-Host "✗ Poca continuidad entre segmentos (overlap de solo $overlapWords palabras)"
            $textContinuity = $false
        }
    } else {
        Write-Host "✓ Segmentos muestran continuidad natural"
        $testsPassed++
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