$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\whisper-reconstruction.ps1"
. "$projectRoot\src\Import\Convert-WhisperX.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

$pass = $true

# Paso 1: Convertir WhisperX a formato interno
Write-Host "=== Paso 1: Convert-WhisperX ==="
try {
    $windows = Convert-WhisperX -Path $fixturePath
    Write-Host "PASS: Convert-WhisperX ejecutado sin error"
} catch {
    Write-Host "FAIL: Convert-WhisperX lanzó excepción: $_"
    $pass = $false
    exit 1
}

if ($windows.Count -ne 3) {
    Write-Host "FAIL: Expected 3 windows, got $($windows.Count)"
    $pass = $false
} else {
    Write-Host "PASS: 3 ventanas convertidas"
}

# Paso 2: Reconstrucción
Write-Host ""
Write-Host "=== Paso 2: Reconstruct-WhisperWindows ==="
$exceptionCaught = $false
$errorMessage = $null
$result = $null

try {
    $result = Reconstruct-WhisperWindows $windows
    Write-Host "PASS: Reconstruct-WhisperWindows ejecutado sin excepción"
} catch {
    $exceptionCaught = $true
    $errorMessage = $_.ToString()
    Write-Host "FAIL: Reconstruct-WhisperWindows lanzó excepción: $errorMessage"
    $pass = $false
}

if (-not $exceptionCaught) {
    $wordsArray = @($result)
    if ($wordsArray.Count -eq 0) {
        Write-Host "FAIL: Result is empty"
        $pass = $false
    } else {
        Write-Host "PASS: Result contains $($wordsArray.Count) words"
    }

    $expectedWords = @(
        @("Esta", "es", "una", "prueba"),
        @("prueba", "de", "reconstrucción", "Whisper"),
        @("donde", "algunas", "palabras")
    )

    $globalWordIndex = 0
    for ($w = 0; $w -lt $windows.Count; $w++) {
        $windowTokens = $windows[$w].Tokens
        for ($t = 0; $t -lt $windowTokens.Count; $t++) {
            $expectedText = $expectedWords[$w][$t]
            $actualText = $wordsArray[$globalWordIndex].Text

            if ($actualText -ne $expectedText) {
                Write-Host "FAIL: Word $globalWordIndex expected '$expectedText', got '$actualText'"
                $pass = $false
            } else {
                Write-Host "PASS: Word $globalWordIndex = '$actualText'"
            }
            $globalWordIndex++
        }
    }

    if ($globalWordIndex -ne $wordsArray.Count) {
        Write-Host "FAIL: Word count mismatch: expected $globalWordIndex, got $($wordsArray.Count)"
        $pass = $false
    }
}

Write-Host ""
if ($pass) {
    Write-Host "Integration test PASSED"
    exit 0
} else {
    Write-Host "Integration test FAILED"
    exit 1
}
