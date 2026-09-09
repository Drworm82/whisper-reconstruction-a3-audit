# Project State Addendum — Phase 1 Architecture Review

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`

This addendum records the architecture conclusions from the repository review. The canonical detailed review is `docs/ARCHITECTURE-REVIEW-2026-09-09.md`.

## Current repository state

The repository is currently a batch/post-processing reconstruction project. It has no NAudio/WASAPI capture subsystem, live audio buffer, session recorder, ASR worker supervisor, or persistent transcript store.

The current `Invoke-WhisperReconstruction` wrapper is WhisperX/file-oriented: it accepts a `WhisperXPath`, calls `Convert-WhisperX`, flattens tokens, creates batch windows, and calls reconstruction. It is not the Phase 1 live orchestrator.

## Preserve

- `Convert-WhisperCpp` as the whisper.cpp import boundary.
- `Build-WhisperWords`.
- `Find-WordOverlap`.
- Validated behavior in `Reconstruct-WhisperWindows`.
- Existing regression tests and fixtures.
- WhisperX adapter until backend comparison is complete.

## Do not repurpose without evidence

- `New-WhisperWindows` is a batch/grid windowing utility, not a live PCM scheduler.
- `Invoke-WhisperReconstruction` should not be turned into the live orchestrator merely by adding audio-capture concerns.

## Phase 1 target

```text
Windows audio
    -> WASAPI Loopback
    -> NAudio
    -> early fan-out
       -> independent session recording
       -> bounded live ASR path
          -> persistent whisper.cpp candidate
          -> normalized ASR windows
          -> existing reconstruction
          -> continuous transcript
```

A process boundary between capture/recording and ASR is justified by fault isolation: an ASR/Vulkan failure must not terminate source recording.

`whisper-server` is a POC candidate, not a production decision.

## Open validation items

- Capture stability and device-change recovery.
- Non-blocking fan-out.
- Recording format/segment duration.
- Live window/stride strategy.
- Persistent whisper.cpp behavior and context semantics.
- Sustained GPU performance.
- Incremental use of reconstruction without algorithm changes.
- Multi-hour memory/runtime behavior.
- ASR crash recovery from persisted audio.
- Final multilingual model selection.

## Next phase gate

Do **POC 1 only** before adding whisper.cpp streaming: NAudio + WASAPI Loopback capture, persistent session recording, and an independent ASR stub. Kill the ASR stub during capture and prove the recording path remains intact.

No reconstruction source-code change is authorized by this architecture review alone.
