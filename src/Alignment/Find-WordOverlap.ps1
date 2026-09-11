# ============================================================
# Find-WordOverlap
# ============================================================
function Find-WordOverlap {
    param($previousWords, $currentWords)

    $best = $null

    for ($i = 0; $i -lt $previousWords.Count; $i++) {
        for ($j = 0; $j -lt $currentWords.Count; $j++) {
            $pi = $i
            $cj = $j
            $matches = 0
            $exactTextMatches = 0
            $skippedPrevious = 0
            $skippedCurrent = 0

            while ($pi -lt $previousWords.Count -and $cj -lt $currentWords.Count) {
                if ($previousWords[$pi].Key -ne '' -and $currentWords[$cj].Key -ne '' -and $previousWords[$pi].Key -eq $currentWords[$cj].Key) {
                    $matches++
                    if ($previousWords[$pi].Text.Trim() -eq $currentWords[$cj].Text.Trim()) {
                        $exactTextMatches++
                    }
                    $pi++
                    $cj++
                    continue
                }

                if (($cj + 1) -lt $currentWords.Count -and $previousWords[$pi].Key -ne '' -and $currentWords[$cj + 1].Key -ne '' -and $previousWords[$pi].Key -eq $currentWords[$cj + 1].Key) {
                    $cj++
                    $skippedCurrent++
                    continue
                }

                if (($pi + 1) -lt $previousWords.Count -and $previousWords[$pi + 1].Key -ne '' -and $currentWords[$cj].Key -ne '' -and $previousWords[$pi + 1].Key -eq $currentWords[$cj].Key) {
                    $pi++
                    $skippedPrevious++
                    continue
                }

                break
            }

            if ($matches -lt 3) {
                continue
            }

            $startPrevious = $previousWords[$i].From
            $startCurrent  = $currentWords[$j].From
            $endPrevious   = $previousWords[$pi - 1].To
            $endCurrent    = $currentWords[$cj - 1].To
            $durationPrevious = $endPrevious - $startPrevious
            $durationCurrent  = $endCurrent - $startCurrent
            $durationDifference = [math]::Abs($durationPrevious - $durationCurrent)

            $candidate = [PSCustomObject]@{
                Matches = $matches
                ExactTextMatches = $exactTextMatches
                PreviousStart = $i
                CurrentStart = $j
                PreviousEnd = $pi
                CurrentEnd = $cj
                PreviousConsumed = $pi - $i
                CurrentConsumed = $cj - $j
                SkippedPrevious = $skippedPrevious
                SkippedCurrent = $skippedCurrent
                DurationDifference = $durationDifference
            }

            if ($null -eq $best) {
                $best = $candidate
                continue
            }

            if ($candidate.ExactTextMatches -gt $best.ExactTextMatches) {
                $best = $candidate
                continue
            }

            if ($candidate.ExactTextMatches -eq $best.ExactTextMatches -and $candidate.Matches -gt $best.Matches) {
                $best = $candidate
                continue
            }

            if ($candidate.ExactTextMatches -eq $best.ExactTextMatches -and $candidate.Matches -eq $best.Matches) {
                $candidateSkipped = $candidate.SkippedPrevious + $candidate.SkippedCurrent
                $bestSkipped = $best.SkippedPrevious + $best.SkippedCurrent

                if ($candidateSkipped -lt $bestSkipped) {
                    $best = $candidate
                    continue
                }

                if ($candidateSkipped -eq $bestSkipped -and $candidate.DurationDifference -lt $best.DurationDifference) {
                    $best = $candidate
                }
            }
        }
    }

    if ($null -eq $best) {
        return $null
    }

    if ($best.PreviousStart -lt 0 -or $best.PreviousStart -ge $previousWords.Count -or $best.CurrentStart -lt 0 -or $best.CurrentStart -ge $currentWords.Count) {
        return $best
    }

    # Reconstruction owns the accumulated transcript. During a production
    # call, the caller scope contains $finalWords. Validate the selected
    # anchor against the word immediately preceding that anchor. Standalone
    # Find-WordOverlap calls remain lexical-only because no $finalWords scope
    # is present.
    $callerFinalWords = Get-Variable -Name finalWords -Scope 1 -ValueOnly -ErrorAction SilentlyContinue

    if ($null -ne $callerFinalWords -and @($callerFinalWords).Count -gt 0) {
        $matchedPreviousAnchor = $previousWords[$best.PreviousStart]
        $currentAnchor = $currentWords[$best.CurrentStart]
        $matchedIndex = -1

        for ($idx = 0; $idx -lt @($callerFinalWords).Count; $idx++) {
            if (@($callerFinalWords)[$idx].Id -eq $matchedPreviousAnchor.Id) {
                $matchedIndex = $idx
                break
            }
        }

        if ($matchedIndex -gt 0) {
            $prefixBoundary = @($callerFinalWords)[$matchedIndex - 1].To

            if ([double]$currentAnchor.From -lt [double]$prefixBoundary) {
                Write-Host "MATCH REJECTED BY TEMPORAL PLACEMENT GUARD"
                Write-Host "Previous anchor: '$($matchedPreviousAnchor.Text)' @ $($matchedPreviousAnchor.From)s"
                Write-Host "Current anchor:  '$($currentAnchor.Text)' @ $($currentAnchor.From)s"
                Write-Host "Accumulated prefix boundary: $prefixBoundary s"
                return $null
            }
        }
    }

    return $best
}
