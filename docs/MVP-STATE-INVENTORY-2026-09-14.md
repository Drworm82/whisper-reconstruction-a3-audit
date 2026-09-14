# MVP State Inventory

**Date:** 2026-09-14  
**Baseline:** `fa047d3276115e58a832c36c3b10272fd54127a9`  
**Branch:** `poc7-paso6-temporal-guard-clean`  
**Repository:** `Drworm82/whisper-reconstruction-a3-audit`

## 1. Purpose

This document establishes the current project state against a practical Phase 1 MVP definition derived from the repository's architecture review, POC results, and current project-state checkpoint.

It is an inventory, not an implementation plan. No source-code changes are implied by this document.

## 2. MVP definition used for this inventory

For this project, the Phase 1 MVP is considered the smallest local Windows application that can:

1. capture Windows system audio continuously;
2. preserve the complete session recording independently of ASR failure;
3. feed a bounded/low-latency audio stream into a persistent local ASR worker;
4. normalize ASR output into the established window contract;
5. reconstruct a continuous timestamped transcript using the validated reconstruction core;
6. tolerate ordinary ASR/transcription failures without losing the source recording;
7. operate for a realistic session without unbounded queue/memory growth;
8. expose enough temporal metadata and discontinuity information for a later context/LLM stage;
9. provide a reproducible end-to-end run with measurable latency and failure behavior.

The LLM/context stage itself is **not part of the Phase 1 MVP**. The architecture review explicitly places it after the continuous transcript boundary.

## 3. Current status summary

| MVP capability | Status | Evidence / gap |
|---|---|---|
| Validated reconstruction core | **DONE** | Alignment, temporal placement, deduplication, deferred-anchor handling, and end-of-run preservation have been validated through the POC7 work. |
| whisper.cpp import boundary | **DONE** | Real `-ojf` JSON converted, control/timestamp tokens excluded, token timing normalized, and reconstruction chain validated on the real fixture. |
| WASAPI loopback capture POC | **DONE (POC)** | POC4 validated capture, ring buffer, overlapping scheduler windows, sizing, and clean termination. |
| Bounded inference queue | **DONE (POC)** | POC6 validated queue mechanics in isolation. |
| Scheduler -> whisper-server structural path | **DONE (POC)** | POC5 structural integration passed. |
| Real repeated-overlap MATCH through live capture path | **PARTIAL** | Reconstruction has been validated on real overlapping ASR JSON; POC5 did not produce sufficient physical-overlap lexical content to validate real MATCH/deduplication in the live scheduler path. |
| Independent full-session recorder | **NOT DONE** | Architecture is specified, but repository documentation says the recorder implementation is not yet present as a validated subsystem. |
| Live capture -> recording + ASR fan-out | **NOT DONE** | Direct WASAPI/NAudio path is an architectural decision, not yet validated as the complete concurrent implementation. |
| Persistent live ASR worker with measured latency | **PARTIAL** | whisper-server has been exercised structurally, but sustained live inference latency/queue behavior has not been established. |
| Normalized live window contract | **PARTIAL** | The normalized reconstruction contract is established; live production of that contract from a continuous ASR worker remains to be demonstrated. |
| Incremental/streaming reconstruction semantics | **NOT DONE** | Current `Reconstruct-WhisperWindows` is a batch function over a collection of windows. Incremental invocation has not been proven equivalent to persistent streaming state. |
| Failure isolation | **PARTIAL** | Architectural requirement and isolated POCs exist; complete capture/recording survival under live ASR failure has not yet been demonstrated end-to-end. |
| Device-change/reconnection | **NOT DONE** | Explicitly identified as an outstanding capture POC requirement. |
| Sustained multi-hour operation | **NOT DONE** | Five-hour/long-duration behavior has not been validated. |
| Bounded memory/queue behavior under sustained load | **PARTIAL** | Bounded queue mechanics were validated in isolation; sustained integrated behavior remains unvalidated. |
| Measured capture-to-text latency | **NOT DONE** | No project invariant for end-to-end latency has been established. |
| Crash/restart recovery using preserved recording | **NOT DONE** | The recording-as-source-of-truth architecture is defined, but recovery/reprocessing behavior is not yet validated. |
| Persistent transcript store | **NOT DONE** | Architecture review identifies this as absent. |
| LLM/context stage | **OUT OF MVP** | Explicitly deferred to Phase 2. |

## 4. What is already solid

### 4.1 Reconstruction core

The reconstruction layer is the strongest part of the project. The current branch contains the validated POC7 Paso 6 implementation and its real-audio evidence. The final deferred end-of-run solution preserves pending words conditionally, deduplicates them using source-derived temporal tolerance, and inserts them chronologically.

The real-audio validation produced 121 windows and 120 transitions, with 44 deferred words processed at end-of-run, 23 discarded as temporal/text duplicates, and 21 preserved. No duplicate identities, timestamp alterations, or chronological-order violations were observed.

This should be treated as **frozen core behavior** while the remaining MVP infrastructure is built around it.

### 4.2 ASR boundary

The whisper.cpp adapter is already a clean boundary between native whisper.cpp JSON and the normalized token contract. The approximately 125-second real fixture has passed conversion, word construction, overlapping window construction, and reconstruction without token-control artifacts or word-count loss.

