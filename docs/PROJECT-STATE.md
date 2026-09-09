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
- Model tested: `ggml-base.en.bin`.
- Real test audio: `tests/fixtures/real-course-test.wav`.
- Duration: approximately 125 seconds.
- `whisper-cli.exe -ojf` produced token-level JSON timestamps.
- Token timestamps are available through `offsets.from` / `offsets.to` in milliseconds.
- Segment timestamps are formatted strings such as `00:00:00,000`.
- A real 125-second test produced 331 lexical/control-filtered token records before word grouping and 279 words after `Build-WhisperWords` in the current experiment.
- The JSON contained 17 `[_TT_nnn]` tokens in the inspected real file; all had zero duration and no additional text. It also contained `[_BEG_]` control tokens.
- These control/timestamp tokens must be excluded by the whisper.cpp adapter.

### WhisperX

WhisperX remains in the repository and has not been removed. Its existing adapter is `src/Import/Convert-WhisperX.ps1`.

## 4. Current whisper.cpp adapter

`src/Import/Convert-WhisperCpp.ps1` was added as the boundary adapter.

Responsibilities:

- Read whisper.cpp `-ojf` JSON.
- Validate required `transcription`, `timestamps`, `tokens`, `text`, and `offsets` fields.
- Convert segment timestamp strings to seconds.
- Convert token offsets from milliseconds to seconds.
- Preserve token leading whitespace because `Build-WhisperWords` uses it for word boundaries.
- Drop control/timestamp tokens matching `^\[_.*_\]$`.
- Reject inverted timestamps.

Initial implementation failure:

- The first implementation attempted `[int]` conversion of segment timestamps.
- Real whisper.cpp JSON uses strings such as `00:00:00,000` for segment timestamps.
- This caused the local error: `No se puede convertir el valor "00:00:00,000" al tipo "System.Int32"`.
- Fixed by adding explicit timestamp parsing.

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

### whisper.cpp adapter: validated locally through word construction

After `f4752e6`, the user synchronized the local branch to `8f66727` and ran the real whisper.cpp fixture locally.

Conversion command:

```powershell
$windowsCpp = Convert-WhisperCpp -Path ".\tests\fixtures\whispercpp-real-full.json"
```

Observed result:

- `17` windows produced.
- `331` total tokens produced.
- First windows had numeric second-based boundaries: `0 -> 5.6`, `5.6 -> 13.88`, `13.88 -> 20.2`.

The user then ran `Build-WhisperWords` over every converted window:

```powershell
$wordsCpp = @()
for ($i = 0; $i -lt $windowsCpp.Count; $i++) {
    $wordsCpp += @(Build-WhisperWords $windowsCpp[$i].Tokens $i)
}
```

Observed result:

- `279` words produced.
- This exactly matches the previously documented experiment for this fixture.
- Sample output showed numeric `From`/`To` timings and window-scoped word IDs, e.g. `normal 0.02 -> 0.5`, `economics 0.5 -> 1.23`, `in 1.23 -> 1.4`.

Conclusion for this phase:

`whisper.cpp -ojf JSON -> Convert-WhisperCpp -> Build-WhisperWords` is locally validated against the real 125-second fixture at the observed structural level.

This does **not** yet validate the full overlapping-window reconstruction path or five-hour continuous operation.

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

1. Validate the converted whisper.cpp windows through the existing windowing/reconstruction path.
2. Compare the resulting behavior against the established reconstruction invariants and regression expectations.
3. Only after successful reconstruction validation, evaluate what is still required for continuous real-time processing and five-hour course operation.
