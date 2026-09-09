# ============================================================
# Load-WhisperReconstruction
# Central loader that provides deterministic loading of all pipeline dependencies
# ============================================================

# Error handling
$ErrorActionPreference = "Stop"

# Get the directory where this loader is located
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Loading Whisper reconstruction modules..."

# Load core processing modules in dependency order
# These are the essential modules that don't depend on other local modules
. "$scriptRoot\Models\Word.ps1"
. "$scriptRoot\Words\Build-WhisperWords.ps1"
. "$scriptRoot\Alignment\Find-WordOverlap.ps1"
. "$scriptRoot\Import\Convert-WhisperX.ps1"
. "$scriptRoot\Import\Convert-WhisperCpp.ps1"
. "$scriptRoot\Windowing\New-WhisperWindows.ps1"
. "$scriptRoot\Reconstruction\Reconstruct-WhisperWindows.ps1"
. "$scriptRoot\Pipeline\Invoke-WhisperReconstruction.ps1"

Write-Host "Whisper reconstruction modules loaded successfully."
Write-Host "Available functions: Build-WhisperWords, Find-WordOverlap, Reconstruct-WhisperWindows, Convert-WhisperX, Convert-WhisperCpp, New-WhisperWindows, Invoke-WhisperReconstruction"
