# ============================================================
# Find-WordOverlap
# ============================================================

function Find-WordOverlap {
    param(
        $previousWords,
        $currentWords
    )

    $best = $null

    for ($i = 0; $i -lt $previousWords.Count; $i++) {

        for ($j = 0; $j -lt $currentWords.Count; $j++) {

            $pi = $i
            $cj = $j

            $matches = 0
            $skippedPrevious = 0
            $skippedCurrent = 0

            while (
                $pi -lt $previousWords.Count -and
                $cj -lt $currentWords.Count
            ) {

                if (
                    $previousWords[$pi].Key -eq
                    $currentWords[$cj].Key
                ) {

                    $matches++
                    $pi++
                    $cj++

                    continue
                }

                # ------------------------------------------------
                # CURRENT tiene una palabra extra
                # ------------------------------------------------

                if (
                    ($cj + 1) -lt $currentWords.Count -and
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
                    $previousWords[$pi + 1].Key -eq
                    $currentWords[$cj].Key
                ) {

                    $pi++
                    $skippedPrevious++

                    continue
                }

                break
            }

            # Umbral mínimo real: 5 coincidencias.
            if ($matches -lt 5) {
                continue
            }

            # ----------------------------------------------------
            # Métricas del candidato
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

            $previousConsumed = $pi - $i
            $currentConsumed  = $cj - $j

            # ¿El tramo coincidente llega hasta el final
            # del overlap recibido?
            $reachesPreviousEnd =
                ($pi -ge $previousWords.Count)

            $reachesCurrentEnd =
                ($cj -ge $currentWords.Count)

            $candidate = [PSCustomObject]@{

                Matches = $matches

                PreviousStart = $i
                CurrentStart  = $j

                PreviousEnd = $pi
                CurrentEnd  = $cj

                PreviousConsumed =
                    $previousConsumed

                CurrentConsumed =
                    $currentConsumed

                SkippedPrevious =
                    $skippedPrevious

                SkippedCurrent =
                    $skippedCurrent

                ReachesPreviousEnd =
                    $reachesPreviousEnd

                ReachesCurrentEnd =
                    $reachesCurrentEnd

                ReachesBothEnds =
                    (
                        $reachesPreviousEnd -and
                        $reachesCurrentEnd
                    )

                DurationDifference =
                    $durationDifference
            }

            # ----------------------------------------------------
            # CRITERIO DE SELECCION
            #
            # 1. Más matches
            # 2. Menos palabras saltadas
            # 3. Menor diferencia temporal
            #
            # NOTA:
            # No hacemos todavía que ReachesBothEnds domine
            # la selección. Primero queremos observar el
            # comportamiento real con esta métrica disponible.
            # ----------------------------------------------------

            if ($null -eq $best) {

                $best = $candidate

                continue
            }

            if (
                $candidate.Matches -gt
                $best.Matches
            ) {

                $best = $candidate

                continue
            }

            if (
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
