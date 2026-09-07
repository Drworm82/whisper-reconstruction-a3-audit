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

    $finalWords = @(
        Build-WhisperWords $windows[0].Tokens -WindowIndex 0
    )

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
            }
        }
    }

    for ($i = 1; $i -lt $windows.Count; $i++) {
        $previous = $windows[$i - 1]
        $current  = $windows[$i]

        $previousWords = @(
            Build-WhisperWords $previous.Tokens -WindowIndex ($i - 1)
        )
        $currentWords = @(
            Build-WhisperWords $current.Tokens -WindowIndex $i
        )

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

        $match = Find-WordOverlap $prevOverlap $currOverlap

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "TRANSICION $($previous.Start)s -> $($current.Start)s"
        Write-Host "============================================================"

        if ($null -eq $previousOverlapMap) {
            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }
        }

        if ($null -eq $match) {
            Write-Host "SIN MATCH"

            $bandDuration = $overlapEnd - $overlapStart
            $driftAllowance = [math]::Max(
                0.5,
                [math]::Min(1.5, $bandDuration * 0.2)
            )

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

            function Test-BandPairEvidence {
                param(
                    [string]$text,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText,
                    [double]$driftAllowance
                )

                if (-not ($prevBandByText.ContainsKey($text) -and $currBandByText.ContainsKey($text))) {
                    return $false
                }

                $prevOccurrences = @($prevBandByText[$text])
                $currOccurrences = @($currBandByText[$text])

                if ($prevOccurrences.Count -lt 1 -or $currOccurrences.Count -lt 1 -or $prevOccurrences.Count -ne $currOccurrences.Count) {
                    return $false
                }

                for ($occ = 0; $occ -lt $prevOccurrences.Count; $occ++) {
                    $fromDiff = [math]::Abs($prevOccurrences[$occ].From - $currOccurrences[$occ].From)
                    $toDiff   = [math]::Abs($prevOccurrences[$occ].To - $currOccurrences[$occ].To)
                    if ($fromDiff -gt $driftAllowance -or $toDiff -gt $driftAllowance) {
                        return $false
                    }
                }

                return $true
            }

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

                if (-not ($newWord.From -lt $bandEnd -and $newWord.To -gt $bandStart)) { return $false }
                if ([string]::IsNullOrEmpty($newWord.Key)) { return $false }
                if (-not (Test-BandPairEvidence $newTextNormalized $prevBandByText $currBandByText $driftAllowance)) { return $false }

                for ($idx = 0; $idx -lt $existingWords.Count; $idx++) {
                    $existing = $existingWords[$idx]
                    if ($newTextNormalized -ne (($existing.Text.ToLower()).Trim())) { continue }

                    $fromDiff = [math]::Abs($newWord.From - $existing.From)
                    $toDiff   = [math]::Abs($newWord.To   - $existing.To)

                    if ($fromDiff -le $driftAllowance -and $toDiff -le $driftAllowance) {
                        if ($claimed.Contains($idx)) { continue }
                        $claimed.Add($idx) | Out-Null
                        return $true
                    }
                }

                return $false
            }

            function Test-TransitiveWordAlreadyExists {
                param(
                    [object]$newWord,
                    [object[]]$existingWords,
                    [double]$bandStart,
                    [double]$bandEnd,
                    [double]$transitiveAllowance,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText,
                    [hashtable]$accBandByText,
                    [System.Collections.Generic.HashSet[int]]$claimed
                )

                $newTextNormalized = ($newWord.Text.ToLower()).Trim()

                if (-not ($newWord.From -lt $bandEnd -and $newWord.To -gt $bandStart)) { return $false }
                if ([string]::IsNullOrEmpty($newWord.Key)) { return $false }
                if ($prevBandByText.ContainsKey($newTextNormalized)) { return $false }
                if (-not $accBandByText.ContainsKey($newTextNormalized)) { return $false }

                $accOccurrences = @($accBandByText[$newTextNormalized])
                $currOccurrences = @($currBandByText[$newTextNormalized])
                if ($accOccurrences.Count -lt 1 -or $currOccurrences.Count -lt 1 -or $accOccurrences.Count -ne $currOccurrences.Count) { return $false }

                $accSorted = @($accOccurrences | Sort-Object -Property From)
                $currSorted = @($currOccurrences | Sort-Object -Property From)

                for ($k = 0; $k -lt $accSorted.Count; $k++) {
                    $fromDiff = [math]::Abs($accSorted[$k].From - $currSorted[$k].From)
                    $toDiff   = [math]::Abs($accSorted[$k].To   - $currSorted[$k].To)
                    if ($fromDiff -gt $transitiveAllowance -or $toDiff -gt $transitiveAllowance) { return $false }
                }

                $slot = -1
                for ($k = 0; $k -lt $currSorted.Count; $k++) {
                    if ($currSorted[$k].Id -eq $newWord.Id) { $slot = $k; break }
                }
                if ($slot -lt 0) { return $false }

                $partner = $accSorted[$slot]
                for ($idx = 0; $idx -lt $existingWords.Count; $idx++) {
                    if ($existingWords[$idx].Id -eq $partner.Id) {
                        if ($claimed.Contains($idx)) { return $false }
                        $claimed.Add($idx) | Out-Null
                        return $true
                    }
                }

                return $false
            }

            function Add-NewWordsWithTiming {
                param(
                    [object[]]$currentWords,
                    [object[]]$finalWords,
                    [double]$bandStart,
                    [double]$bandEnd,
                    [double]$driftAllowance,
                    [hashtable]$prevBandByText,
                    [hashtable]$currBandByText,
                    [double]$transitiveAllowance,
                    [hashtable]$accBandByText
                )

                $result = @($finalWords)
                $claimed = New-Object 'System.Collections.Generic.HashSet[int]'

                foreach ($word in $currentWords) {
                    if (-not (Test-WordAlreadyExists $word $result $bandStart $bandEnd $driftAllowance $prevBandByText $currBandByText $claimed)) {
                        if (-not (Test-TransitiveWordAlreadyExists $word $result $bandStart $bandEnd $transitiveAllowance $prevBandByText $currBandByText $accBandByText $claimed)) {
                            $result += $word
                        }
                    }
                }

                return @($result)
            }

            $transitiveAllowance = [math]::Min($driftAllowance, 0.5)
            $accBandByText = @{}
            foreach ($existingWord in $finalWords) {
                if ($existingWord.From -lt $overlapEnd -and $existingWord.To -gt $overlapStart) {
                    $bandText = ($existingWord.Text.ToLower()).Trim()
                    if ($accBandByText.ContainsKey($bandText)) {
                        $accBandByText[$bandText] = @($accBandByText[$bandText]) + $existingWord
                    } else {
                        $accBandByText[$bandText] = @($existingWord)
                    }
                }
            }

            $finalWords = @(
                Add-NewWordsWithTiming `
                    $currentWords `
                    $finalWords `
                    $overlapStart `
                    $overlapEnd `
                    $driftAllowance `
                    $prevBandByText `
                    $currBandByText `
                    $transitiveAllowance `
                    $accBandByText
            )

            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }

            continue
        }

        $matchedWord = $prevOverlap[$match.PreviousStart]
        if ($null -eq $matchedWord) {
            Write-Host "ERROR: EL ELEMENTO DEL MATCH ES NULL"
            continue
        }

        $prefixCount = $null
        if ($previousOverlapMap.ContainsKey($matchedWord.Id)) {
            $prefixCount = $previousOverlapMap[$matchedWord.Id]
        }

        if ($null -eq $prefixCount) {
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                if ($finalWords[$idx].Id -eq $matchedWord.Id) {
                    $prefixCount = $idx
                    break
                }
            }
        }

        if ($null -eq $prefixCount) {
            # The match anchor is not represented in the accumulated transcript.
            # This is not a recoverable state for prefix reconstruction; do not
            # silently continue with a truncated transcript.
            Write-Host "ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA"
            continue
        }

        if ($prefixCount -lt 0 -or $prefixCount -gt $finalWords.Count) {
            Write-Host "ERROR: PREFIX COUNT INVALIDO"
            Write-Host "PrefixCount = $prefixCount"
            Write-Host "FinalCount  = $($finalWords.Count)"
            continue
        }

        $prefix = @()
        if ($prefixCount -gt 0) {
            $prefix = @($finalWords | Select-Object -First $prefixCount)
        }

        $currentMatch = @(
            $currOverlap |
            Select-Object -Skip $match.CurrentStart -First $match.CurrentConsumed
        )
        if ($currentMatch.Count -eq 0) {
            Write-Host "MATCH INVALIDO"
            continue
        }

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
        if ($currentLastIndexInWords -lt 0 -or $currentLastIndexInWords -ge $currentWords.Count) {
            Write-Host "ERROR: CURRENT LAST INDEX INVALIDO"
            continue
        }

        $after = @()
        if ($currentLastIndexInWords + 1 -lt $currentWords.Count) {
            $after = @($currentWords | Select-Object -Skip ($currentLastIndexInWords + 1))
        }

        $newFinal = @()
        foreach ($word in $prefix) { $newFinal += $word }
        foreach ($word in $currentMatch) { $newFinal += $word }
        foreach ($word in $after) { $newFinal += $word }

        $finalWords = @($newFinal)

        # Rebuild state from the complete accumulated transcript after MATCH.
        # A subsequent transition may use any surviving word as its match anchor;
        # limiting this map to currOverlap loses valid prefix state.
        $previousOverlapMap = @{}
        for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
            $previousOverlapMap[$finalWords[$idx].Id] = $idx
        }
    }

    return @($finalWords)
}
