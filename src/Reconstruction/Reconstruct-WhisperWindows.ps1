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

            # --------------------------------------------------------
            # DEDUPLICACION CONTEXTUAL EN SIN MATCH (Issue 3)
            #
            # Dos ventanas solapadas re-transcriben la MISMA banda de
            # audio [overlapStart, overlapEnd). Un mismo evento puede
            # aparecer con timestamps desplazados por deriva de ASR; la
            # tolerancia fija de +/-0.5s no lo alcanza y la palabra
            # queda duplicada. Para absorber esa re-transcripcion SIN
            # fusionar dos ocurrencias legitimas se exige evidencia de
            # correspondencia 1:1 dentro de la banda:
            #
            #   1. la palabra nueva cae dentro de la banda;
            #   2. la Key no es vacia (contenido real, no puntuacion);
            #   3. el texto coincide tras la normalizacion existente;
            #   4. el mismo texto aparece el MISMO numero de veces en la
            #      banda de ambas ventanas y en el MISMO orden dentro
            #      del margen de deriva (emparejamiento 1:1 inequivoco);
            #   5. la ocurrencia previa emparejada no absorbe dos veces
            #      (one-to-one con un conjunto 'claimed');
            #   6. la tolerancia deriva del volumen de audio re-transcrito
            #      (mas re-transcripcion, mas deriva acumulable), acotada
            #      entre +/-0.5s (comportamiento historico) y +/-1.5s.
            #
            # Fuera de la banda o sin evidencia 1:1, se conserva la
            # palabra: es preferible conservar antes que absorber una
            # ocurrencia potencialmente legitima.
            # --------------------------------------------------------

            $bandDuration = $overlapEnd - $overlapStart

            $driftAllowance = [math]::Max(
                0.5,
                [math]::Min(1.5, $bandDuration * 0.2)
            )
            Write-Host "DRIFT ALLOWANCE: $driftAllowance s (banda $bandDuration s)"

            # Indice de ocurrencias por texto normalizado dentro de la
            # banda, por ventana. Es la evidencia de correspondencia 1:1
            # en orden: la k-esima ocurrencia de una ventana debe caer
            # dentro del margen de deriva de la k-esima de la otra.
            $prevBandByText = @{}
            $currBandByText = @{}

            foreach ($overlapWord in $prevOverlap) {
                $bandText = ($overlapWord.Text.ToLower()).Trim()
                if ($prevBandByText.ContainsKey($bandText)) {
                    $prevBandByText[$bandText] = @($prevBandByText[$bandText]) + $overlapWord
                } else {
                    $prevBandByText[$bandText] = @($overlapWord)
                }
            }

            foreach ($overlapWord in $currOverlap) {
                $bandText = ($overlapWord.Text.ToLower()).Trim()
                if ($currBandByText.ContainsKey($bandText)) {
                    $currBandByText[$bandText] = @($currBandByText[$bandText]) + $overlapWord
                } else {
                    $currBandByText[$bandText] = @($overlapWord)
                }
            }

            # Helper: verifica la correspondencia 1:1 en orden dentro de la banda
            function Test-BandPairEvidence {
                param(
                    [string]$text,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText,
                    [double]$driftAllowance
                )

                if (-not (
                    $prevBandByText.ContainsKey($text) -and
                    $currBandByText.ContainsKey($text)
                )) {
                    return $false
                }

                $prevOccurrences = @($prevBandByText[$text])
                $currOccurrences = @($currBandByText[$text])

                if (
                    $prevOccurrences.Count -lt 1 -or
                    $currOccurrences.Count -lt 1 -or
                    $prevOccurrences.Count -ne $currOccurrences.Count
                ) {
                    return $false
                }

                for ($occ = 0; $occ -lt $prevOccurrences.Count; $occ++) {
                    $prevOcc = $prevOccurrences[$occ]
                    $currOcc = $currOccurrences[$occ]

                    $fromDiff = [math]::Abs($prevOcc.From - $currOcc.From)
                    $toDiff   = [math]::Abs($prevOcc.To   - $currOcc.To)

                    if (
                        $fromDiff -gt $driftAllowance -or
                        $toDiff   -gt $driftAllowance
                    ) {
                        return $false
                    }
                }

                return $true
            }

            # Helper: Test if a word already exists based on text and timing
            function Test-WordAlreadyExists {
                param(
                    [object]$newWord,
                    [object[]]$existingWords,
                    [double]$bandStart,
                    [double]$bandEnd,
                    [double]$driftAllowance,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText,
                    [System.Collections.Generic.HashSet[int]]$claimed
                )

                $newTextNormalized = ($newWord.Text.ToLower()).Trim()

                if (-not (
                    $newWord.From -lt $bandEnd -and
                    $newWord.To   -gt $bandStart
                )) {
                    return $false
                }

                if ([string]::IsNullOrEmpty($newWord.Key)) {
                    return $false
                }

                if (-not (
                    Test-BandPairEvidence `
                        $newTextNormalized `
                        $prevBandByText `
                        $currBandByText `
                        $driftAllowance
                )) {
                    return $false
                }

                for ($idx = 0; $idx -lt $existingWords.Count; $idx++) {
                    $existing = $existingWords[$idx]

                    $existingTextNormalized = ($existing.Text.ToLower()).Trim()

                    if ($newTextNormalized -ne $existingTextNormalized) {
                        continue
                    }

                    $fromDiff = [math]::Abs($newWord.From - $existing.From)
                    $toDiff   = [math]::Abs($newWord.To   - $existing.To)

                    if (
                        $fromDiff -le $driftAllowance -and
                        $toDiff   -le $driftAllowance
                    ) {
                        if ($claimed.Contains($idx)) {
                            continue
                        }
                        $claimed.Add($idx) | Out-Null
                        return $true
                    }
                }

                return $false
            }

            # Helper: Add new words avoiding duplicates based on text and timing
            function Add-NewWordsWithTiming {
                param(
                    [object[]]$currentWords,
                    [object[]]$finalWords,
                    [double]$bandStart,
                    [double]$bandEnd,
                    [double]$driftAllowance,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText
                )

                $result = @($finalWords)
                $claimed = New-Object 'System.Collections.Generic.HashSet[int]'

                foreach ($word in $currentWords) {
                    if (-not (
                        Test-WordAlreadyExists `
                            $word `
                            $result `
                            $bandStart `
                            $bandEnd `
                            $driftAllowance `
                            $prevBandByText `
                            $currBandByText `
                            $claimed
                    )) {
                        $result += $word
                    }
                }

                return $result
            }

            # Add words based on text and timing deduplication
            $finalWords = Add-NewWordsWithTiming `
                $currentWords `
                $finalWords `
                $overlapStart `
                $overlapEnd `
                $driftAllowance `
                $prevBandByText `
                $currBandByText

            # Build previousOverlapMap for all words in finalWords using their absolute index
            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }

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
