# POC 1 — WASAPI Loopback / NAudio Capture Results

**Date:** 2026-09-09  
**Branch:** `reconstruction-fixes`  
**Status:** Capture path validated; WAV recording not yet implemented  
**Scope:** Capture only. No whisper.cpp integration was performed in this POC step.

## 1. Objective

Validate on the target Windows machine that the proposed Phase 1 audio-capture foundation can open a system-audio render endpoint through WASAPI Loopback using NAudio and deliver continuous PCM buffers to the application.

This test is intentionally isolated from whisper.cpp, reconstruction, and LLM integration.

## 2. Environment

- Windows target machine.
- .NET SDK: `10.0.302`.
- NAudio: `3.1.0`.
- `NAudio.Wasapi`: `3.1.0`.
- Isolated POC project: `AudioCapturePOC`.
- Initial capture API: `WasapiLoopbackCapture`.

The current NAudio API reports `WasapiLoopbackCapture` as obsolete for new code; the production-oriented implementation should migrate to `WasapiRecorderBuilder`. The obsolete API was retained for this first proof because it provided the shortest path to validating the underlying capture mechanism.

## 3. Device validation

Windows audio devices and audio endpoints were queried before capture. The relevant endpoint inventory returned devices with `Status OK`, including the AMD display-audio endpoints, Realtek audio, and several virtual audio endpoints.

No assumption was made that a hardware "Stereo Mix" device was required.

## 4. Capture implementation

The POC created a `WasapiLoopbackCapture`, subscribed to `DataAvailable` and `RecordingStopped`, printed the negotiated format, started recording, and stopped on user input.

The application built successfully after adding `NAudio.Wasapi`.

## 5. Observed result

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

The process subsequently reported:

```text
Captura detenida.
```

No capture exception was reported in the test output.

The complete console capture is preserved as experimental evidence in the conversation artifact used for this validation.

## 6. Interpretation

For the scope of this POC, the following points are demonstrated:

1. NAudio can instantiate the WASAPI loopback capture path on the target machine.
2. A render endpoint is available and negotiates `48 kHz`, `2 channels`, `32-bit IEEE Float`.
3. Audio data is delivered repeatedly through `DataAvailable` while system audio is playing.
4. The capture can be stopped cleanly.
5. The basic capture mechanism therefore works on the target machine and is suitable for the next experiment.

At the observed format, 3840 bytes correspond to 480 stereo frames, or approximately 10 ms of audio. 7680 bytes correspond to approximately 20 ms. This describes callback payload duration, **not end-to-end application latency**.

## 7. What this does not prove

This POC does **not** yet prove:

- end-to-end capture latency;
- uninterrupted capture over multi-hour sessions;
- behavior when no system audio is playing;
- device-change/disconnect recovery;
- non-blocking fan-out to multiple consumers;
- persistent recording;
- ASR throughput or latency;
- whisper.cpp streaming behavior;
- reconstruction correctness in an incremental live flow;
- GPU stability under sustained ASR load.

In particular, the observed 10–20 ms callback payloads must not be interpreted as a 10–20 ms transcription latency.

## 8. Architectural consequence

The first architectural assumption has been validated: the target machine can provide system audio to a local application through WASAPI Loopback/NAudio.

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

## 9. Next experiment

The next step is to modify the isolated POC so that received buffers are written to a WAV file, then verify that the resulting file is valid and contains the captured system audio.

Whisper.cpp should **not** be connected until persistent capture/recording has been demonstrated.

After recording validation, the next architectural gate is the independent ASR-stub/fault-isolation test described in the Phase 1 architecture review.
