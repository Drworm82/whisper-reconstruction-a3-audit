# Project State Checkpoint

**Branch:** `reconstruction-fixes`

**Repository:** `Drworm82/whisper-reconstruction-a3-audit`

**Last documented update:** 2026-09-09

## 1. Current objective

Build a robust reconstruction pipeline for continuous transcription from overlapping Whisper/ASR audio windows, with enough temporal precision to detect questions and preserve context for a later assistant stage.

## 2. Architecture

Current conceptual flow:

`audio capture -> ASR -> import adapter -> Build-WhisperWords -> overlapping windows -> alignment/reconstruction -> continuous transcript -> question/context stage`

The ASR/import boundary is intentionally separated from reconstruction logic.

Audio capture is now being evaluated as a separate subsystem. OBS is not yet considered a mandatory dependency. See `docs/AUDIO-CAPTURE-ARCHITECTURE.md` for the current investigation and decision status.

## 3. ASR investigation

### whisper.cpp

- Installed at `C:\whisper.cpp` in the user's Windows environment.
- GPU: AMD Radeon RX 6600 XT.
- Backend observed: Vulkan.
- Model tested: `ggml-base.base.en.bin`.
- Real test audio: `tests/fixtures/real-course-test.wav`.
- Duration: approximately 125 seconds.
- `whisper-cli.exe -ojf` produced token-level JSON timestamps.
- Token timestamps are available through `offsets.from` / `offsets.to` in milliseconds.
- Segment timestamps are formatted strings such as `00:00:00,000`.
- The real fixture contains 331 token records in the whisper.cpp JSON, including 17 zero-duration `[_TT_nnn]` control/timestamp tokens inspected during adapter validation.
- These control/timestamp tokens must be excluded by the whisper.cpp adapter.

### WhisperX

WhisperX remains in the repository and has not been removed. Its existing adapter is `src/Import/Convert-WhisperX.ps1`.

## 4. Current whisper.cpp adapter

`src/Import/Convert-WhisperCpp.ps1` is the boundary adapter.

Responsibilities:

- Read whisper.cpp `-ojf` JSON.
- Validate required `transcription`, `timestamps`, `tokens`, `text`, and `offsets` fields.
- Convert segment timestamp strings to seconds.
- Convert token offsets from milliseconds to seconds.
- Preserve token leading whitespace because `Build-WhisperWords` uses it for word boundaries.
- Drop control/timestamp tokens matching `^\[_.*\]$`.
- Reject inverted timestamps.

### Control-token filtering fix

The adapter initially used the incorrect pattern `^\[_.*_\]$`. Real whisper.cpp control tokens such as `[_TT_280]` do not contain an underscore immediately before the closing bracket, so that pattern failed to match them. The adapter was corrected to `^\[_.*\]$`.

Commit:

- `ce7a64f` — Fix whisper.cpp control token filtering

No changes were made to `Build-WhisperWords.ps1`, `New-WhisperWindows.ps1`, or `Reconstruct-WhisperWindows.ps1` for this fix.

### Earlier adapter work

Relevant commits:

- `b3671d7` — Add whisper.cpp JSON adapter
- `dd0c7ed` — Load whisper.cpp adapter
- `f4752e6` — Fix whisper.cpp segment timestamp parsing
- `94d6081` — Add persistent project operating rules
- `8f66727` — Add persistent project state checkpoint

## 5. Reconstruction status

Previously validated reconstruction fixes must be preserved. The project has a suite of 23 relevant tests that were run locally and all passed before the whisper.cpp adapter work.

Important validated fixes include:

- SIN MATCH state preservation
- window-boundary word assignment
- empty-key false-match prevention
- key-collision match selection
- timing-drift correction in SIN MATCH deduplication
- transitive deduplication across omitted windows
- Issue 6 deferred MATCH-anchor state
- Issue 1 E1 alias preservation after SIN MATCH

The user previously ran `Test-NoMatchThenMatch.Tests.ps1` successfully after the Issue 6 regression correction.

## 6. Current validation status

### whisper.cpp adapter: locally validated through overlapping reconstruction

The real whisper.cpp fixture was re-run after commit `ce7a64f`.

Fresh conversion:

```powershell
$windowsCppClean = @(Convert-WhisperCpp -Path ".\\tests\\fixtures\\whispercpp-real-full.json")
```

Observed result:

- `17` native windows produced.
- `0` control tokens remained in the converted window token collections when checked against `^\\[_.*\\]$`.

Word construction:

```powershell
$wordsCppClean = @()
for ($i = 0; $i -lt $windowsCppClean.Count; $i++) {
    $wordsCppClean += @(Build-WhisperWords $windowsCppClean[$i].Tokens $i)
}
```

