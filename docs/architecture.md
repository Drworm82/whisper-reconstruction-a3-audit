# Architecture

## Overview

This project reconstructs Whisper transcriptions from overlapping audio windows. The architecture follows a modular structure with clear separation of concerns.

## Directory Structure

```
whisper-reconstruction/
├── src/
│   ├── Words/
│   │   └── Build-WhisperWords.ps1      # Token-to-word grouping
│   ├── Alignment/
│   │   └── Find-WordOverlap.ps1        # Overlap search between windows
│   ├── Reconstruction/
│   │   └── Reconstruct-WhisperWindows.ps1  # Main reconstruction pipeline
│   ├── Models/
│   │   └── Word.ps1                    # Word model documentation
│   ├── Diagnostics/
│   │   └── ReconstructionDiagnostics.ps1  # Diagnostic placeholders
│   └── Common/
│       └── Helpers.ps1                 # Shared helper placeholders
├── tests/                              # Test suite
├── fixtures/                           # Test fixtures
├── data/
│   ├── input/                          # Input window data
│   └── output/                         # Reconstruction results
├── scripts/
│   ├── Run-Reconstruction.ps1          # Execution wrapper
│   └── Run-Diagnostics.ps1             # Diagnostics wrapper
├── docs/
│   └── architecture.md                 # This file
├── whisper-reconstruction.ps1          # Entry point
└── README.md                           # Project readme
```

## Data Flow

1. **Input**: Array of window objects, each containing `Start`, `End`, and `Tokens`.
2. **Words**: `Build-WhisperWords` groups tokens into word objects with timing.
3. **Alignment**: `Find-WordOverlap` finds the best overlapping word sequence between consecutive windows.
4. **Reconstruction**: `Reconstruct-WhisperWindows` merges windows using the overlap, removing duplicates and preserving timing.
5. **Output**: Array of reconstructed word objects.

## Entry Point

```powershell
. .\whisper-reconstruction.ps1
$testFinal = @(Reconstruct-WhisperWindows $cleanWindows)
```

## Word Model

```powershell
[PSCustomObject]@{
    Text   = <string>
    Key    = <string>
    From   = <double>
    To     = <double>
    Tokens = <array>
    Id     = <string>
}
```

## Dependencies

- PowerShell 5.1+
- No external modules required
