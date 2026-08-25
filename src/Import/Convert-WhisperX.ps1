# ============================================================
# Convert-WhisperX
# ============================================================

function Convert-WhisperX {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "WhisperX JSON not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "WhisperX JSON is empty: $Path"
    }

    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) {
        throw "WhisperX JSON is invalid: $Path"
    }

    if (-not ($data.PSObject.Properties.Match("Segments").Count)) {
        throw "Invalid WhisperX JSON: missing 'segments'."
    }

    if ($null -eq $data.Segments -or $data.Segments.Count -eq 0) {
        throw "Invalid WhisperX JSON: 'segments' is empty."
    }

    $windows = @()

    foreach ($segment in $data.Segments) {

        if (-not ($segment.PSObject.Properties.Match("Start").Count)) {
            throw "Invalid segment: missing 'start'."
        }
        if (-not ($segment.PSObject.Properties.Match("End").Count)) {
            throw "Invalid segment: missing 'end'."
        }
        if (-not ($segment.PSObject.Properties.Match("Words").Count)) {
            throw "Invalid segment: missing 'words'."
        }

        if ($null -eq $segment.Words -or $segment.Words.Count -eq 0) {
            throw "Invalid segment: 'words' is empty."
        }

        $tokens = @()
        $first = $true

        foreach ($word in $segment.Words) {

            if (-not ($word.PSObject.Properties.Match("Word").Count)) {
                throw "Invalid word in segment: missing 'word'."
            }
            if (-not ($word.PSObject.Properties.Match("Start").Count)) {
                throw "Invalid word in segment: missing 'start'."
            }
            if (-not ($word.PSObject.Properties.Match("End").Count)) {
                throw "Invalid word in segment: missing 'end'."
            }

            $text = $word.Word
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw "Invalid word in segment: 'word' is null or whitespace."
            }

            if ($first) {
                $tokenText = $text
                $first = $false
            } else {
                $tokenText = " " + $text
            }

            $tokens += [PSCustomObject]@{
                Text = $tokenText
                From = $word.Start
                To   = $word.End
            }
        }

        $windows += [PSCustomObject]@{
            Start  = $segment.Start
            End    = $segment.End
            Tokens = @($tokens)
        }
    }

    return @($windows)
}