Observed result:

- `274` words produced.
- `0` words contained `[_TT_nnn]` markers.

Overlapping window construction used the already-established test parameters:

```powershell
$overlapCppClean = @(New-WhisperWindows -Words $wordsCppClean -WindowDurationSeconds 10 -OverlapDurationSeconds 4)
```

Observed result:

- `21` overlapping windows produced.

Reconstruction:

```powershell
$resultCppClean = @(Reconstruct-WhisperWindows $overlapCppClean)
```

Observed result:

- `274` reconstructed words.
- `274` input words.
- `0` words lost by count comparison.
- One `SIN MATCH` was observed at the `96.02s -> 102.02s` transition.
- Final reconstructed sequence had `0` temporal-order violations (`From` never decreased).
- Final reconstructed sequence contained `0` `[_TT_nnn]` markers.

Conclusion:

`whisper.cpp -ojf JSON -> Convert-WhisperCpp -> Build-WhisperWords -> New-WhisperWindows (10s/4s) -> Reconstruct-WhisperWindows` is locally validated against the real approximately 125-second fixture at the current structural/reconstruction level.

This does **not** yet validate real-time streaming, sustained five-hour operation, or production-scale performance.

### Audio capture investigation: OBS is not currently mandatory

The product being used as the functional reference is ParakeetAI at `https://www.parakeet-ai.com/`. Its public product description establishes real-time desktop transcription/assistance behavior, but does not establish which Windows capture API it uses internally.

The current technical investigation found:

- Windows provides native WASAPI loopback capture of rendered output audio; this does not require a third-party virtual audio driver.
- NAudio exposes WASAPI loopback capture through its recorder API, allowing captured audio to be delivered to application code rather than waiting for a completed recording file.
- A two-minute recording block is therefore not an inherent two-minute ASR latency. Such latency would depend on a file-based integration that waits for the block to complete.
- The session recording requirement and low-latency ASR requirement can be separated by fanning out the captured stream: one consumer persists the full session and another feeds a short ASR buffer.
- OBS remains useful as an optional diagnostic/reference recorder, but it is not currently justified as a mandatory intermediary between Windows audio and whisper.cpp.
- Windows also provides Application Loopback for process-specific audio capture; this is a future option, not yet the selected design.
- Device-change/reconnection behavior remains an explicit proof-of-concept requirement.

These are research findings, not yet implementation validation. No measured end-to-end capture latency has been established.

The full investigation is documented in `docs/AUDIO-CAPTURE-ARCHITECTURE.md`.

Documentation commits:

- `771947f` — Document direct audio capture and OBS decision
- `a70ea51` — Update project state with audio capture findings
- `1df89d3` — Correct documented whisper.cpp control-token regex

## 7. Local synchronization note

The initial `git pull origin reconstruction-fixes` was blocked because a pre-existing untracked local `AGENTS.md` would have been overwritten by the tracked repository version. The local file was moved to `AGENTS.local-backup.md`, the pull then completed as a fast-forward to `8f66727`, and no project source code was changed during this resolution.

The later documentation update was rebased locally and the resulting code commit became `ce7a64f`; that commit was pushed to `origin/reconstruction-fixes` successfully.

## 8. Important constraints

- Do not modify `Build-WhisperWords.ps1` merely to accommodate whisper.cpp input.
- Do not modify `Reconstruct-WhisperWindows.ps1` merely to accommodate whisper.cpp input.
- Prefer an adapter at the ASR/import boundary.
- Do not remove WhisperX until the whisper.cpp path has been sufficiently compared and validated.
- Do not invent a test runner. Inspect `tests/` and run the actual scripts present.
- Do not delete untracked project artifacts without a specific reason and user approval.
- Every meaningful change must be documented and committed.
- Do not treat OBS as mandatory until the direct WASAPI/NAudio proof of concept has been evaluated.
- Keep the complete session recording independent of live ASR/reconstruction/AI success during experimental use.

## 9. Immediate next step

1. Build a small NAudio + WASAPI Loopback proof of concept.
2. Persist the complete captured session while simultaneously exposing PCM data to a short ASR buffer.
3. Measure capture-to-text latency with controlled audio rather than inferring latency from recording block size.
4. Test behavior when the Windows default playback device changes or disappears.
5. Test sustained capture and simultaneous recording/ASR under a realistic class/meeting workload.
6. After the POC, decide whether OBS has any continuing production role and document the final capture architecture.
7. Continue comparing the whisper.cpp path against established reconstruction invariants before evaluating five-hour operation requirements.
8. Add or run a focused regression test for whisper.cpp control-token filtering if the existing test suite does not already cover it.
