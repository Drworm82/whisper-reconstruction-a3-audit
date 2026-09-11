# Project State Checkpoint

**Branch:** `reconstruction-fixes`

**Repository:** `Drworm82/whisper-reconstruction-a3-audit`

**Last documented update:** 2026-09-10

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
- Models available include `ggml-base.en.bin` and `ggml-large-v3-turbo-q5_0.bin`.
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
- Drop control/timestamp tokens matching `^\\[_.*\\]$`.
- Reject inverted timestamps.

### Control-token filtering fix

The adapter initially used the incorrect pattern `^\\[_.*_\\]$`. Real whisper.cpp control tokens such as `[_TT_280]` do not contain an underscore immediately before the closing bracket, so that pattern failed to match them. The adapter was corrected to `^\\[_.*\\]$`.

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

**POC7 — Paso 7: real audio end-to-end validation after MATCH temporal guard integration**

POC7 Paso 1, Paso 2, Paso 3, Paso 4, Paso 5 y la corrección del Paso 6 están implementados y cuentan con validaciones locales específicas. La siguiente prueba debe ejercitar nuevamente el audio WASAPI real con el flujo completo y observar explícitamente `Convert -> Build -> Reconstruct` usando el guard temporal integrado.

La batería de regresión ejecutada antes de esta etapa obtuvo:

- `Find-WordOverlap.TemporalPlacement.Tests.ps1`: **2/2 PASS**.
- `Integration.Reconstruct-WhisperWindows.Tests.ps1`: **PASS**, 3/3 MATCH, 21 palabras, texto esperado exacto.
- `Integration.RealisticTranscript.Tests.ps1`: **4/4 PASS**, 117 palabras, sin bloques repetidos y overlap de 10 palabras.
- `Integration.Pipeline.Tests.ps1`: **PASS**, 138 palabras; la prueba tolera explícitamente transiciones `SIN MATCH` y valida continuidad de ejecución y resultado no vacío.

### Paso 7 — alcance de la próxima ejecución

Usar el harness existente:

`AudioCapturePOC/EndToEndPOC/Program.cs`

Configuración experimental preservada:

- WASAPI Loopback.
- 48 kHz, 2 canales, IEEE Float.
- Ring buffer de 20 s.
- Ventanas de 5 s.
- Overlap de 1 s.
- Paso de 4 s.
- Cola de capacidad 3 con `DropOldest` como política experimental.
- `whisper-server` persistente en `http://127.0.0.1:8080/inference`.
- `verbose_json`.
- Conversión mediante `Convert-WhisperServer.ps1`.
- Offset global aplicado fuera del adapter usando `job.StartSeconds`.
- `Build-WhisperWords`.
- `Find-WordOverlap` integrado con guard temporal.
- `Reconstruct-WhisperWindows` sobre las ventanas exitosas juntas.

El harness actual ya implementa este flujo y guarda el JSON crudo por ventana para inspección posterior. fileciteturn267file0

### Evidencia previa de Paso 5

Existe una ejecución end-to-end anterior que validó 3 ventanas reales con HTTP 200, conversión correcta y reconstrucción de 30 palabras, con `0` IDs duplicados y orden temporal correcto. Esa evidencia corresponde a la ejecución documentada en `docs/POC7-PASO5-CONVERT-BRIDGE-VALIDATION-2026-09-10.md`. fileciteturn275file0

### Limitaciones todavía abiertas

La próxima ejecución tampoco establece por sí sola:

- calidad lingüística suficiente para conversación arbitraria;
- geometría final de producción;
- política definitiva de overflow bajo saturación real;
- watchdog/reinicio de `whisper-server`;
- reconexión de dispositivo de audio;
- soak test de larga duración;
- latencia end-to-end objetivo para UX;
- integración de LLM de Fase 2.

## 10. POC4 result - WASAPI Loopback + ring buffer + audio scheduler

POC4 validated the audio capture/scheduler layer using WASAPI Loopback, a 20-second ring buffer, and overlapping scheduler windows.

Configuration:

| Parameter | Value |
|---|---:|
| Capture | WASAPI Loopback |
| Sample rate | 48,000 Hz |
| Channels | 2 |
| Format | 32-bit IEEE Float |
| Bytes per frame | 8 |
| Ring buffer | 20 s |
| Test duration | 15 s |
| Window | 5 s |
| Overlap | 1 s |
| Step | 4 s |

Observed result:

