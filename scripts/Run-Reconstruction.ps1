# Run-Reconstruction.ps1
#
# Usage:
#   .\scripts\Run-Reconstruction.ps1 -WindowsPath .\data\input\windows.json
#
# Loads the whisper-reconstruction entry point and runs reconstruction
# on the provided windows data.

param(
    [Parameter(Mandatory=$true)]
    [string]$WindowsPath
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

. "$projectRoot\whisper-reconstruction.ps1"

if (-not (Test-Path -LiteralPath $WindowsPath)) {
    Write-Error "Windows file not found: $WindowsPath"
    exit 1
}

$windows = Get-Content -LiteralPath $WindowsPath -Raw | ConvertFrom-Json

Write-Host "Running reconstruction on $($windows.Count) windows..."
$result = Reconstruct-WhisperWindows $windows
Write-Host "Reconstruction complete. Words: $($result.Count)"

$outputPath = Join-Path $projectRoot "data\output\result.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Host "Result saved to: $outputPath"
