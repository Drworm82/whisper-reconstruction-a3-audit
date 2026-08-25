$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\whisper-reconstruction.ps1"
. "$projectRoot\src\Import\Convert-WhisperX.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

$pass = $true

$windows = Convert-WhisperX -Path $fixturePath

if ($windows.Count -ne 3) {
    Write-Host "FAIL: Expected 3 windows, got $($windows.Count)"
    $pass = $false
} else {
    Write-Host "PASS: 3 windows converted"
}

$expectedTokensPerWindow = @(4, 4, 3)
for ($i = 0; $i -lt $windows.Count; $i++) {
    $window = $windows[$i]
    $tokens = $window.Tokens

    if ($tokens.Count -ne $expectedTokensPerWindow[$i]) {
        Write-Host "FAIL: Window $i expected $($expectedTokensPerWindow[$i]) tokens, got $($tokens.Count)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i has $($tokens.Count) tokens"
    }

    for ($j = 0; $j -lt $tokens.Count; $j++) {
        $token = $tokens[$j]

        if ($j -eq 0) {
            if ($token.Text -match '^\s') {
                Write-Host "FAIL: Window $i token $j should not have leading space, got '$($token.Text)'"
                $pass = $false
            } else {
                Write-Host "PASS: Window $i token $j has no leading space"
            }
        } else {
            if ($token.Text -notmatch '^\s') {
                Write-Host "FAIL: Window $i token $j should have leading space, got '$($token.Text)'"
                $pass = $false
            } else {
                Write-Host "PASS: Window $i token $j has leading space"
            }
        }

        if ($token.From -ne $token.From) {
            Write-Host "FAIL: Window $i token $j From is null"
            $pass = $false
        }
        if ($token.To -ne $token.To) {
            Write-Host "FAIL: Window $i token $j To is null"
            $pass = $false
        }
    }
}

$expectedWindows = @(
    @{ Start = 0.0; End = 5.0; TokenTexts = @("Esta", " es", " una", " prueba"); TokenFrom = @(0.2, 0.9, 1.3, 1.9); TokenTo = @(0.8, 1.2, 1.8, 2.5) },
    @{ Start = 2.0; End = 7.0; TokenTexts = @("prueba", " de", " reconstrucción", " Whisper"); TokenFrom = @(2.1, 2.8, 3.2, 4.1); TokenTo = @(2.7, 3.1, 4.0, 4.8) },
    @{ Start = 6.0; End = 10.0; TokenTexts = @("donde", " algunas", " palabras"); TokenFrom = @(6.2, 6.9, 7.6); TokenTo = @(6.8, 7.5, 8.3) }
)

for ($i = 0; $i -lt $windows.Count; $i++) {
    $window = $windows[$i]

    if ($window.Start -ne $expectedWindows[$i].Start) {
        Write-Host "FAIL: Window $i Start mismatch: expected $($expectedWindows[$i].Start), got $($window.Start)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i Start=$($window.Start)"
    }

    if ($window.End -ne $expectedWindows[$i].End) {
        Write-Host "FAIL: Window $i End mismatch: expected $($expectedWindows[$i].End), got $($window.End)"
        $pass = $false
    } else {
        Write-Host "PASS: Window $i End=$($window.End)"
    }

    for ($j = 0; $j -lt $window.Tokens.Count; $j++) {
        $token = $window.Tokens[$j]

        if ($token.Text -ne $expectedWindows[$i].TokenTexts[$j]) {
            Write-Host "FAIL: Window $i token $j Text mismatch: expected '$($expectedWindows[$i].TokenTexts[$j])', got '$($token.Text)'"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $j Text='$($token.Text)'"
        }

        if ([math]::Abs($token.From - $expectedWindows[$i].TokenFrom[$j]) -gt 0.0001) {
            Write-Host "FAIL: Window $i token $j From mismatch: expected $($expectedWindows[$i].TokenFrom[$j]), got $($token.From)"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $j From=$($token.From)"
        }

        if ([math]::Abs($token.To - $expectedWindows[$i].TokenTo[$j]) -gt 0.0001) {
            Write-Host "FAIL: Window $i token $j To mismatch: expected $($expectedWindows[$i].TokenTo[$j]), got $($token.To)"
            $pass = $false
        } else {
            Write-Host "PASS: Window $i token $j To=$($token.To)"
        }
    }
}

Write-Host ""
if ($pass) {
    Write-Host "Convert-WhisperX test PASSED"
    exit 0
} else {
    Write-Host "Convert-WhisperX test FAILED"
    exit 1
}
