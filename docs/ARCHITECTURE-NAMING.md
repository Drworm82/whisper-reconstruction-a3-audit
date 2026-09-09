# ASR and Reconstruction Naming

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`

## Purpose

Clarify the similarly named Whisper/WhisperX/reconstruction components so that the project architecture is not confused with the historical script names.

## The names are not four Whisper engines

The project currently contains different layers with similar names:

| Name | Type | Role |
|---|---|---|
| `whisper.cpp` | ASR engine | Converts audio into a transcription/token stream. Current ASR path under investigation/validation. |
| `WhisperX` | ASR/alignment backend | Alternative ASR/alignment path retained in the repository. It has its own import adapter. |
| `whisper-reconstruction` | Project/repository name | The project that reconstructs a continuous transcript from ASR output produced in windows. |
| `whisper-reconstruction.ps1` | Project entry-point script | Loads the modular reconstruction functions (`Build-WhisperWords`, `Find-WordOverlap`, `Reconstruct-WhisperWindows`). It is not an ASR engine. |
| `whisper-reconstruct.ps1` | Monolithic/legacy reconstruction script | Contains implementations of `Build-WhisperWords`, `Find-WordOverlap`, and `Reconstruct-WhisperWindows` together. It is not an ASR engine and does not represent a separate Whisper backend. |

## Current conceptual architecture

```text
audio
  |
  +--> whisper.cpp ------------------+
  |                                  |
  +--> WhisperX (alternative) -------+
                                     |
                              import adapter
                        Convert-WhisperCpp / Convert-WhisperX
                                     |
                             normalized ASR data
                                     |
                              word construction
                                     |
                                windowing
                                     |
                             reconstruction
                                     |
                              continuous text
```

The ASR/import boundary is intentionally separated from the reconstruction logic.

## Evidence from the repository

### `whisper-reconstruction.ps1`

The entry-point script loads the modular reconstruction components and reports the available reconstruction functions. It does not invoke an ASR engine or capture audio.

### `whisper-reconstruct.ps1`

The script contains the reconstruction functions directly. `Build-WhisperWords` receives tokens as input; `Find-WordOverlap` compares word sequences; and `Reconstruct-WhisperWindows` receives already-created windows. Therefore this file is reconstruction logic, not Whisper inference.

### `src/Pipeline/Invoke-WhisperReconstruction.ps1`

The current pipeline script is specifically wired to WhisperX: it requires a `WhisperXPath`, imports `Convert-WhisperX.ps1`, converts the WhisperX output, creates windows, and calls `Reconstruct-WhisperWindows`.

This means the existing pipeline entry point is not yet a generic `whisper.cpp` streaming pipeline.

### Import adapters

The repository has separate adapters:

- `src/Import/Convert-WhisperCpp.ps1`
- `src/Import/Convert-WhisperX.ps1`

Their purpose is to keep backend-specific output handling at the ASR/import boundary rather than modifying reconstruction logic for each ASR backend.

## Important architectural conclusion

The names should be interpreted as layers, not as sequential programs:

```text
Whisper.cpp OR WhisperX
        |
        v
   import adapter
        |
        v
 reconstruction pipeline
```

WhisperX is currently retained as an alternative/established backend path. Whisper.cpp is the backend currently being validated for the new path. The reconstruction algorithms are intended to be backend-independent once the adapter produces the expected representation.

## What is still unknown

The repository does **not** currently identify the external mechanism that connects OBS-generated audio files to Whisper.cpp. The OBS -> WAV -> Whisper.cpp execution/monitoring bridge must be located separately before real-time latency can be determined.

No conclusion should yet be recorded that the application necessarily has a two-minute latency. That depends on how OBS blocks are detected and processed.
