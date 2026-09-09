# ============================================================
# Convert-WhisperCpp
# ============================================================
# Adapts whisper.cpp -ojf JSON to the token/window shape expected
# by the existing reconstruction pipeline.
#
# whisper.cpp stores segment timestamps as formatted strings and
# token timestamps in milliseconds under offsets.from / offsets.to.
# The reconstruction pipeline uses seconds, matching Convert-WhisperX.
#
# Zero-duration control/timestamp tokens such as [_BEG_] and
# [_TT_nnn] are ignored. All other token text, including leading
# whitespace, is preserved because Build-WhisperWords uses leading
# whitespace to detect word boundaries.
# ============================================================

function Convert-WhisperCpp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "whisper.cpp JSON not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "whisper.cpp JSON is empty: $Path"
    }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw "whisper.cpp JSON is invalid: $Path"
    }

    if ($null -eq $data) {
        throw "whisper.cpp JSON is invalid: $Path"
    }

    if (-not ($data.PSObject.Properties.Match("transcription").Count)) {
        throw "Invalid whisper.cpp JSON: missing 'transcription'."
    }

    if ($null -eq $data.transcription -or $data.transcription.Count -eq 0) {
        throw "Invalid whisper.cpp JSON: 'transcription' is empty."
    }

    function Convert-WhisperCppTimestamp {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Value,

            [Parameter(Mandatory = $true)]
            [string]$Context
        )

        if ($Value -notmatch '^(\d+):([0-5]\d):([0-5]\d)[,\.]([0-9]{3})$') {
            throw "Invalid whisper.cpp timestamp '$Value' in $Context."
        }

        $hours = [int]$Matches[1]
        $minutes = [int]$Matches[2]
        $seconds = [int]$Matches[3]
        $milliseconds = [int]$Matches[4]

        return ($hours * 3600.0) + ($minutes * 60.0) + $seconds + ($milliseconds / 1000.0)
    }

    $windows = @()

    foreach ($segment in @($data.transcription)) {
        if (-not ($segment.PSObject.Properties.Match("timestamps").Count)) {
            throw "Invalid whisper.cpp segment: missing 'timestamps'."
        }
        if (-not ($segment.PSObject.Properties.Match("tokens").Count)) {
            throw "Invalid whisper.cpp segment: missing 'tokens'."
        }

        $segmentFrom = $segment.timestamps.from
        $segmentTo = $segment.timestamps.to

        if ($null -eq $segmentFrom -or $null -eq $segmentTo) {
            throw "Invalid whisper.cpp segment: missing timestamp values."
        }

        $startSeconds = Convert-WhisperCppTimestamp -Value ([string]$segmentFrom) -Context "segment start"
        $endSeconds = Convert-WhisperCppTimestamp -Value ([string]$segmentTo) -Context "segment end"

        if ($endSeconds -lt $startSeconds) {
            throw "Invalid whisper.cpp segment timing: end before start."
        }

        $tokens = @()

        foreach ($token in @($segment.tokens)) {
            if (-not ($token.PSObject.Properties.Match("text").Count)) {
                throw "Invalid whisper.cpp token: missing 'text'."
            }
            if (-not ($token.PSObject.Properties.Match("offsets").Count)) {
                throw "Invalid whisper.cpp token: missing 'offsets'."
            }
            if ($null -eq $token.offsets.from -or $null -eq $token.offsets.to) {
                throw "Invalid whisper.cpp token: missing offset values."
            }

            $text = [string]$token.text
            $trimmed = $text.Trim()

            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            # whisper.cpp emits control/timestamp tokens such as
            # [_BEG_] and [_TT_280]. They carry no lexical content.
            if ($trimmed -match '^\[_.*\]$') {
                continue
            }

            $fromMs = [int]$token.offsets.from
            $toMs = [int]$token.offsets.to

            if ($toMs -lt $fromMs) {
                throw "Invalid whisper.cpp token timing: '$text' has end before start."
            }

            $tokens += [PSCustomObject]@{
                Text = $text
                From = $fromMs / 1000.0
                To   = $toMs / 1000.0
            }
        }

        if ($tokens.Count -eq 0) {
            continue
        }

        $windows += [PSCustomObject]@{
            Start  = $startSeconds
            End    = $endSeconds
            Tokens = @($tokens)
        }
    }

    if ($windows.Count -eq 0) {
        throw "Invalid whisper.cpp JSON: no lexical tokens found."
    }

    return @($windows)
}