- Window `#0`: `0.000-5.000 s` - `1,920,000` bytes.
- Window `#1`: `4.000-9.000 s` - `1,920,000` bytes.
- Window `#2`: `8.000-13.000 s` - `1,920,000` bytes.
- Frames captured: `720,960`.
- Bytes captured: `5,767,680`.
- Calculated duration: `15.020 s`.
- Ring-buffer dropped frames: `0`.
- All three window sizes: `OK`.

The scheduler termination was corrected to use the actual WASAPI `RecordingStopped` event/state rather than requiring exactly 15 seconds of captured frames.

**Status:** POC4 WASAPI scheduler **PASS**.

The POC validates capture, ring-buffer retention, overlapping window generation, expected window sizing, and clean termination. It does not validate ASR inference, inference-queue saturation, continuous reconstruction, watchdog behavior, or long-duration operation.

Commit:

- `0218fac` - Add WASAPI scheduler POC4

Detailed results are documented in `docs/POC4-WASAPI-SCHEDULER-RESULTS-2026-09-09.md`.

## 11. POC5 result — scheduler + whisper-server structural integration

The scheduler-generated windows `0-5s`, `4-9s`, and `8-13s` were processed sequentially through the persistent whisper-server, converted with `Convert-WhisperServer`, normalized with `Build-WhisperWords`, and evaluated through `Reconstruct-WhisperWindows`.

Observed result:

- `17` normalized token units across the three windows.
- `13` constructed words.
- `13` reconstructed words.
- `0` words lost by count.
- `13` unique reconstructed IDs.
- `0` duplicate IDs.
- Temporal-order check: `True`.
- Both reconstruction transitions were `SIN MATCH`.

The two `SIN MATCH` results are not considered evidence of a reconstruction defect. The actual ASR outputs did not contain sufficient common lexical content in the physical overlap intervals to form a match: window 0 ended with a music marker around `4-5s` while window 1 began with punctuation/`upbeat`, and window 1's recognized content ended around `6.57s`, leaving no recognized content in the `8-9s` overlap with window 2.

**Status:** POC5 structural integration **PASS**. Real overlap MATCH/deduplication with repeated speech remains **NOT YET VALIDATED**.

Detailed results are documented in `docs/POC5-SCHEDULER-WHISPER-SERVER-INTEGRATION-RESULTS-2026-09-09.md`.

## 12. POC6 result — bounded inference queue

The bounded inference-queue mechanics were validated in isolation before proceeding to POC7.

Configuration:

| Parameter | Value |
|---|---:|
| Queue capacity | 3 jobs |
| Producer interval | 100 ms |
| Consumer processing time | 500 ms/job |
| Test

## 13. POC7 — previous implementation checkpoints

The repository contains detailed Paso 1-6 documentation under `docs/`. The current live-audio next step supersedes the older text below and is retained here as historical checkpoint material.

### Paso 1

WASAPI Loopback, ring buffer, and scheduler were validated with real audio at 48 kHz/2ch/32-bit IEEE Float using 5 s windows, 1 s overlap, and 4 s step.

### Paso 2

Bounded inference queue mechanics were validated under non-saturated load, with capacity 3 and 500 ms simulated processing.

### Paso 3

The persistent whisper-server was exercised from scheduled audio windows.

### Paso 4

`Convert-WhisperServer` was corrected to aggregate all segments of one HTTP response into a single logical Window before `Build-WhisperWords`.

### Paso 5

The real ASR bridge `WASAPI -> scheduler -> queue -> whisper-server -> Convert -> Build -> Reconstruct` was integrated and previously validated locally with 3 windows, 30 reconstructed words, 0 duplicate IDs, and temporal order OK. fileciteturn275file0

### Paso 6

A temporal MATCH placement inversion was reproduced using real JSON from overlapping audio windows. The problematic candidate had previous anchor `in @ 4.86s` and current anchor `in @ 4.00s`, producing one temporal regression before the guard. The guard was first validated experimentally and then integrated into `Find-WordOverlap.ps1`.

Post-integration validation on the same real JSON produced:

- `ORDER VIOLATIONS: 0`;
- `DUPLICATE IDS: 0`;
- `FINAL WORD COUNT: 31`;
- regression test: **2/2 PASS**;
- historical reconstruction integration: **PASS**;
- realistic continuous transcript integration: **4/4 PASS**;
- pipeline integration: **PASS** with 138 words.

The detailed Step 6 record is `docs/POC7-PASO6-MATCH-GUARD-VALIDATION-2026-09-10.md`. fileciteturn268file0

The next proof required is therefore the **live-audio end-to-end run with the integrated guard**, not another synthetic fixture or a second reconstruction algorithm change.
