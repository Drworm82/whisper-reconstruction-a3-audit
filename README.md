# Whisper Reconstruction

Reconstructs Whisper transcriptions from overlapping audio windows.

## Quick Start

```powershell
. .\whisper-reconstruction.ps1
$testFinal = @(Reconstruct-WhisperWindows $cleanWindows)
```

## Project Structure

See `docs/architecture.md` for the full module layout.

## Scripts

- `scripts\Run-Reconstruction.ps1` - Run reconstruction on input data
- `scripts\Run-Diagnostics.ps1` - Run reconstruction with diagnostic output

## Requirements

- PowerShell 5.1+
- No external dependencies
