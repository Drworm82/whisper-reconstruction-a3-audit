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

            while (
                $pi -lt $previousWords.Count -and
                $cj -lt $currentWords.Count
            ) {

                if (
                    $previousWords[$pi].Key -ne '' -and
                    $currentWords[$cj].Key -ne '' -and
                    $previousWords[$pi].Key -eq
                    $currentWords[$cj].Key
                ) {

                    $matches++

                    if (
                        $previousWords[$pi].Text.Trim() -eq
                        $currentWords[$cj].Text.Trim()
                    ) {
                        $exactTextMatches++
                    }

                    $pi++
                    $cj++

                    continue
                }

                # ------------------------------------------------
                # CURRENT tiene una palabra extra
                # ------------------------------------------------

                if (
                    ($cj + 1) -lt $currentWords.Count -and
                    $previousWords[$pi].Key -ne '' -and
                    $currentWords[$cj + 1].Key -ne '' -and
                    $previousWords[$pi].Key -eq
                    $currentWords[$cj + 1].Key
                ) {

                    $cj++
                    $skippedCurrent++

                    continue
                }

                # ------------------------------------------------
                # PREVIOUS tiene una palabra extra
                # ------------------------------------------------

                if (
                    ($pi + 1) -lt $previousWords.Count -and
                    $previousWords[$pi + 1].Key -ne '' -and
                    $currentWords[$cj].Key -ne '' -and
                    $previousWords[$pi + 1].Key -eq
                    $currentWords[$cj].Key
                ) {

                    $pi++
                    $skippedPrevious++

                    continue
                }

                break
            }

            if ($matches -lt 3) {
                continue
            }

            # ----------------------------------------------------
            # Medir la calidad temporal del match
            # ----------------------------------------------------

            $startPrevious = $previousWords[$i].From
            $startCurrent  = $currentWords[$j].From

            $endPrevious =
                $previousWords[$pi - 1].To

            $endCurrent =
                $currentWords[$cj - 1].To

            $durationPrevious =
                $endPrevious - $startPrevious

            $durationCurrent =
                $endCurrent - $startCurrent

            $durationDifference =
                [math]::Abs(
                    $durationPrevious -
                    $durationCurrent
                )

            $candidate = [PSCustomObject]@{

                Matches = $matches

                ExactTextMatches =
                    $exactTextMatches

                PreviousStart = $i
                CurrentStart  = $j

                PreviousEnd = $pi
                CurrentEnd  = $cj

                PreviousConsumed =
                    $pi - $i

                CurrentConsumed =
                    $cj - $j

                SkippedPrevious =
                    $skippedPrevious

                SkippedCurrent =
                    $skippedCurrent

                DurationDifference =
                    $durationDifference
            }

            # ----------------------------------------------------
            # CRITERIO DE SELECCION
            #
            # 1. Más matches con texto idéntico (identidad del bloque)
            # 2. Más matches (coincidencia de Keys)
            # 3. Menos palabras saltadas
            # 4. Menor diferencia temporal
            # ----------------------------------------------------

            if ($null -eq $best) {

                $best = $candidate

                continue
            }

            if (
                $candidate.ExactTextMatches -gt
                $best.ExactTextMatches
            ) {

                $best = $candidate

                continue
            }

            if (
                $candidate.ExactTextMatches -eq
                $best.ExactTextMatches -and
                $candidate.Matches -gt
                $best.Matches
            ) {

                $best = $candidate

                continue
            }

            if (
                $candidate.ExactTextMatches -eq
                $best.ExactTextMatches -and
                $candidate.Matches -eq
                $best.Matches
            ) {

                $candidateSkipped =
                    $candidate.SkippedPrevious +
                    $candidate.SkippedCurrent

                $bestSkipped =
                    $best.SkippedPrevious +
                    $best.SkippedCurrent

                if (
                    $candidateSkipped -lt
                    $bestSkipped
                ) {

                    $best = $candidate

                    continue
                }

                if (
                    $candidateSkipped -eq
                    $bestSkipped -and
                    $candidate.DurationDifference -lt
                    $best.DurationDifference
                ) {

                    $best = $candidate
                }
            }
        }
    }

    return $best
}
