# POC 1 — WASAPI Loopback / NAudio Capture Results

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`  
**Status:** **PASS — capture and WAV output validated**  
**Scope:** Capture and recording only. No whisper.cpp integration was performed in this POC step.

## 1. Objective

Validate on the target Windows machine that the proposed Phase 1 audio-capture foundation can open a system-audio render endpoint through WASAPI Loopback using NAudio, deliver continuous PCM buffers, persist those buffers to WAV, and reproduce the captured audio.

This test is intentionally isolated from whisper.cpp, reconstruction, and LLM integration.

## 2. Environment

- Windows target machine.
- .NET SDK: `10.0.302`.
- NAudio: `3.1.0`.
- `NAudio.Wasapi`: `3.1.0`.
- Isolated POC project: `AudioCapturePOC`.
- Initial capture API: `WasapiLoopbackCapture`.
- Test source: YouTube playback through the Windows audio output.

The current NAudio API reports `WasapiLoopbackCapture` as obsolete for new code; the production-oriented implementation should migrate to `WasapiRecorderBuilder`. The obsolete API was retained for this first proof because it provided the shortest path to validating the underlying capture mechanism.

## 3. Device validation

Windows audio devices and audio endpoints were queried before capture. The relevant endpoint inventory returned devices with `Status OK`, including the AMD display-audio endpoints, Realtek audio, and several virtual audio endpoints.

No assumption was made that a hardware "Stereo Mix" device was required.

## 4. Capture implementation

The POC created a `WasapiLoopbackCapture`, subscribed to `DataAvailable` and `RecordingStopped`, printed the negotiated format, started recording, and stopped on user input.

The application built successfully after adding `NAudio.Wasapi`.

## 5. Observed capture result

The capture process reported:

```text
Formato: 32 bit IEEEFloat: 48000Hz 2 channels
Capturando. Presiona ENTER para detener.
```

During playback, the application received a large number of buffers. The observed buffer sizes included:

```text
Buffer recibido: 3840 bytes
Buffer recibido: 7680 bytes
```

The process subsequently stopped cleanly. No capture exception was reported during the initial capture-only test.

At the observed format, 3840 bytes correspond to 480 stereo frames, or approximately 10 ms of audio. 7680 bytes correspond to approximately 20 ms. This describes callback payload duration, **not end-to-end application latency**.

## 6. WAV recording validation

The POC was then changed to write each received PCM buffer to a `WaveFileWriter` using the negotiated capture format.

The first implementation exposed a lifecycle error: `RecordingStopped` attempted to flush a writer that had already been disposed, producing `System.ObjectDisposedException`. This was a defect in the POC's resource lifetime handling, not in WASAPI/NAudio capture.

After correcting the writer lifetime, the capture completed successfully and produced:

```text
C:\Users\Enrique\whisper-reconstruction\AudioCapturePOC\loopback-test.wav
```

Observed file size:

```text
3,171,898 bytes
```

The file header was inspected directly and returned:

```text
RIFF
WAVE
2
48000
32
```

Interpretation:

- `RIFF` — RIFF container signature.
- `WAVE` — WAV format identifier.
- `2` — two channels.
- `48000` — 48 kHz sample rate.
- `32` — 32 bits per sample.

The resulting WAV was opened and the captured YouTube audio was audible. This confirms that the persisted file contains actual captured system audio and is not merely a structurally valid WAV header.

## 7. What this POC proves

The following assumptions are now experimentally validated on the target machine:

1. Windows system audio can be captured through WASAPI Loopback.
2. NAudio can receive the resulting PCM buffers.
3. The negotiated capture format is 48 kHz, stereo, 32-bit IEEE Float.
4. The captured buffers can be persisted as a WAV file.
5. The resulting WAV is structurally valid.
6. The resulting WAV contains audible system audio from the selected playback source.
7. The capture can be stopped cleanly after recording.

This removes **basic WASAPI/NAudio capture and WAV persistence viability** from the Phase 1 unknowns.

## 8. What this POC does not prove

This POC does **not** yet prove:

- end-to-end capture latency;
- uninterrupted capture over multi-hour sessions;
- behavior when no system audio is playing;
- device-change/disconnect recovery;
- non-blocking fan-out to multiple consumers;
- segmented long-session recording behavior;
- ASR throughput or latency;
- whisper.cpp streaming behavior;
- reconstruction correctness in an incremental live flow;
- GPU stability under sustained ASR load;
- production suitability of the obsolete `WasapiLoopbackCapture` API.

In particular, the observed 10–20 ms callback payloads must not be interpreted as 10–20 ms transcription latency.

## 9. Architectural consequence

The first architectural assumption has been validated: the target machine can provide usable system audio to a local application through WASAPI Loopback/NAudio, and that audio can be persisted independently of ASR.

The Phase 1 architecture remains:

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

The independent recording path remains mandatory during the experimental phase. ASR and reconstruction must not become prerequisites for preserving the original session audio.

## 10. Next experiment

The next architectural gate is **POC 2 — independent ASR-stub/fault isolation and bounded live buffering**.

The objective is to prove that the capture/recording side remains operational when the ASR consumer is delayed, stopped, or fails. Whisper.cpp should not be connected until this isolation behavior has been demonstrated.

No reconstruction source-code change is justified by POC 1.
