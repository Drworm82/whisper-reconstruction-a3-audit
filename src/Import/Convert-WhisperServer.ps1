function Convert-WhisperServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "whisper-server JSON file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "whisper-server JSON file is empty: $Path"
    }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw "Invalid whisper-server JSON: $($_.Exception.Message)"
    }

    if ($null -eq $data.segments) {
        throw "whisper-server JSON does not contain 'segments'."
    }

    $tokens = @()
    $windowStart = $null
    $windowEnd = $null

    foreach ($segment in @($data.segments)) {
        if ($null -eq $segment.words) {
            throw "whisper-server segment does not contain 'words'."
        }

        $segmentStart = [double]$segment.start
        $segmentEnd   = [double]$segment.end

        if ([double]::IsNaN($segmentStart) -or [double]::IsNaN($segmentEnd) -or
            [double]::IsInfinity($segmentStart) -or [double]::IsInfinity($segmentEnd)) {
            throw "Non-finite whisper-server segment timing."
        }

        if ($segmentStart -lt 0 -or $segmentEnd -lt 0) {
            throw "Negative whisper-server segment timing."
        }

        if ($segmentEnd -lt $segmentStart) {
            throw "Inverted whisper-server segment timing: $segmentStart > $segmentEnd."
        }

        if ($null -eq $windowStart) {
            $windowStart = $segmentStart
        }

        $windowEnd = $segmentEnd

        foreach ($word in @($segment.words)) {
            if ($null -eq $word.word -or $null -eq $word.start -or $null -eq $word.end) {
                throw "whisper-server word entry must contain 'word', 'start', and 'end'."
            }

            $text = [string]$word.word
            if ([string]::IsNullOrWhiteSpace($text)) {
                continue
            }

            try {
                $from = [double]$word.start
                $to   = [double]$word.end
            }
            catch {
                throw "Invalid whisper-server word timing for '$text'."
            }

            if ([double]::IsNaN($from) -or [double]::IsNaN($to) -or
                [double]::IsInfinity($from) -or [double]::IsInfinity($to)) {
                throw "Non-finite whisper-server word timing for '$text'."
            }

            if ($from -lt 0 -or $to -lt 0) {
                throw "Negative whisper-server word timing for '$text'."
            }

            if ($to -lt $from) {
                throw "Inverted whisper-server word timing for '$text': $from > $to."
            }

            $tokens += [PSCustomObject]@{
                Text = $text
                From = $from
                To   = $to
            }
        }
    }

    if ($tokens.Count -eq 0) {
        throw "whisper-server JSON contains no usable word units."
    }

    return [PSCustomObject]@{
        Start  = $windowStart
        End    = $windowEnd
        Tokens = $tokens
    }
}