### 4.3 Capture architecture decision

The architecture now favors direct Windows WASAPI loopback through NAudio, with an early fan-out into independent session recording and a low-latency ASR path. OBS is not a mandatory dependency at this stage.

That decision is architectural; the complete implementation still requires proof.

## 5. Principal MVP gaps

The project is no longer primarily missing reconstruction logic. The remaining MVP risk is integration around the reconstruction core.

### Gap A — Capture core

Implement and validate a real WASAPI/NAudio capture component that continuously supplies PCM data without blocking the capture callback.

Acceptance evidence must include:

- continuous capture;
- known sample format/timeline;
- controlled buffering;
- clean shutdown;
- behavior when the playback device changes or disappears.

### Gap B — Recording consumer

Implement a session recorder independent of ASR/reconstruction. The recording must remain valid when the ASR side fails.

Acceptance evidence must include:

- complete session persisted;
- no dependency on ASR success;
- recoverable output after abnormal ASR termination;
- suitable segmentation/file strategy for long sessions.

### Gap C — Live ASR worker

Connect the capture stream to a persistent local ASR worker and measure:

- inference duration;
- queue delay;
- window age at inference;
- capture-to-text latency;
- behavior under load;
- worker failure/restart.

### Gap D — Live normalized window contract

Demonstrate that the live ASR worker produces windows with the metadata required by the existing reconstruction core, including authoritative audio-time information and monotonic window identity.

Do not rewrite the reconstruction algorithm merely to accommodate the live path until this contract has been demonstrated.

### Gap E — Streaming reconstruction integration

Determine experimentally how the current batch reconstruction state must be maintained for continuous operation. Do not assume that repeatedly calling the current batch function on partial windows is equivalent to a persistent streaming state machine.

The desired outcome is to preserve the validated reconstruction behavior while introducing only the minimum orchestration/state boundary required by live operation.

### Gap F — Integrated failure isolation

Demonstrate that an ASR worker crash, timeout, or queue failure does not terminate the capture/recording side and does not destroy the source recording.

### Gap G — Long-duration behavior

Run a realistic sustained session and measure memory, queue depth, CPU/GPU utilization, transcript growth, latency, and recovery behavior. Five hours is the current architectural target noted in the project state, but the exact MVP acceptance threshold should be made explicit before declaring production readiness.

### Gap H — Transcript persistence

Introduce the minimal persistent transcript representation required for later context queries. It should preserve text plus temporal metadata and explicit discontinuities, without coupling the Phase 1 core to an LLM.

## 6. MVP versus post-MVP

### Required for MVP

- Direct or otherwise validated continuous Windows audio capture.
- Independent complete-session recording.
- Live/bounded ASR feed.
- Persistent ASR worker behavior sufficient for a realistic session.
- Normalized live window contract.
- Continuous reconstruction using the validated core.
- Failure isolation between recording and ASR.
- Measured end-to-end latency.
- Device-change behavior defined and tested.
- Long-duration/soak evidence sufficient for the chosen MVP target.
- Minimal timestamped transcript persistence.

### Explicitly post-MVP / Phase 2

- LLM integration.
- Advanced question/context reasoning.
- Full conversational assistant UX.
- Production-grade process supervision beyond the MVP recovery requirements.
- Process-specific loopback if ordinary system loopback is sufficient.
- Final UX polish and distribution/installer work unless separately required by the product definition.

## 7. Recommended remaining POC sequence

The repository's earlier architecture review already provides the safest ordering. The current state suggests this sequence:

1. **Capture + recorder proof** — prove continuous WASAPI/NAudio capture and independent recording.
2. **Live ASR timing proof** — feed bounded live audio to the persistent ASR worker and measure latency/queue behavior.
3. **Live normalized-window proof** — establish the exact window contract produced by the live ASR path.
4. **Live reconstruction proof** — connect the live normalized windows to the frozen reconstruction core and measure MATCH/SIN MATCH, omissions, duplicates, order, and latency.
5. **Failure-isolation proof** — deliberately fail ASR while recording continues.
6. **Device-change proof** — change/remove/reconnect the playback device during capture.
7. **Soak test** — sustained realistic session with resource and latency measurements.
8. **Transcript persistence** — add the minimal store and query boundary required by Phase 2.
9. **MVP acceptance run** — one reproducible end-to-end scenario with all acceptance evidence collected.

## 8. Current MVP assessment

**Overall: NOT YET MVP.**

The project has a **validated reconstruction core plus several validated infrastructure POCs**, but it does not yet have the integrated live application required by the Phase 1 target architecture.

The principal remaining work is therefore integration and operational validation rather than another round of reconstruction-algorithm redesign.

A numerical completion percentage is intentionally not assigned here because the remaining work is concentrated in a few high-risk integration boundaries; a simple percentage would obscure those dependencies.

## 9. Baseline and change-control rule

This inventory uses commit `fa047d3276115e58a832c36c3b10272fd54127a9` as the official post-Paso-6 baseline.

Until the MVP gaps above are addressed, the validated reconstruction core should be treated as frozen. New work should be isolated to the specific next POC and accompanied by its own evidence and documentation.

No LLM implementation is required to close the Phase 1 MVP.
