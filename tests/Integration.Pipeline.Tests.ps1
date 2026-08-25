$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\whisper-reconstruction.ps1"
. "$projectRoot\src\Pipeline\Invoke-WhisperReconstruction.ps1"

$fixturePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'fixtures\whisperx-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Error "Fixture not found: $fixturePath"
    exit 1
}

$pass = $true

Write-Host "=== Pipeline Integration Test ==="
Write-Host "Input: $fixturePath"
Write-Host "WindowDurationSeconds: 10"
Write-Host "OverlapDurationSeconds: 4"
Write-Host ""

try {
    $result = Invoke-WhisperReconstruction -WhisperXPath $fixturePath `
                                           -WindowDurationSeconds 10 `
                                           -OverlapDurationSeconds 4
    Write-Host "PASS: Pipeline completed without exception"
} catch {
    Write-Host "FAIL: Pipeline threw exception: $_"
    $pass = $false
    exit 1
}

$wordsArray = @($result)
if ($wordsArray.Count -gt 0) {
    Write-Host "PASS: Result contains $($wordsArray.Count) words"
} else {
    Write-Host "FAIL: Result is empty"
    $pass = $false
}

Write-Host ""
if ($pass) {
    Write-Host "Pipeline integration test PASSED"
    exit 0
} else {
    Write-Host "Pipeline integration test FAILED"
    exit 1
}
