# ============================================================
# Test script demonstrating Load-WhisperReconstruction functionality
# ============================================================

$ErrorActionPreference = 'Stop'

# Determine project root relative to this test script location
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $scriptRoot
$loaderPath = Join-Path $scriptRoot 'src\Load-WhisperReconstruction.ps1'

Write-Host "=== Testing Load-WhisperReconstruction.ps1 ==="
Write-Host "Script root: $scriptRoot"
Write-Host "Project root: $projectRoot"
Write-Host "Loader path: $loaderPath"

if (-not (Test-Path -LiteralPath $loaderPath)) {
    Write-Host "ERROR: Loader not found at $loaderPath"
    exit 1
}

# Test 1: Load the loader
Write-Host "`n1. Loading Load-WhisperReconstruction.ps1..."
try {
    . $loaderPath
    Write-Host "   OK: Loader loaded successfully"
}
catch {
    Write-Host "   ERROR: Loader failed to load: $_"
    exit 1
}

# Test 2: Verify expected functions exist
Write-Host "`n2. Verifying loaded functions..."
$functions = @(
    'Build-WhisperWords'
    'Find-WordOverlap'
    'Reconstruct-WhisperWindows'
    'Convert-WhisperX'
    'New-WhisperWindows'
    'Invoke-WhisperReconstruction'
)

$missing = @()
foreach ($func in $functions) {
    if (Get-Command -Name $func -ErrorAction SilentlyContinue) {
        Write-Host "   OK: $func is available"
    }
    else {
        Write-Host "   MISSING: $func is NOT available"
        $missing += $func
    }
}

if ($missing.Count -gt 0) {
    Write-Host "ERROR: Missing functions: $($missing -join ', ')"
    exit 1
}

# Test 3: Run Invoke-WhisperReconstruction against the long fixture
Write-Host "`n3. Running Invoke-WhisperReconstruction..."
$fixturePath = Join-Path $projectRoot 'tests\fixtures\whisperx-long-test.json'

if (-not (Test-Path -LiteralPath $fixturePath)) {
    Write-Host "   ERROR: Fixture not found at $fixturePath"
    exit 1
}

Write-Host "   Fixture: $fixturePath"
Write-Host "   WindowDurationSeconds: 10"
Write-Host "   OverlapDurationSeconds: 4"

try {
    $result = Invoke-WhisperReconstruction `
        -WhisperXPath $fixturePath `
        -WindowDurationSeconds 10 `
        -OverlapDurationSeconds 4
}
catch {
    Write-Host "   ERROR: Invoke-WhisperReconstruction threw: $_"
    exit 1
}

if ($null -eq $result) {
    Write-Host "   ERROR: Reconstruction returned null"
    exit 1
}

Write-Host "   OK: Reconstruction completed"
Write-Host "   OK: Result contains $($result.Count) word(s)"

if ($result.Count -eq 0) {
    Write-Host "   ERROR: Expected at least one word"
    exit 1
}

Write-Host "`n=== Test Summary ==="
Write-Host "OK: Load-WhisperReconstruction.ps1 loaded all required modules"
Write-Host "OK: All expected functions are available"
Write-Host "OK: Invoke-WhisperReconstruction executed successfully"
Write-Host "OK: Result contains $($result.Count) word(s)"
Write-Host "`nLoader test PASSED"
exit 0
