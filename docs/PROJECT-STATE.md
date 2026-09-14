# Project State Checkpoint

**Branch:** `reconstruction-fixes`

**Repository:** `Drworm82/whisper-reconstruction-a3-audit`

**Last documented update:** 2026-09-14

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

**POC7 — Paso 7: siguiente etapa de integración/validación end-to-end**

La validación de audio real end-to-end tras la integración del guard temporal de MATCH ya fue realizada durante la caracterización y el cierre de POC7 Paso 6 (ver sección 14). POC7 Paso 6 no requiere otra modificación algorítmica; su implementación quedó congelada en `0bacc37` y su estado documental actual es `69864d4`.

Cualquier siguiente etapa debe partir de este estado congelado y documentado. El repositorio no documenta todavía un objetivo técnico concreto para Paso 7; esa definición queda pendiente de una decisión explícita.

### Limitaciones todavía abiertas

Cualquier siguiente etapa tampoco establece por sí sola:

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

## 14. POC7 — Paso 6: Deferred end-of-run preservation — STATUS: PASS / CLOSED

**Fecha de cierre documental:** 2026-09-14

El problema caracterizado era que los deferred creados durante un MATCH (palabras de la ventana actual que preceden al ancla seleccionado) podían quedar pendientes al terminar la última ventana y desaparecer al retornar de `Reconstruct-WhisperWindows`, descartándose silenciosamente sin aparecer en `finalWords`.

### 14.1 Solución implementada

La solución implementa un flush final condicional, ejecutado al terminar el recorrido de ventanas e inmediatamente antes de `return @($finalWords)`:

1. Recorre los deferred pendientes de forma determinista (orden `From`, `To`, `Id`).
2. Descarta entradas malformadas o sin texto útil (texto vacío o `Key` vacío).
3. Deriva la tolerancia temporal de la geometría de la transición que creó el deferred, usando el índice de ventana presente en su `Id`.
4. Para las ventanas reales usadas en la validación, la geometría es:

   * ventana: 5 s;
   * overlap: 4 s;
   * `driftAllowance = max(0.5, min(1.5, 4 * 0.2)) = 0.8 s`.
5. Si ya existe una representación equivalente por texto normalizado (minúsculas, sin espacios) y dentro de la tolerancia temporal en `From` y `To`, el deferred se descarta.
6. Si no existe representación equivalente, se inserta en orden cronológico según su `From`.
7. Se conservan sin modificación `Id`, `Text`, `From` y `To` de la ocurrencia insertada.
8. El flush no reutiliza el temporal MATCH guard; su responsabilidad es preservación/deduplicación al final de la reconstrucción.

### 14.2 Validación final sobre audio real

