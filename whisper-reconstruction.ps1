# ============================================================
# whisper-reconstruction
# Entry point
# ============================================================

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load core modules
. "$scriptRoot\src\Words\Build-WhisperWords.ps1"
. "$scriptRoot\src\Alignment\Find-WordOverlap.ps1"
. "$scriptRoot\src\Reconstruction\Reconstruct-WhisperWindows.ps1"

# Load supporting modules (currently placeholders)
. "$scriptRoot\src\Models\Word.ps1"
. "$scriptRoot\src\Diagnostics\ReconstructionDiagnostics.ps1"
. "$scriptRoot\src\Common\Helpers.ps1"

Write-Host "Whisper reconstruction modules loaded."
Write-Host "Available functions: Build-WhisperWords, Find-WordOverlap, Reconstruct-WhisperWindows"
