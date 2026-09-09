# Audio Capture Architecture Investigation

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`  
**Status:** Investigation documented; implementation not yet started

## Purpose

Determine whether OBS Studio is technically required for the local ParakeetAI-style application, or whether Windows audio can be captured directly and supplied to the local ASR pipeline with low latency.

The investigation also separates two requirements that were previously combined:

1. a low-latency audio stream for real-time ASR; and
2. a complete recording of the session for later verification/reprocessing.

## Evidence and scope

The product being used as the functional reference is ParakeetAI at `https://www.parakeet-ai.com/`. Its public product description presents desktop transcription and assistance as operating during the call, but the public site does not establish which Windows audio-capture API it uses internally.

Therefore, no implementation claim is made here that ParakeetAI itself uses WASAPI, NAudio, or OBS. The following conclusions concern the technical options available for our local implementation.

## Finding 1: Windows provides native loopback capture

Microsoft documents WASAPI loopback recording as a way for an application to capture the audio stream being rendered by an output device. This does not require a physical `Stereo Mix` input and does not require a third-party virtual audio driver.

Official reference:

- Microsoft, `Loopback Recording`: `https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording`

This makes native Windows loopback capture a technically viable replacement for using OBS as the mandatory audio-capture intermediary.

## Finding 2: NAudio exposes WASAPI loopback capture

The current NAudio documentation describes `WasapiRecorder` and `WithLoopbackCapture()` for capturing audio being rendered by an output device. Captured data is delivered to the application rather than requiring a completed recording file before processing can begin.

Official project/documentation references:

- NAudio WASAPI Recorder: `https://github.com/naudio/NAudio/blob/main/Docs/WasapiRecorder.md`
- NAudio source: `https://github.com/naudio/NAudio`

The exact capture latency for our hardware, Windows configuration, and chosen buffering parameters has **not** yet been measured. Therefore no fixed millisecond latency is recorded as a project invariant.

## Finding 3: A two-minute recording block does not imply a two-minute ASR latency

A file-based workflow can introduce approximately the duration of a recording block if the consumer waits for the file to close before processing it. That is a property of the integration, not an inherent requirement of Windows loopback capture or NAudio.

A direct capture path can receive audio continuously and maintain a short processing buffer. Whisper.cpp can then operate on intentionally selected ASR windows while the session continues.

The project therefore must **not** assume a two-minute live-transcription delay merely because a two-minute recording/backup interval exists somewhere in a capture workflow.

## Finding 4: Recording and ASR should be separate consumers of the same capture stream

The experimental application needs a trustworthy recording because the live ASR/reconstruction/AI stack is not yet considered reliable enough to be the sole record of a class or meeting.

The preferred conceptual design is therefore a fan-out after capture:

```text
Windows system audio
        |
        v
WASAPI Loopback
        |
        v
      NAudio
        |
        +--------------------+
        |                    |
        v                    v
Full-session recording   Low-latency buffer
        |                    |
        v                    v
  source-of-truth       whisper.cpp
  audio backup              |
                             v
                       reconstruction
                             |
                             v
                      question/context
                             |
                             v
                            LLM
```

The recording path must not depend on the success of Whisper, reconstruction, or the later AI stage.

The recorded session becomes the source audio that can be reprocessed offline if the experimental live pipeline loses words, produces incorrect reconstruction, crashes, or generates an incorrect AI response.

## Finding 5: OBS is not currently justified as a mandatory component

The earlier recommendation for OBS had a valid operational rationale: OBS provides mature Windows audio capture, recording, automatic file splitting, and automation facilities. It was also considered useful as a robust backup recorder.

However, the current investigation establishes that the specific low-latency capture capability we need is available directly through Windows WASAPI loopback and NAudio. Consequently, OBS is **not technically established as a required component** of the local architecture.

At this stage OBS should be treated as:

- an optional recording/reference tool;
- a diagnostic and comparison tool during the proof of concept;
- not a required intermediary between Windows audio and whisper.cpp.

This is a change in architectural confidence, not yet an implementation change.

## Finding 6: Process-specific loopback may be useful later

Windows also documents Application Loopback Audio Capture, which can target audio associated with a specific process rather than capturing the entire system render stream. This capability is available on supported Windows versions and may be useful if the application eventually needs to capture only a meeting/call application.

Official reference:

- Microsoft, `Application Loopback Audio Capture Sample`: `https://learn.microsoft.com/en-us/samples/microsoft/windows-classic-samples/applicationloopbackaudio-sample/`

This is an option for later investigation. It is not yet selected as the project's capture architecture.

## Finding 7: Device-change recovery remains a POC requirement

A remaining technical concern is what happens when the Windows default output device changes or disappears while capture is active, for example when headphones are connected/disconnected or a different output device becomes default.

Microsoft documents recovery from invalidated audio devices by releasing/recreating the audio client against the current device. NAudio also provides device-routing functionality, but its current documented compatibility constraints with loopback capture mean that the exact recovery behavior for this project must be tested rather than assumed.

This is one of the primary acceptance criteria for the capture proof of concept.

## OBS decision status

**Decision:** Do not make OBS a mandatory dependency yet.

**Reason:** Native WASAPI loopback plus NAudio provides a direct technical path for both continuous capture and application-controlled buffering, while the session recording requirement can be implemented as a separate consumer of the captured stream.

**Not yet validated:**

- measured end-to-end capture latency;
- sustained capture for a five-hour session;
- behavior when the default playback device changes;
- whether every target application behaves correctly with loopback capture;
- simultaneous recording and ASR fan-out under sustained load;
- whisper.cpp real-time chunking/inference latency.

## Required proof of concept before implementation is considered validated

1. Capture Windows system audio using NAudio WASAPI loopback.
2. Record the complete captured stream to a persistent session file.
3. Simultaneously expose the captured PCM data to a short in-memory ASR buffer.
4. Feed controlled audio into whisper.cpp and timestamp both the source audio and transcription arrival.
5. Measure capture-to-text latency rather than inferring it from recording block size.
6. Change the default Windows playback device during capture and verify whether audio is lost.
7. Repeat with a realistic meeting/class audio source.
8. Preserve the complete recording even if the ASR or AI pipeline fails.

Only after this POC should the project select final capture buffering parameters and decide whether OBS has any continuing production role.

## Current architectural hypothesis

```text
                         Windows Audio
                              |
                       WASAPI Loopback
                              |
                            NAudio
                              |
                 +------------+------------+
                 |                         |
                 v                         v
          Session recording          ASR stream/buffer
                 |                         |
                 v                         v
          source audio backup         whisper.cpp
                                           |
                                           v
                                    reconstruction
                                           |
                                           v
                                   question/context
                                           |
                                           v
                                          LLM
```

OBS may remain outside this architecture as an optional diagnostic/backup tool until the POC demonstrates whether the direct path satisfies the project's reliability requirements.