La validación ejecutó exactamente la implementación de `0bacc37` (flush end-of-run) contra el audio `tests/fixtures/real-course-test.wav`, con la entrada ASR cacheada (whisper.cpp `base.en`/Vulkan, una invocación por ventana de 5 s con paso de 1 s) reutilizada byte-idéntica a la caracterización histórica de 2026-09-11. El runner de diagnóstico solo lee el repositorio; todos los artefactos quedaron en `%TEMP%\opencode\`.

| Métrica                                   | Resultado |
| ----------------------------------------- | --------: |
| Ventanas usables                          |       121 |
| Transiciones                              |       120 |
| MATCH                                     |       114 |
| MATCH con `CurrentStart > 0`              |        36 |
| SIN MATCH                                 |        73 |
| Rechazos por temporal guard               |        67 |
| Deferred creados                          |        44 |
| Deferred recuperados durante transiciones |         0 |
| Pendientes antes del flush                |        44 |
| Descartados por dedup final               |        23 |
| Insertados por flush final                |        21 |
| Palabras finales OLD                      |       379 |
| Palabras finales NEW                      |       400 |
| Duplicados por identidad OLD/NEW          |     0 / 0 |
| IDs duplicados OLD/NEW                    |     0 / 0 |
| Violaciones de orden temporal OLD/NEW     |     0 / 0 |
| Timestamps alterados                      |         0 |
| `pending = discarded + inserted`          |      TRUE |

Consistencia contable del flush:

`44 = 23 + 21`

Incremento del resultado final producido exclusivamente por el flush:

`400 = 379 + 21`

### 14.3 Especificaciones A-D satisfechas en audio real

- **A — No duplicación:** 23 deferred descartados por representación equivalente; 0 duplicados de identidad añadidos por el flush.
- **B — Preservación de huérfanos:** 21 deferred insertados exactamente una vez; 0 IDs duplicados en el resultado final.
- **C — Orden cronológico:** 0 violaciones de orden temporal en el resultado final.
- **D — Preservación de timestamps:** 0 cambios en `From`/`To`, incluso para las palabras insertadas por el flush.

### 14.4 Relación con la caracterización histórica

El resultado real fue **23 descartados / 21 insertados** y NO debe confundirse con una predicción de la heurística histórica:

- La caracterización de 2026-09-11 usaba `From-only ±0.6 s` y producía 21 con representación / 23 sin representación.
- El runner posterior usa `From + To ±0.6 s` y produce 19 / 25.
- El algoritmo implementado usa la tolerancia derivada de la geometría real de la ventana: **0.8 s**.

Bajo esa tolerancia:

- los 21 con representación histórica fueron descartados;
- 21 de los 23 restantes fueron insertados;
- 2 casos adicionales quedaron dentro de la tolerancia de 0.8 s y fueron descartados.

Casos frontera:

- `35-1 "a"` frente a `35-4 "a"`: `dFrom = 0.670 s`.
- `98-0 "that's"` frente a `97-1 "that's"`: `dFrom = 0.800 s`, exactamente en el límite.

No debe afirmarse que los 21 insertados sean palabras lingüísticamente verdaderas. Son entradas que la política de reconstrucción decidió conservar porque no encontró una representación equivalente dentro de la tolerancia definida.

### 14.5 Falsa alarma del runner

El mensaje:

`inserted-position monotonicity: violations=2`

no representa una violación del algoritmo. Fue un artefacto del diagnóstico: esa comprobación ordenaba los IDs lexicográficamente, de modo que `11-0` y `12-0` aparecen después de `114-1` bajo orden textual. La comprobación temporal real, procesando inserciones por `From`, `To`, `Id`, produjo:

`orderViolations = 0`

No debe modificarse producción por esta falsa alarma.

### 14.6 Alcance y limitación residual

**Paso 6 — STATUS: PASS / CLOSED.**

La evidencia comprende:

- especificación A-D (tests `Reconstruct-WhisperWindows.DeferredEndOfRun.Spec.Tests.ps1` y validación en audio real);
- pruebas específicas de especificación y regresión temporal;
- validación final con audio real completo (121 ventanas);
- ausencia de regresión en las métricas de reconstrucción (MATCH, SIN MATCH y guard idénticos antes/después del flush);
- preservación de timestamps;
- deduplicación de representaciones equivalentes;
- orden cronológico;
- consistencia contable del flush (`44 = 23 + 21`, `400 = 379 + 21`).

Limitación/riesgo residual:

> La preservación de un deferred no implica que Whisper haya reconocido correctamente una palabra. La operación garantiza conservación y deduplicación conforme a la política algorítmica; la calidad lingüística de la salida de `base.en` sigue siendo un asunto separado.

### 14.7 Historial

- `0bacc37` — Implement deferred end-of-run preservation (implementación evaluada).
- `69864d4` — documentación/estado actual del cierre de Paso 6 (HEAD durante la validación final).
- Validación final: 121 ventanas, 44 deferred, 23 descartados, 21 insertados, 400 palabras finales, A-D OK.

Nota: durante la validación final el HEAD real fue `69864d4`, descendiente documental de `0bacc37`. La implementación evaluada es byte-idéntica a `0bacc37` (`git diff 0bacc37 HEAD -- src/` vacío). El label "HEAD 0bacc37" del runner de diagnóstico es obsoleto y no representa el HEAD real.
