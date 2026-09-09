# Project State Checkpoint

**Branch:** `reconstruction-fixes`

**Repository:** `Drworm82/whisper-reconstruction-a3-audit`

**Last documented update:** 2026-09-08

## 1. Current objective

Build a robust reconstruction pipeline for continuous transcription from overlapping Whisper/ASR audio windows, with enough temporal precision to detect questions and preserve context for a later assistant stage.

## 2. Architecture

Current conceptual flow:

`audio -> ASR -> import adapter -> Build-WhisperWords -> overlapping windows -> alignment/reconstruction -> continuous transcript -> question/context stage`

The ASR/import boundary is intentionally separated from reconstruction logic.

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

- `cc4bfe9` — Fix whisper.cpp control token filtering

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

The real whisper.cpp fixture was re-run after commit `cc4bfe9`.

Fresh conversion:

```powershell
$windowsCppClean = @(Convert-WhisperCpp -Path ".\tests\fixtures\whispercpp-real-full.json")
```

Observed result:

- `17` native windows produced.
- `0` control tokens remained in the converted window token collections when checked against `^\[_.*\]$`.

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

This is a correction to the earlier `279`-word observation: the earlier count included the 17 control tokens because the adapter's original regular expression failed to remove them.

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

### Local synchronization note

The initial `git pull origin reconstruction-fixes` was blocked because a pre-existing untracked local `AGENTS.md` would have been overwritten by the tracked repository version. The local file was moved to `AGENTS.local-backup.md`, the pull then completed as a fast-forward to `8f66727`, and no project source code was changed during this resolution.

## 7. Important constraints

- Do not modify `Build-WhisperWords.ps1` merely to accommodate whisper.cpp input.
- Do not modify `Reconstruct-WhisperWindows.ps1` merely to accommodate whisper.cpp input.
- Prefer an adapter at the ASR/import boundary.
- Do not remove WhisperX until the whisper.cpp path has been sufficiently compared and validated.
- Do not invent a test runner. Inspect `tests/` and run the actual scripts present.
- Do not delete untracked project artifacts without a specific reason and user approval.
- Every meaningful change must be documented and committed.

## 8. Immediate next step

1. Synchronize the documented adapter fix and validation results with the local branch.
2. Verify repository state and remote synchronization without staging unrelated untracked artifacts.
3. Continue comparing the whisper.cpp path against established reconstruction invariants before evaluating real-time and five-hour operation requirements.
