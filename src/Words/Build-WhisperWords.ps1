# ============================================================
# Build-WhisperWords
# ============================================================

function Build-WhisperWords {
    param(
        $tokens,
        [int]$WindowIndex = -1
    )

    $words = @()
    $currentText = ""
    $currentTokens = @()

    # Si el token anterior era puntuación pura,
    # el siguiente token comienza una palabra nueva.
    $forceBoundaryNext = $false
    $wordIndex = 0

    foreach ($token in $tokens) {

        $text = $token.Text
        $cleanText = $text.Trim()

        if ([string]::IsNullOrWhiteSpace($cleanText)) {
            $forceBoundaryNext = $true
            continue
        }

        # Espacio inicial = inicio normal de palabra.
        $hasLeadingSpace = $text -match '^\s'

        # Token compuesto únicamente por puntuación.
        $isPunctuationOnly = -not ($cleanText -match '[\p{L}\p{N}]')

        $startsNewWord = $hasLeadingSpace -or $forceBoundaryNext

        if ($startsNewWord -and $currentTokens.Count -gt 0) {

            $words += [PSCustomObject]@{
                Text = $currentText
                Key  = (
                    $currentText.ToLower() -replace '[^\p{L}\p{N}%]', ''
                )
                From = $currentTokens[0].From
                To   = $currentTokens[-1].To
                Tokens = @($currentTokens)
                Id   = "$WindowIndex-$wordIndex"
            }
            $wordIndex++

            $currentText = ""
            $currentTokens = @()
        }

        $currentText += $cleanText
        $currentTokens += $token

        # Esta decisión afecta al SIGUIENTE token.
        $forceBoundaryNext = $isPunctuationOnly
    }

    if ($currentTokens.Count -gt 0) {

        $words += [PSCustomObject]@{
            Text = $currentText
            Key  = (
                $currentText.ToLower() -replace '[^\p{L}\p{N}%]', ''
            )
            From = $currentTokens[0].From
            To   = $currentTokens[-1].To
            Tokens = @($currentTokens)
            Id   = "$WindowIndex-$wordIndex"
        }
        $wordIndex++
    }

    return @($words)
}
