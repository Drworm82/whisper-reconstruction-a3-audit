# ============================================================
# New-WhisperWindows
# ============================================================

function New-WhisperWindows {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Words,

        [Parameter(Mandatory = $true)]
        [double]$WindowDurationSeconds,

        [Parameter(Mandatory = $true)]
        [double]$OverlapDurationSeconds
    )

    if ($null -eq $Words -or $Words.Count -eq 0) {
        throw "Words array is empty or null."
    }

    if ($WindowDurationSeconds -le 0) {
        throw "WindowDurationSeconds must be greater than 0."
    }

    if ($OverlapDurationSeconds -lt 0) {
        throw "OverlapDurationSeconds must be greater than or equal to 0."
    }

    if ($OverlapDurationSeconds -ge $WindowDurationSeconds) {
        throw "OverlapDurationSeconds must be less than WindowDurationSeconds."
    }

    $step = $WindowDurationSeconds - $OverlapDurationSeconds

    $minFrom = $Words[0].From
    $maxTo = $Words[0].To
    foreach ($word in $Words) {
        if ($word.From -lt $minFrom) {
            $minFrom = $word.From
        }
        if ($word.To -gt $maxTo) {
            $maxTo = $word.To
        }
    }

    $windows = @()
    $windowStart = $minFrom
    $assigned = @{}

    while ($windowStart -lt $maxTo) {
        $windowEnd = $windowStart + $WindowDurationSeconds

        $windowWords = @()
        for ($w = 0; $w -lt $Words.Count; $w++) {
            $word = $Words[$w]
            if ($word.From -ge $windowStart -and $word.To -le $windowEnd) {
                $windowWords += $word
                $assigned[$w] = $true
            }
        }

        if ($windowWords.Count -gt 0) {
            $tokens = @()
            $first = $true
            foreach ($word in $windowWords) {
                if ($first) {
                    $tokenText = $word.Text
                    $first = $false
                } else {
                    $tokenText = " " + $word.Text
                }
                $tokens += [PSCustomObject]@{
                    Text = $tokenText
                    From = $word.From
                    To   = $word.To
                }
            }

            $windows += [PSCustomObject]@{
                Start  = $windowStart
                End    = $windowEnd
                Tokens = @($tokens)
                Words  = @($windowWords)
            }
        }

        $windowStart += $step
    }

    # ============================================================
    # PASADA DE RESCATE
    #
    # Solo para palabras que No entraron en NINGUNA ventana por
    # contencion estricta (duracion larga que cae en el hueco de
    # la cuadricula). Se asignan a la UNA ventana de la cuadricula
    # con mayor solapamiento temporal real; en caso de empate, a la
    # que empieza antes. El rescate nunca duplica una palabra entre
    # ventanas.
    # ============================================================

    $gridStarts = @()
    $gridStart = $minFrom
    while ($gridStart -lt $maxTo) {
        $gridStarts += $gridStart
        $gridStart += $step
    }

    for ($w = 0; $w -lt $Words.Count; $w++) {
        if ($assigned.ContainsKey($w)) {
            continue
        }

        $word = $Words[$w]

        $bestStart = $null
        $bestOverlap = 0

        foreach ($candidateStart in $gridStarts) {
            $candidateEnd = $candidateStart + $WindowDurationSeconds
            $overlap = (
                [math]::Min($candidateEnd, $word.To) -
                [math]::Max($candidateStart, $word.From)
            )

            if ($overlap -gt 0) {
                if ($null -eq $bestStart -or $overlap -gt $bestOverlap) {
                    $bestStart = $candidateStart
                    $bestOverlap = $overlap
                }
            }
        }

        if ($null -eq $bestStart) {
            continue
        }

        $targetWindow = $null
        foreach ($window in $windows) {
            if ($window.Start -eq $bestStart) {
                $targetWindow = $window
                break
            }
        }

        if ($null -eq $targetWindow) {
            $targetWindow = [PSCustomObject]@{
                Start  = $bestStart
                End    = $bestStart + $WindowDurationSeconds
                Words  = @()
                Tokens = @()
            }
            $windows += $targetWindow
        }

        $targetWindow.Words = @($targetWindow.Words + $word) | Sort-Object -Property From

        $rescuedTokens = @()
        $firstRescued = $true
        foreach ($rescuedWord in $targetWindow.Words) {
            if ($firstRescued) {
                $tokenText = $rescuedWord.Text
                $firstRescued = $false
            } else {
                $tokenText = " " + $rescuedWord.Text
            }
            $rescuedTokens += [PSCustomObject]@{
                Text = $tokenText
                From = $rescuedWord.From
                To   = $rescuedWord.To
            }
        }
        $targetWindow.Tokens = @($rescuedTokens)
    }

    $windows = @($windows | Sort-Object -Property Start)

    return @($windows)
}
