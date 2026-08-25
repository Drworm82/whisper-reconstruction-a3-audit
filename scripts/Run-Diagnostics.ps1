# Run-Diagnostics.ps1
#
# Usage:
#   .\scripts\Run-Diagnostics.ps1 -WindowsPath .\data\input\windows.json
#
# Loads the whisper-reconstruction entry point and runs reconstruction
# with full diagnostic output enabled.

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

Write-Host "Running diagnostics on $($windows.Count) windows..."
$result = Reconstruct-WhisperWindows $windows
Write-Host "Diagnostics complete. Words: $($result.Count)"
