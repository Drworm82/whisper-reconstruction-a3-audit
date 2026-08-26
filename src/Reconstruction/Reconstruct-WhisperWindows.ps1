# ============================================================
# Reconstruct-WhisperWindows
# ============================================================

function Reconstruct-WhisperWindows {
    param($windows)

    if ($null -eq $windows -or $windows.Count -eq 0) {
        return @()
    }

    for ($idx = 0; $idx -lt $windows.Count; $idx++) {
        $window = $windows[$idx]

        if (-not ($window.PSObject.Properties.Match("Start").Count)) {
            throw "Invalid window at index $idx : missing property 'Start'."
        }

        if (-not ($window.PSObject.Properties.Match("End").Count)) {
            throw "Invalid window at index $idx : missing property 'End'."
        }

        if (-not ($window.PSObject.Properties.Match("Tokens").Count)) {
            throw "Invalid window at index $idx : missing property 'Tokens'."
        }
    }

    # ============================================================
    # PRIMERA VENTANA
    # ============================================================

    $finalWords = @(
        Build-WhisperWords $windows[0].Tokens -WindowIndex 0
    )

    # ============================================================
    # MAPA DEL OVERLAP DE LA VENTANA PREVIA
    # ============================================================

    $previousOverlapMap = @{}

    if ($windows.Count -gt 1) {
        $firstWords = $finalWords
        $overlapStart = $windows[1].Start
        $overlapEnd   = $windows[0].End

        $firstOverlap = @(
            $firstWords |
            Where-Object {
                $_.From -lt $overlapEnd -and
                $_.To   -gt $overlapStart
            }
        )

        foreach ($word in $firstOverlap) {
            $foundIndex = -1
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                if ($finalWords[$idx].Id -eq $word.Id) {
                    $foundIndex = $idx
                    break
                }
            }

            if ($foundIndex -ne -1) {
                $previousOverlapMap[$word.Id] = $foundIndex
            } else {
                Write-Host "DIAGNOSTICO INICIAL: Palabra del overlap '$($word.Text)' (ID: $($word.Id)) no encontrada en finalWords."
            }
        }
    }

    # ============================================================
    # VENTANAS SIGUIENTES
    # ============================================================

    for ($i = 1; $i -lt $windows.Count; $i++) {

        $previous = $windows[$i - 1]
        $current  = $windows[$i]

        $previousWords = @(
            Build-WhisperWords $previous.Tokens -WindowIndex ($i - 1)
        )

        $currentWords = @(
            Build-WhisperWords $current.Tokens -WindowIndex $i
        )

        # --------------------------------------------------------
        # SOLAPAMIENTO TEMPORAL
        # --------------------------------------------------------

        $overlapStart = $current.Start
        $overlapEnd   = $previous.End

        $prevOverlap = @(
            $previousWords |
            Where-Object {
                $_.From -lt $overlapEnd -and
                $_.To   -gt $overlapStart
            }
        )

        $currOverlap = @(
            $currentWords |
            Where-Object {
                $_.From -lt $overlapEnd -and
                $_.To   -gt $overlapStart
            }
        )

        # --------------------------------------------------------
        # BUSCAR MATCH
        # --------------------------------------------------------

        $match = Find-WordOverlap `
            $prevOverlap `
            $currOverlap

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "TRANSICION $($previous.Start)s -> $($current.Start)s"
        Write-Host "============================================================"

        # --------------------------------------------------------
        # VALIDAR MAPA Y MATCH
        # --------------------------------------------------------

        if ($null -eq $previousOverlapMap) {
            Write-Host "ERROR: NO EXISTE MAPA PREVIO"
            continue
        }

        if ($null -eq $match) {
            Write-Host "SIN MATCH"
            
            # Helper: Test if a word already exists based on text and timing
            function Test-WordAlreadyExists {
                param(
                    [object]$newWord,
                    [object[]]$existingWords
                )
                
                foreach ($existing in $existingWords) {
                    # Normalize text comparison (case-insensitive, trim)
                    $newTextNormalized = ($newWord.Text.ToLower()).Trim()
                    $existingTextNormalized = ($existing.Text.ToLower()).Trim()
                    
                    if ($newTextNormalized -eq $existingTextNormalized) {
                        # Check timing differences
                        $fromDiff = [math]::Abs($newWord.From - $existing.From)
                        $toDiff = [math]::Abs($newWord.To - $existing.To)
                        
                        if ($fromDiff -le 0.5 -and $toDiff -le 0.5) {
                            return $true
                        }
                    }
                }
                
                return $false
            }
            
            # Helper: Add new words avoiding duplicates based on text and timing
            function Add-NewWordsWithTiming {
                param(
                    [object[]]$currentWords,
                    [object[]]$finalWords
                )
                
                $result = @($finalWords)
                
                foreach ($word in $currentWords) {
                    if (-not (Test-WordAlreadyExists $word $result)) {
                        $result += $word
                    }
                }
                
                return $result
            }
            
            # Helper: Build previousOverlapMap for currentWords based on currOverlap
            function Build-PreviousOverlapMap {
                param(
                    [object[]]$currOverlap,
                    [object[]]$currentWords
                )
                
                $previousOverlapMap = @{}
                foreach ($word in $currOverlap) {
                    $foundIndex = -1
                    for ($idx = 0; $idx -lt $currentWords.Count; $idx++) {
                        if ($currentWords[$idx].Id -eq $word.Id) {
                            $foundIndex = $idx
                            break
                        }
                    }
                    if ($foundIndex -ne -1) {
                        $previousOverlapMap[$word.Id] = $foundIndex
                    }
                }
                return $previousOverlapMap
            }
            
            # Get currentWords for the current window
            $currentWords = @(
                Build-WhisperWords $current.Tokens -WindowIndex $i
            )
            
            # Build previousOverlapMap for currentWords based on currOverlap
            $previousOverlapMap = Build-PreviousOverlapMap $currOverlap $currentWords
            
            # Add words based on text and timing deduplication
            $finalWords = Add-NewWordsWithTiming $currentWords $finalWords
            
            # Continue reconstruction from this point without losing history
            continue
        }

        $matchedWord = $prevOverlap[$match.PreviousStart]

        if ($null -eq $matchedWord) {
            Write-Host "ERROR: EL ELEMENTO DEL MATCH ES NULL"
            continue
        }

        $prefixCount = $previousOverlapMap[$matchedWord.Id]

        if ($null -eq $prefixCount) {
            # Fallback de búsqueda directa por ID en finalWords
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                if ($finalWords[$idx].Id -eq $matchedWord.Id) {
                    $prefixCount = $idx
                    break
                }
            }
        }

        if ($null -eq $prefixCount) {
            Write-Host "ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA"
            continue
        }

        if (
            $prefixCount -lt 0 -or
            $prefixCount -gt $finalWords.Count
        ) {
            Write-Host "ERROR: PREFIX COUNT INVALIDO"
            Write-Host "PrefixCount = $prefixCount"
            Write-Host "FinalCount  = $($finalWords.Count)"
            continue
        }

        $prefix = @()

        if ($prefixCount -gt 0) {
            $prefix = @(
                $finalWords |
                Select-Object -First $prefixCount
            )
        }

        # ========================================================
        # CURRENT MATCH
        # ========================================================

        $currentMatch = @(
            $currOverlap |
            Select-Object `
                -Skip $match.CurrentStart `
                -First $match.CurrentConsumed
        )

        if ($currentMatch.Count -eq 0) {
            Write-Host "MATCH INVALIDO"
            continue
        }

        # ========================================================
        # CORRECTED OFFSET FOR AFTER
        # ========================================================

        $overlapStartInCurrent = -1
        if ($currOverlap.Count -gt 0) {
            for ($j = 0; $j -lt $currentWords.Count; $j++) {
                if ($currentWords[$j].Id -eq $currOverlap[0].Id) {
                    $overlapStartInCurrent = $j
                    break
                }
            }
        }

        if ($overlapStartInCurrent -lt 0) {
            Write-Host "ERROR: NO SE PUDO LOCALIZAR EL INICIO DEL OVERLAP EN CURRENT WORDS"
            continue
        }

        $currentLastIndexInWords = $overlapStartInCurrent + $match.CurrentStart + $match.CurrentConsumed - 1

        if (
            $currentLastIndexInWords -lt 0 -or
            $currentLastIndexInWords -ge $currentWords.Count
        ) {
            Write-Host "ERROR: CURRENT LAST INDEX INVALIDO"
            continue
        }

        # ========================================================
        # AFTER
        # ========================================================

        $after = @()

        if ($currentLastIndexInWords + 1 -lt $currentWords.Count) {
            $after = @(
                $currentWords |
                Select-Object `
                    -Skip ($currentLastIndexInWords + 1)
            )
        }

        # ========================================================
        # POSICION ABSOLUTA DE LA NUEVA INSERCION
        # ========================================================

        $insertionStart = $prefix.Count

        # ========================================================
        # RECONSTRUIR
        # ========================================================

        $newFinal = @()

        foreach ($word in $prefix) {
            $newFinal += $word
        }

        foreach ($word in $currentMatch) {
            $newFinal += $word
        }

        foreach ($word in $after) {
            $newFinal += $word
        }

        $finalWords = @(
            $newFinal
        )

        # ========================================================
        # CONSTRUIR MAPA RECORRIENDO CURROVERLAP
        # ========================================================

        $previousOverlapMap = @{}

        for ($k = 0; $k -lt $currOverlap.Count; $k++) {
            $word = $currOverlap[$k]

            # 1. Buscar esa palabra por Id dentro de finalWords
            $foundIndex = -1
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                if ($finalWords[$idx].Id -eq $word.Id) {
                    $foundIndex = $idx
                    break
                }
            }

            # 2. Si existe: guardar: $previousOverlapMap[$word.Id] = índice absoluto
            if ($foundIndex -ne -1) {
                $previousOverlapMap[$word.Id] = $foundIndex
            } else {
                # 3. Si no existe: investigar por qué esa palabra fue descartada. No asignar null silenciosamente.
                $reason = "Desconocida"
                if ($k -lt $match.CurrentStart) {
                    $reason = "Descartada por estar antes del inicio del match (CurrentStart = $($match.CurrentStart))"
                } elseif ($k -ge ($match.CurrentStart + $match.CurrentConsumed)) {
                    $reason = "Descartada por estar después de la zona consumida por el match (CurrentConsumed = $($match.CurrentConsumed))"
                } else {
                    $reason = "Omitida por alineamiento/distancia de edición durante el match"
                }
                Write-Host "DIAGNOSTICO: Palabra del overlap '$($word.Text)' (ID: $($word.Id)) fue descartada de finalWords. Razón: $reason"
            }
        }

        # ========================================================
        # DIAGNOSTICO
        # ========================================================

        Write-Host "PreviousStart      : $($match.PreviousStart)"
        Write-Host "CurrentStart       : $($match.CurrentStart)"
        Write-Host "CurrentConsumed    : $($match.CurrentConsumed)"
        Write-Host "PrefixCount        : $($prefix.Count)"
        Write-Host "CurrentMatch       : $($currentMatch.Count)"
        Write-Host "After               : $($after.Count)"
        Write-Host "FinalWords          : $($finalWords.Count)"

        Write-Host ""
        Write-Host "MAPA CURRENT OVERLAP:"

        for ($k = 0; $k -lt $currOverlap.Count; $k++) {
            $target = $currOverlap[$k]
            
            # Buscar en el mapa que acabamos de construir
            if ($previousOverlapMap.ContainsKey($target.Id)) {
                $targetLabel = $previousOverlapMap[$target.Id]
            } else {
                $targetLabel = "DISCARDED"
            }

            Write-Host (
                "[{0,2}] [{1}] -> FINAL[{2}]" -f `
                $k,
                $target.Text,
                $targetLabel
            )
        }

        Write-Host ""
        Write-Host "PALABRAS ACUMULADAS: $($finalWords.Count)"
    }

    return @(
        $finalWords
    )
}
