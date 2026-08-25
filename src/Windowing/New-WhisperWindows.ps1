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

    while ($windowStart -lt $maxTo) {
        $windowEnd = $windowStart + $WindowDurationSeconds

        $windowWords = @()
        foreach ($word in $Words) {
            if ($word.From -ge $windowStart -and $word.To -le $windowEnd) {
                $windowWords += $word
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
            }
        }

        $windowStart += $step
    }

    return @($windows)
}
