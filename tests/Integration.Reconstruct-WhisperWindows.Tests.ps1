$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\whisper-reconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\windows-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

$windows = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json

$pass = $true

if ($windows.Count -ne 4) {
    Write-Host "FAIL: Expected 4 windows, got $($windows.Count)"
    $pass = $false
} else {
    Write-Host "PASS: 4 windows processed"
}

$transcriptPath = Join-Path $env:TEMP ("whisper-transcript-" + [Guid]::NewGuid().ToString() + ".txt")
Start-Transcript -Path $transcriptPath | Out-Null

$result = Reconstruct-WhisperWindows $windows

Stop-Transcript | Out-Null

$diagnostics = Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue

$transitionCount = @($diagnostics | Where-Object { $_ -match '^TRANSICION' }).Count
if ($transitionCount -ne 3) {
    Write-Host "FAIL: Expected 3 transitions, got $transitionCount"
    $pass = $false
} else {
    Write-Host "PASS: 3 transitions evaluated"
}

$sinMatchCount = @($diagnostics | Where-Object { $_ -match 'SIN MATCH' }).Count
$matchCount = $transitionCount - $sinMatchCount

if ($matchCount -ne 3) {
    Write-Host "FAIL: Expected 3 MATCH transitions, got $matchCount"
    $pass = $false
} else {
    Write-Host "PASS: 3 MATCH transitions"
}

if ($sinMatchCount -ne 0) {
    Write-Host "FAIL: Expected 0 SIN MATCH transitions, got $sinMatchCount"
    $pass = $false
} else {
    Write-Host "PASS: 0 SIN MATCH transitions"
}

$wordsArray = @($result)
if ($wordsArray.Count -ne 21) {
    Write-Host "FAIL: Expected 21 words, got $($wordsArray.Count)"
    $pass = $false
} else {
    Write-Host "PASS: 21 words reconstructed"
}

$expectedText = 'Esta es una prueba de reconstrucción de Whisper donde algunas palabras aparecen repetidas entre ventanas y esta es la prueba final'
$actualText = ($wordsArray | ForEach-Object { $_.Text }) -join ' '

if ($actualText -ne $expectedText) {
    Write-Host "FAIL: Text mismatch"
    Write-Host "Expected: $expectedText"
    Write-Host "Actual:   $actualText"
    $pass = $false
} else {
    Write-Host "PASS: Reconstructed text matches expected"
}

Write-Host ""
if ($pass) {
    Write-Host "Integration test PASSED"
    exit 0
} else {
    Write-Host "Integration test FAILED"
    exit 1
}
