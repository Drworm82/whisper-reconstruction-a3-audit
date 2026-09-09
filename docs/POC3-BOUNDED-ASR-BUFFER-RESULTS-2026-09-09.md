# POC 3 — Bounded ASR Buffer / Backpressure

**Date:** 2026-09-09  
**Status:** PASS — bounded buffer and non-blocking capture validated

## Objective

Validate that the WASAPI loopback capture path can remain active when the ASR consumer is deliberately slower than the capture producer, while preventing unbounded growth of the ASR queue.

## Test configuration

- Platform: Windows
- .NET: 10.0.302
- NAudio: 3.1.0
- Capture: `WasapiLoopbackCapture`
- Captured format: 32-bit IEEE Float, 48 kHz, 2 channels
- ASR queue: `BlockingCollection<byte[]>` with capacity 50
- Queue insertion: `TryAdd`, so the capture callback does not block waiting for ASR
- Artificial ASR processing delay: 200 ms per buffer
- Capture duration: 15 seconds
- Full-session recording: WAV writer on the capture path

## Observed result

The queue reached its configured limit of 50 buffers while the ASR consumer remained intentionally slower than the capture producer. Once full, incoming buffers for the ASR path were discarded instead of blocking the capture callback.

Final counters:

- Buffers captured: **1318**
- Buffers processed by ASR stub: **124**
- Buffers discarded because the ASR queue was full: **1194**
- Buffers remaining in queue at shutdown: **0**
- Maximum queue capacity: **50**

The console showed `ASR QUEUE LLENA — buffer descartado` while capture counters continued increasing. After `Captura detenida`, the ASR consumer continued draining the queued buffers until it finalized at buffer 124.

The recording path produced:

`C:\Users\Enrique\whisper-reconstruction\AudioCapturePOC\poc3-bounded-buffer.wav`

## What this validates

1. The capture callback can continue operating while the ASR consumer is overloaded.
2. The ASR queue has a hard memory bound in this POC.
3. Queue overflow does not block the capture callback because insertion uses `TryAdd`.
4. The recording path is independent of ASR queue capacity and continues receiving captured audio.
5. Shutdown can complete cleanly and the bounded queue can be drained to zero after capture stops.

## Important limitation

The discard policy is provisional. This POC discards the **newest incoming ASR buffer** when the queue is full. With 10–20 ms capture buffers, this can create temporal gaps in the audio presented to ASR. It is therefore a backpressure mechanism, not yet an acceptable final transcription policy.

The test also uses an artificial ASR delay rather than real whisper.cpp inference. It does not establish real-time transcription throughput, transcription latency, GPU utilization, or sustained five-hour behavior.

## Architectural disposition

**Keep:** bounded buffering and non-blocking capture as architectural requirements.

**Do not yet freeze:** the exact overflow/drop policy, buffer size, chunk duration, or ASR scheduling strategy.

The next POC should replace the artificial ASR consumer with a controlled whisper.cpp integration or equivalent representative workload and measure whether the system can maintain an acceptable live transcription horizon without excessive data loss.

## Relationship to previous POCs

- POC1 validated WASAPI loopback capture and independent WAV recording.
- POC2 validated that the recording path can survive an injected ASR consumer failure.
- POC3 validates bounded ASR buffering and non-blocking behavior under sustained ASR overload.

Together, these POCs support the Phase 1 architecture of:

`Windows audio → WASAPI loopback → NAudio → full-session recording + live ASR buffer → ASR → reconstruction`

They do not yet validate the complete live transcription path.