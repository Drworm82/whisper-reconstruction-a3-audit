# ============================================================
# Find-WordOverlap-MatchGuard
# ============================================================
# Experimental guard for controlled reconstruction validation.
# It preserves the existing Find-WordOverlap implementation and
# rejects only candidates whose selected current anchor is earlier
# than the selected previous anchor in global time.
#
# The rejection returns $null so Reconstruct-WhisperWindows enters
# its existing SIN MATCH path instead of replacing an accumulated
# prefix with a sequence that would move backwards in time.

if (-not (Get-Command Find-WordOverlap -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Find-WordOverlap must be loaded before Find-WordOverlap-MatchGuard.ps1."
}

$OriginalFindWordOverlap = (Get-Command Find-WordOverlap -CommandType Function).ScriptBlock

function Find-WordOverlap {
    param($previousWords, $currentWords)

    $candidate = & $OriginalFindWordOverlap $previousWords $currentWords

    if ($null -eq $candidate) {
        return $null
    }

    if (
        $candidate.PreviousStart -lt 0 -or
        $candidate.PreviousStart -ge $previousWords.Count -or
        $candidate.CurrentStart -lt 0 -or
        $candidate.CurrentStart -ge $currentWords.Count
    ) {
        return $candidate
    }

    $previousAnchor = $previousWords[$candidate.PreviousStart]
    $currentAnchor  = $currentWords[$candidate.CurrentStart]

    if ([double]$currentAnchor.From -lt [double]$previousAnchor.From) {
        Write-Host "MATCH REJECTED BY TEMPORAL PLACEMENT GUARD"
        Write-Host "Previous anchor: '$($previousAnchor.Text)' @ $($previousAnchor.From)s"
        Write-Host "Current anchor:  '$($currentAnchor.Text)' @ $($currentAnchor.From)s"
        return $null
    }

    return $candidate
}
