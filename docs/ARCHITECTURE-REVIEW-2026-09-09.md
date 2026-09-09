# Phase 1 Architecture Review

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`  
**Status:** Architecture reviewed; no implementation change made by this review

## 1. Purpose

Compare the current repository architecture with the target Phase 1 architecture for a local ParakeetAI-style Windows application:

```text
Windows system audio
        |
WASAPI Loopback
        |
      NAudio
        |
   early fan-out
      /      \
     v        v
recording   live ASR buffer
              |
          whisper.cpp
              |
        normalized ASR data
              |
      windowing/reconstruction
              |
       continuous transcript
```

The later LLM/context stage remains outside Phase 1.

## 2. Repository reality

The repository is currently a **batch/post-processing reconstruction project**, not yet a live audio application.

The current modular loader imports:

- `Word.ps1`
- `Build-WhisperWords.ps1`
- `Find-WordOverlap.ps1`
- `Convert-WhisperX.ps1`
- `Convert-WhisperCpp.ps1`
- `New-WhisperWindows.ps1`
- `Reconstruct-WhisperWindows.ps1`
- `Invoke-WhisperReconstruction.ps1`

There is currently no audio-capture subsystem, no NAudio integration, no live audio buffer, no session recorder, no ASR worker supervisor, and no transcript store in the repository.

## 3. Component disposition

| Current component | Phase 1 disposition | Rationale |
|---|---|---|
| `src/Import/Convert-WhisperCpp.ps1` | **Keep; adapt boundary later** | Correct location for whisper.cpp-specific output normalization. Already filters control/timestamp tokens and converts timing units. |
| `src/Import/Convert-WhisperX.ps1` | **Keep for now; legacy/alternative backend** | WhisperX remains a valid alternative backend and must not be removed prematurely. |
| `src/Words/Build-WhisperWords.ps1` | **Keep unchanged unless regression** | Existing reconstruction invariant; whisper.cpp adapter should provide compatible tokens. |
| `src/Alignment/Find-WordOverlap.ps1` | **Keep unchanged unless regression** | Existing alignment component. |
| `src/Reconstruction/Reconstruct-WhisperWindows.ps1` | **Keep unchanged for architecture work** | Contains previously validated fixes. Do not rewrite to solve capture/ASR integration problems. |
| `src/Windowing/New-WhisperWindows.ps1` | **Keep as batch/grid utility; do not assume it is the live window generator** | It builds artificial windows from already constructed words. Live audio will need a window scheduler over audio time. |
| `src/Pipeline/Invoke-WhisperReconstruction.ps1` | **Do not use as the Phase 1 live pipeline** | It is explicitly hard-wired to a `WhisperXPath`, loads `Convert-WhisperX`, converts WhisperX output, flattens tokens to words, then creates windows. It does not accept live audio or whisper.cpp directly. |
| `src/Load-WhisperReconstruction.ps1` | **Keep; later extend only if justified** | Current role is deterministic loading of reconstruction modules. It should not become the audio orchestrator by accident. |
| tests/fixtures/data | **Keep** | They provide regression evidence and fixtures for the existing reconstruction path. |
| `docs/*` | **Extend** | Architecture and experiment status must remain persistent. |

## 4. Critical architectural finding: the current pipeline cannot simply be switched to live whisper.cpp

The current `Invoke-WhisperReconstruction` function requires a filesystem path named `WhisperXPath`, verifies that it exists, calls `Convert-WhisperX`, flattens its tokens into words, calls `New-WhisperWindows`, and finally calls `Reconstruct-WhisperWindows`.

Therefore, the correct future design is **not** to modify this function until it becomes a generic live pipeline. The cleaner boundary is to introduce a new live orchestration path that produces the normalized window contract required by reconstruction.

This preserves the existing validated reconstruction path and avoids coupling audio capture to legacy WhisperX file processing.

## 5. Current reconstruction boundary

`Reconstruct-WhisperWindows` currently receives an array of windows with `Start`, `End`, and `Tokens`. It builds accumulated words internally and maintains state such as `previousOverlapMap` and deferred anchor information while traversing windows.

The function therefore already provides a useful **window-to-reconstructed-text boundary**, but it currently operates as a batch function over an entire window collection.

For live use, we should not assume that repeatedly invoking it on arbitrary partial collections is equivalent to a persistent streaming state machine. That behavior must be demonstrated experimentally before changing the algorithm.

## 6. `New-WhisperWindows` is not the live audio window scheduler

`New-WhisperWindows` accepts already-created word objects, discovers the minimum/maximum word times, and constructs an artificial time grid with a configured duration and overlap. It also has a rescue pass for words not strictly contained in a grid window.

That is appropriate for post-hoc reconstruction experiments. It does not consume PCM audio and therefore cannot itself determine when a live ASR window should be submitted.

A future live scheduler should operate from the authoritative audio timeline and produce ASR windows. Whether its normalized outputs can be passed directly into the existing reconstruction must be tested; no algorithmic rewrite is authorized by this review.

## 7. Temporal authority

For the live architecture, audio sample position should be treated as the primary session timeline. Whisper token timestamps remain relative ASR evidence rather than the sole absolute clock.

A future window contract should therefore carry enough metadata to relate ASR output back to the audio timeline, at minimum a monotonically increasing sequence/window identifier and an absolute audio start/end position.

A device-change or other capture discontinuity must be represented explicitly rather than inventing silence. Reconstruction continuity across a genuine gap must be treated as a separate behavior to test.

## 8. Recording architecture

The complete session recording must be a separate consumer of the captured PCM stream and must not depend on ASR or reconstruction success.

The repository currently has no recorder implementation. This should therefore be introduced as a new subsystem rather than modifying reconstruction modules to handle recording.

For the initial POC, segmented WAV recording is a candidate because it avoids the classic RIFF-size problem of a multi-hour single WAV and limits the amount of audio exposed to a single file after an abnormal termination. Exact segment duration remains an experimental parameter.

## 9. Process architecture

The review supports a process boundary between capture/recording and ASR because the most important requirement is **fault isolation**:

```text
Capture Core
  ├─ WASAPI/NAudio
  ├─ session recording
  └─ bounded live buffer / chunk delivery
             |
             v
        ASR Worker
  ├─ whisper.cpp / whisper-server candidate
  └─ reconstruction orchestration
```

The process boundary is not justified merely as stylistic modularity. An ASR/Vulkan failure must not be able to terminate the process responsible for preserving the original recording.

For the first implementation, HTTP localhost through `whisper-server` is a candidate IPC mechanism because it avoids inventing a custom transport. This remains a POC decision, not a production commitment.

## 10. Whisper.cpp integration status

`Convert-WhisperCpp.ps1` is already a valid import boundary for `-ojf` JSON. It parses segment timestamps, converts token offsets from milliseconds to seconds, preserves token leading whitespace, and excludes control/timestamp tokens matching `^\[_.*\]$`.

The real approximately 125-second fixture has already validated the post-hoc chain through reconstruction. This proves the adapter/reconstruction compatibility at that structural level, but does not prove live streaming behavior.

A live ASR adapter must eventually produce normalized windows without requiring a completed JSON file on disk. The exact mechanism (persistent whisper process/server vs another integration) remains to be measured.

## 11. Most important unknowns before implementation

1. NAudio/WASAPI loopback capture behavior on the target Windows machine.
2. Reliable fan-out to recording and live ASR without blocking the audio capture callback.
3. Practical audio window/stride parameters for the target course audio.
4. Sustained whisper.cpp performance under realistic concurrent GPU load.
5. Whether `whisper-server` provides the desired persistent-process behavior and context semantics for this use case.
6. Whether the existing reconstruction can be driven incrementally without changing its validated algorithm.
7. Reconstruction runtime and memory behavior over multi-hour input.
8. Device-change/disconnect recovery and timeline discontinuity handling.
9. ASR crash recovery from the persisted session recording.

## 12. POC sequence derived from the repository review

### POC 1 — Capture isolation

Build only enough infrastructure to prove:

```text
WASAPI/NAudio -> recording
                    |
                    + independent ASR stub
```

Kill the ASR side and verify recording continues.

### POC 2 — Live audio buffering

Add a bounded live buffer/chunk producer while preserving the independent recorder. Measure buffer behavior and capture continuity.

### POC 3 — whisper.cpp persistent ASR

Feed controlled audio chunks to the selected persistent whisper.cpp mechanism. Measure inference time, queue delay, and output timing.

### POC 3.5 — normalized live window contract

Prove that live ASR output can be represented as the normalized window contract required by the existing reconstruction without changing the reconstruction algorithm.

### POC 4 — reconstruction in live flow

Only after POC 3.5 succeeds, connect the live normalized windows to the existing reconstruction and measure duplicates, omissions, SIN MATCH frequency, ordering, and latency.

### POC 5 — sustained operation

Run a multi-hour controlled session and measure memory, GPU/CPU usage, queue depth, latency, gaps, recovery, and reconstruction cost.

## 13. Phase 2 preparation

Do not implement the LLM now.

The only Phase 1 requirement is to preserve a persistent transcript with temporal metadata and explicit discontinuity information so that a future context layer can query recent or historical transcript ranges without coupling the reconstruction algorithm to an LLM.

## 14. Architectural conclusion

The repository already contains a useful and validated **reconstruction core**, but it does not yet contain the infrastructure required for a local real-time application.

The safest strategy is therefore:

```text
                EXISTING VALIDATED CORE
                       |
                       v
                 normalized windows
                       ^
                       |
             NEW LIVE ASR ADAPTER
                       ^
                       |
              NEW ASR WORKER
                       ^
                       |
                NEW AUDIO CORE
                /             \
        WASAPI/NAudio       recorder
```

The new architecture should be built around the existing reconstruction contract, not by turning the current batch pipeline into an all-purpose real-time orchestrator.

No source-code changes to the reconstruction pipeline are justified by this architecture review alone.
