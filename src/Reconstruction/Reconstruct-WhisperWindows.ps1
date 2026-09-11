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
        $firstOverlapStart = $windows[1].Start
        $firstOverlapEnd   = $windows[0].End

        foreach ($word in @(
            $finalWords |
            Where-Object {
                $_.From -lt $firstOverlapEnd -and
                $_.To   -gt $firstOverlapStart
            }
        )) {
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                if ($finalWords[$idx].Id -eq $word.Id) {
                    $previousOverlapMap[$word.Id] = $idx
                    break
                }
            }
        }
    }

    # A prior MATCH may omit words that precede its selected anchor. Those
    # omitted occurrences are retained here so a later MATCH can reuse the
    # exact occurrence when it becomes an anchor.
    $deferredWordsByText = @{}

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
        }

        if ($null -ne $match) {
            $guardMatchedWord = $prevOverlap[$match.PreviousStart]
            $guardPrefixCount = $null

            if ($null -ne $guardMatchedWord) {
                if ($previousOverlapMap.ContainsKey($guardMatchedWord.Id)) {
                    $guardPrefixCount = $previousOverlapMap[$guardMatchedWord.Id]
                } else {
                    for ($guardIdx = 0; $guardIdx -lt $finalWords.Count; $guardIdx++) {
                        if ($finalWords[$guardIdx].Id -eq $guardMatchedWord.Id) {
                            $guardPrefixCount = $guardIdx
                            break
                        }
                    }
                }
            }

            if ($null -ne $guardPrefixCount -and $guardPrefixCount -gt 0) {
                $prefix = @(
                    $finalWords |
                    Select-Object -First $guardPrefixCount
                )

                $currentMatch = @(
                    $currOverlap |
                    Select-Object `
                        -Skip $match.CurrentStart `
                        -First $match.CurrentConsumed
                )

                if (
                    $prefix.Count -gt 0 -and
                    $currentMatch.Count -gt 0 -and
                    $currentMatch[0].From -lt $prefix[-1].To
                ) {
                    Write-Host "MATCH REJECTED BY TEMPORAL PLACEMENT GUARD"
                    Write-Host "Previous anchor: '$($guardMatchedWord.Text)' @ $($guardMatchedWord.From)s"
                    Write-Host "Current anchor:  '$($currentMatch[0].Text)' @ $($currentMatch[0].From)s"
                    Write-Host "Accumulated prefix boundary: $($prefix[-1].To) s"
                    $match = $null
                }
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

            foreach ($word in $prevOverlap) {
                $text = ($word.Text.ToLower()).Trim()
                if ($prevBandByText.ContainsKey($text)) {
                    $prevBandByText[$text] = @($prevBandByText[$text]) + $word
                } else {
                    $prevBandByText[$text] = @($word)
                }
            }

            foreach ($word in $currOverlap) {
                $text = ($word.Text.ToLower()).Trim()
                if ($currBandByText.ContainsKey($text)) {
                    $currBandByText[$text] = @($currBandByText[$text]) + $word
                } else {
                    $currBandByText[$text] = @($word)
                }
            }

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
                    $fromDiff = [math]::Abs($prevOccurrences[$occ].From - $currOccurrences[$occ].From)
                    $toDiff   = [math]::Abs($prevOccurrences[$occ].To   - $currOccurrences[$occ].To)

                    if (
                        $fromDiff -gt $driftAllowance -or
                        $toDiff   -gt $driftAllowance
                    ) {
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

                $text = ($newWord.Text.ToLower()).Trim()

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
                        $text `
                        $prevBandByText `
                        $currBandByText `
                        $driftAllowance
                )) {
                    return $false
                }

                for ($idx = 0; $idx -lt $existingWords.Count; $idx++) {
                    $existing = $existingWords[$idx]

                    if ($text -ne (($existing.Text.ToLower()).Trim())) {
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

                $text = ($newWord.Text.ToLower()).Trim()

                if (-not (
                    $newWord.From -lt $bandEnd -and
                    $newWord.To   -gt $bandStart
                )) {
                    return $false
                }

                if ([string]::IsNullOrEmpty($newWord.Key)) {
                    return $false
                }

                if ($prevBandByText.ContainsKey($text)) {
                    return $false
                }

                if (-not $accBandByText.ContainsKey($text)) {
                    return $false
                }

                $accOccurrences  = @($accBandByText[$text])
                $currOccurrences = @($currBandByText[$text])

                if (
                    $accOccurrences.Count -lt 1 -or
                    $currOccurrences.Count -lt 1 -or
                    $accOccurrences.Count -ne $currOccurrences.Count
                ) {
                    return $false
                }

                $accSorted  = @($accOccurrences  | Sort-Object -Property From)
                $currSorted = @($currOccurrences | Sort-Object -Property From)

                for ($k = 0; $k -lt $accSorted.Count; $k++) {
                    $fromDiff = [math]::Abs($accSorted[$k].From - $currSorted[$k].From)
                    $toDiff   = [math]::Abs($accSorted[$k].To   - $currSorted[$k].To)

                    if (
                        $fromDiff -gt $transitiveAllowance -or
                        $toDiff   -gt $transitiveAllowance
                    ) {
                        return $false
                    }
                }

                $slot = -1
                for ($k = 0; $k -lt $currSorted.Count; $k++) {
                    if ($currSorted[$k].Id -eq $newWord.Id) {
                        $slot = $k
                        break
                    }
                }

                if ($slot -lt 0) {
                    return $false
                }

                $partner = $accSorted[$slot]

                for ($idx = 0; $idx -lt $existingWords.Count; $idx++) {
                    if ($existingWords[$idx].Id -eq $partner.Id) {
                        if ($claimed.Contains($idx)) {
                            return $false
                        }

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
                        if (-not (
                            Test-TransitiveWordAlreadyExists `
                                $word `
                                $result `
                                $bandStart `
                                $bandEnd `
                                $transitiveAllowance `
                                $prevBandByText `
                                $currBandByText `
                                $accBandByText `
                                $claimed
                        )) {
                            $result += $word
                        }
                    }
                }

                return @($result)
            }

            $transitiveAllowance = [math]::Min($driftAllowance, 0.5)
            $accBandByText = @{}

            foreach ($word in $finalWords) {
                if (
                    $word.From -lt $overlapEnd -and
                    $word.To   -gt $overlapStart
                ) {
                    $text = ($word.Text.ToLower()).Trim()

                    if ($accBandByText.ContainsKey($text)) {
                        $accBandByText[$text] = @($accBandByText[$text]) + $word
                    } else {
                        $accBandByText[$text] = @($word)
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

            # SIN MATCH appends/deduplicates current words, so the surviving
            # representative may keep the previous window's ID. The next
            # transition, however, addresses the overlap using the current
            # window's IDs. Keep aliases from current overlap IDs to the
            # surviving accumulated representative, and restore chronological
            # order before the next transition.
            $finalWords = @(
                $finalWords | Sort-Object -Property From, To
            )

            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }

            $claimedAliases = New-Object 'System.Collections.Generic.HashSet[int]'

            foreach ($word in $currOverlap) {
                if ($previousOverlapMap.ContainsKey($word.Id)) {
                    continue
                }

                $text = ($word.Text.ToLower()).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    continue
                }

                $bestIndex = -1
                $bestScore = [double]::PositiveInfinity

                for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                    if ($claimedAliases.Contains($idx)) {
                        continue
                    }

                    $candidate = $finalWords[$idx]
                    if ($text -ne (($candidate.Text.ToLower()).Trim())) {
                        continue
                    }

                    $fromDiff = [math]::Abs($word.From - $candidate.From)
                    $toDiff   = [math]::Abs($word.To   - $candidate.To)

                    if ($fromDiff -le $driftAllowance -and $toDiff -le $driftAllowance) {
                        $score = $fromDiff + $toDiff
                        if ($score -lt $bestScore) {
                            $bestScore = $score
                            $bestIndex = $idx
                        }
                    }
                }

                if ($bestIndex -ge 0) {
                    $previousOverlapMap[$word.Id] = $bestIndex
                    $claimedAliases.Add($bestIndex) | Out-Null
                }
            }

            continue
        }

        $matchedWord = $prevOverlap[$match.PreviousStart]

        if ($null -eq $matchedWord) {
            Write-Host "ERROR: EL ELEMENTO DEL MATCH ES NULL"
            continue
        }

        # A match can select an anchor that was deferred by an earlier MATCH.
        # Recover it into the accumulated transcript before calculating prefix.
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
            $anchorText = ($matchedWord.Text.ToLower()).Trim()

            if ($deferredWordsByText.ContainsKey($anchorText)) {
                $candidate = $null

                foreach ($deferred in @($deferredWordsByText[$anchorText])) {
                    $sameFrom = [math]::Abs($deferred.From - $matchedWord.From) -le 0.000001
                    $sameTo   = [math]::Abs($deferred.To   - $matchedWord.To)   -le 0.000001

                    if ($sameFrom -and $sameTo) {
                        $candidate = $deferred
                        break
                    }
                }

                if ($null -ne $candidate) {
                    $insertAt = $finalWords.Count

                    for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                        if ($finalWords[$idx].From -gt $candidate.From) {
                            $insertAt = $idx
                            break
                        }
                    }

                    if ($insertAt -eq 0) {
                        $finalWords = @($candidate) + $finalWords
                    } elseif ($insertAt -eq $finalWords.Count) {
                        $finalWords = @($finalWords) + $candidate
                    } else {
                        $finalWords = @($finalWords[0..($insertAt - 1)]) + $candidate + @($finalWords[$insertAt..($finalWords.Count - 1)])
                    }

                    $prefixCount = $insertAt
                    Write-Host "RECUPERADO ANCLA DIFERIDA: '$($candidate.Text)'"

                    $remaining = @(
                        $deferredWordsByText[$anchorText] |
                        Where-Object { $_.Id -ne $candidate.Id }
                    )

                    if ($remaining.Count -eq 0) {
                        $deferredWordsByText.Remove($anchorText) | Out-Null
                    } else {
                        $deferredWordsByText[$anchorText] = $remaining
                    }
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

        $after = @()

        if ($currentLastIndexInWords + 1 -lt $currentWords.Count) {
            $after = @(
                $currentWords |
                Select-Object -Skip ($currentLastIndexInWords + 1)
            )
        }

        # Preserve words before the selected MATCH as deferred candidates.
        for ($k = 0; $k -lt $match.CurrentStart; $k++) {
            $deferred = $currOverlap[$k]
            $deferredText = ($deferred.Text.ToLower()).Trim()

            if ([string]::IsNullOrEmpty($deferred.Key)) {
                continue
            }

            if ($deferredWordsByText.ContainsKey($deferredText)) {
                $deferredWordsByText[$deferredText] = @($deferredWordsByText[$deferredText]) + $deferred
            } else {
                $deferredWordsByText[$deferredText] = @($deferred)
            }
        }

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

        $finalWords = @($newFinal)

        $previousOverlapMap = @{}
        for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
            $previousOverlapMap[$finalWords[$idx].Id] = $idx
        }
    }

    return @($finalWords)
}
