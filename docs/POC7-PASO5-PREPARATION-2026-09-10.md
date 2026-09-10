# POC7 Paso 5 — preparation checkpoint

**Date:** 2026-09-10  
**Status:** PREPARATION / NOT YET VALIDATED

## Purpose

Record the evidence available immediately before beginning POC7 Paso 5.

Paso 5 will integrate the corrected `Convert-WhisperServer` adapter into the live POC7
end-to-end flow and validate multiple consecutive HTTP inference responses through:

`Convert-WhisperServer -> Build-WhisperWords -> Reconstruct-WhisperWindows`

No Paso 5 code change is included in this checkpoint.

## Existing Paso 4 evidence

The corrected `Convert-WhisperServer` adapter was validated against the Spanish turbo fixture:

- `AudioCapturePOC/poc7-language-es-turbo.json`
- 4 whisper-server segments
- 45 token units
- segment envelope `0.000 s -> 14.680 s`
- exactly 1 normalized Window returned by the adapter
- 26 reconstructed words
- expected Spanish text preserved exactly
- Pester regression: 3 passed, 0 failed

Paso 4 therefore validates the adapter contract for a single HTTP response containing multiple
internal whisper-server segments.

Detailed result: `docs/POC7-PASO4-WHISPER-SERVER-SEGMENT-CONTINUITY-RESULTS-2026-09-10.md`.

## Live POC7 evidence already available

POC7 Paso 3 has been executed successfully after restarting the local environment.
The live harness produced three scheduler windows and sent each window sequentially to the
persistent local `whisper-server` at `127.0.0.1:8080`.

Two valid runs were observed with:

- 3 windows produced
- 3 windows processed
- 0 queue drops
- 0 inference failures
- processing order `#00 #01 #02`
- HTTP 200 for all three inference requests
- AMD Radeon RX 6600 XT / Vulkan server runtime

Observed inference durations were approximately 2.25–2.65 seconds per window in those runs.
Word and segment counts differed between runs because the captured desktop audio differed.

These runs validate the HTTP inference path and bounded sequential processing, but they did
not yet pass the responses through `Convert-WhisperServer`, `Build-WhisperWords`, and
`Reconstruct-WhisperWindows` inside the live C# harness.

## WAV artifact check

A recursive search of `AudioCapturePOC` found historical WAV artifacts, but the specific
scheduler output directory checked for this investigation:

`AudioCapturePOC/SchedulerPOC/bin/Debug/net10.0/`

currently contains no `.wav` files.

Therefore Paso 5 timestamp analysis must not assume the presence of a scheduler WAV artifact
from that directory. The next evidence should be obtained directly from a fresh live
`whisper-server` response.

## Timestamp question to validate

Each POC7 scheduler job has an absolute capture position:

`InferenceJob.StartSeconds`

The `verbose_json` response from whisper-server contains timestamps relative to the uploaded
WAV window. Paso 5 must explicitly verify how those relative timestamps map to the scheduler's
absolute timeline before any production reconstruction integration is accepted.

The mapping must be demonstrated from actual server output; it must not be assumed.

## Constraints for Paso 5

- Do not modify `Build-WhisperWords.ps1` to accommodate whisper-server input.
- Do not modify `Reconstruct-WhisperWindows.ps1` merely to accommodate the server adapter.
- Keep `Convert-WhisperServer.ps1` as the ASR/import boundary.
- Do not silently change scheduler window geometry.
- Do not treat the current POC7 runs as evidence of real-time reconstruction continuity.
- Do not claim MATCH/DEDUP validation until repeated lexical content in overlapping windows has
  actually produced and been checked through reconstruction.
- Do not add Phase 2 LLM/question detection to this step.

## Next controlled action

The next code change should be limited to preserving the raw `verbose_json` response from
`RunInferenceAsync` so that the actual server timestamps can be inspected and subsequently
passed through the existing PowerShell adapter boundary.

That change must be built and tested independently before further integration work.
