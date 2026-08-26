$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

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

    # Definición de las 10 palabras esperadas tras deduplicación de 'prueba' entre ventana 0 y 1
    $expectedReconstructedWords = @(
        @{ Text = "Esta"; From = 0.2; To = 0.8 },
        @{ Text = "es"; From = 0.9; To = 1.2 },
        @{ Text = "una"; From = 1.3; To = 1.8 },
        @{ Text = "prueba"; From = 1.9; To = 2.5 },
        @{ Text = "de"; From = 2.8; To = 3.1 },
        @{ Text = "reconstrucción"; From = 3.2; To = 4.0 },
        @{ Text = "Whisper"; From = 4.1; To = 4.8 },
        @{ Text = "donde"; From = 6.2; To = 6.8 },
        @{ Text = "algunas"; From = 6.9; To = 7.5 },
        @{ Text = "palabras"; From = 7.6; To = 8.3 }
    )

    if ($wordsArray.Count -ne $expectedReconstructedWords.Count) {
        Write-Host "FAIL: Word count mismatch: expected $($expectedReconstructedWords.Count), got $($wordsArray.Count)"
        $pass = $false
    } else {
        Write-Host "PASS: Word count matches expected ($($expectedReconstructedWords.Count) words)"
    }

    $checkCount = [math]::Min($wordsArray.Count, $expectedReconstructedWords.Count)
    for ($i = 0; $i -lt $checkCount; $i++) {
        $actual = $wordsArray[$i]
        $expected = $expectedReconstructedWords[$i]

        $actualKey = $actual.Text.ToLower() -replace '[^\p{L}\p{N}%]', ''
        $expectedKey = $expected.Text.ToLower() -replace '[^\p{L}\p{N}%]', ''

        if ($actualKey -ne $expectedKey) {
            Write-Host "FAIL: Word $i text mismatch: expected '$($expected.Text)', got '$($actual.Text)'"
            $pass = $false
        } else {
            Write-Host "PASS: Word $i = '$($actual.Text)'"
        }

        if ([math]::Abs($actual.From - $expected.From) -gt 0.0001) {
            Write-Host "FAIL: Word $i From mismatch: expected $($expected.From), got $($actual.From)"
            $pass = $false
        } else {
            Write-Host "PASS: Word $i From=$($actual.From)"
        }

        if ([math]::Abs($actual.To - $expected.To) -gt 0.0001) {
            Write-Host "FAIL: Word $i To mismatch: expected $($expected.To), got $($actual.To)"
            $pass = $false
        } else {
            Write-Host "PASS: Word $i To=$($actual.To)"
        }
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
