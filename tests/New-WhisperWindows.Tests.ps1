$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\whisper-reconstruction.ps1"
. "$projectRoot\src\Windowing\New-WhisperWindows.ps1"

$pass = $true

$words = @()
$wordData = @(
    @{ Text = "Esta"; From = 0.0; To = 0.5 },
    @{ Text = "es"; From = 0.6; To = 1.0 },
    @{ Text = "una"; From = 1.1; To = 1.5 },
    @{ Text = "prueba"; From = 1.6; To = 2.2 },
    @{ Text = "de"; From = 2.3; To = 2.6 },
    @{ Text = "reconstrucción"; From = 2.7; To = 3.5 },
    @{ Text = "de"; From = 3.6; To = 3.9 },
    @{ Text = "Whisper"; From = 4.0; To = 4.8 },
    @{ Text = "donde"; From = 5.0; To = 5.6 },
    @{ Text = "algunas"; From = 5.7; To = 6.4 },
    @{ Text = "palabras"; From = 6.5; To = 7.2 },
    @{ Text = "aparecen"; From = 7.3; To = 8.0 },
    @{ Text = "repetidas"; From = 8.1; To = 8.8 },
    @{ Text = "entre"; From = 8.9; To = 9.4 },
    @{ Text = "ventanas"; From = 9.5; To = 10.2 }
)

foreach ($w in $wordData) {
    $words += [PSCustomObject]@{
        Text = $w.Text
        From = $w.From
        To   = $w.To
    }
}

Write-Host "=== New-WhisperWindows test ==="
Write-Host "Input words: $($words.Count)"
Write-Host "WindowDurationSeconds: 10"
Write-Host "OverlapDurationSeconds: 4"
Write-Host ""

try {
    $windows = New-WhisperWindows -Words $words -WindowDurationSeconds 10 -OverlapDurationSeconds 4
    Write-Host "PASS: New-WhisperWindows executed without error"
} catch {
    Write-Host "FAIL: New-WhisperWindows threw: $_"
    $pass = $false
    exit 1
}

if ($windows.Count -ne 2) {
    Write-Host "FAIL: Expected 2 windows, got $($windows.Count)"
    $pass = $false
} else {
    Write-Host "PASS: 2 windows generated"
}

$expectedWindows = @(
    @{ Start = 0.0; End = 10.0; WordIndices = @(0,1,2,3,4,5,6,7,8,9,10,11,12,13) },
    @{ Start = 6.0; End = 16.0; WordIndices = @(10,11,12,13,14) }
)

for ($i = 0; $i -lt $windows.Count; $i++) {
    $window = $windows[$i]
    $expected = $expectedWindows[$i]

    if ([math]::Abs($window.Start - $expected.Start) -gt 0.0001) {
        Write-Host "FAIL: Window $i Start: expected $($expected.Start), got $($window.Start)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i Start=$($window.Start)"
    }

    if ([math]::Abs($window.End - $expected.End) -gt 0.0001) {
        Write-Host "FAIL: Window $i End: expected $($expected.End), got $($window.End)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i End=$($window.End)"
    }

    if ($window.Tokens.Count -ne $expected.WordIndices.Count) {
        Write-Host "FAIL: Window $i token count: expected $($expected.WordIndices.Count), got $($window.Tokens.Count)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i has $($window.Tokens.Count) tokens"
    }

    for ($t = 0; $t -lt $window.Tokens.Count; $t++) {
        $token = $window.Tokens[$t]
        $wordIndex = $expected.WordIndices[$t]
        $expectedWord = $wordData[$wordIndex]

        $expectedText = if ($t -eq 0) { $expectedWord.Text } else { " " + $expectedWord.Text }
        if ($token.Text -ne $expectedText) {
            Write-Host "FAIL: Window $i token $t Text: expected '$expectedText', got '$($token.Text)'"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $t Text='$($token.Text)'"
        }

        if ([math]::Abs($token.From - $expectedWord.From) -gt 0.0001) {
            Write-Host "FAIL: Window $i token $t From: expected $($expectedWord.From), got $($token.From)"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $t From=$($token.From)"
        }

        if ([math]::Abs($token.To - $expectedWord.To) -gt 0.0001) {
            Write-Host "FAIL: Window $i token $t To: expected $($expectedWord.To), got $($token.To)"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $t To=$($token.To)"
        }
    }
}

$overlapWordsW0 = @()
$overlapWordsW1 = @()
for ($t = 0; $t -lt $windows[0].Tokens.Count; $t++) {
    $token = $windows[0].Tokens[$t]
    $wordText = $token.Text.Trim()
    if ($wordText -match '^[\p{L}\p{N}]') {
        $overlapWordsW0 += $wordText
    }
}
for ($t = 0; $t -lt $windows[1].Tokens.Count; $t++) {
    $token = $windows[1].Tokens[$t]
    $wordText = $token.Text.Trim()
    if ($wordText -match '^[\p{L}\p{N}]') {
        $overlapWordsW1 += $wordText
    }
}

$overlapW0 = $overlapWordsW0 | Where-Object { $_ -in $overlapWordsW1 }
if ($overlapW0.Count -ge 3) {
    Write-Host "PASS: Overlap between window 0 and 1 contains $($overlapW0.Count) shared words"
} else {
    Write-Host "FAIL: Overlap between window 0 and 1 contains only $($overlapW0.Count) shared words (expected >= 3)"
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "New-WhisperWindows test PASSED"
    exit 0
} else {
    Write-Host "New-WhisperWindows test FAILED"
    exit 1
}
