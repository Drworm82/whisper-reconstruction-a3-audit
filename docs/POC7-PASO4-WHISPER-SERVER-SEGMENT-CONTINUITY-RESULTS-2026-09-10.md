# POC7 Paso 4 — Whisper-server segment continuity and reconstruction validation

**Date:** 2026-09-10  
**Status:** PASS

## Objective

Validate the integration contract between the whisper-server `verbose_json` response,
`Convert-WhisperServer`, `Build-WhisperWords`, and `Reconstruct-WhisperWindows`.

The specific defect under investigation was that the whisper-server adapter returned one
reconstruction Window per internal `segments[]` entry. This was incompatible with the POC7
runtime contract, where one scheduler/inference job represents one audio Window and the HTTP
response may contain multiple whisper-server segments.

## Evidence fixture

Primary regression fixture:

`AudioCapturePOC/poc7-language-es-turbo.json`

The fixture contains:

- 4 whisper-server `segments`.
- 45 lexical token units across those segments.
- Segment envelope: `0.000 s -> 14.680 s`.

## Defect reproduced before the fix

Before the adapter correction:

- `Convert-WhisperServer` returned 4 Windows for the single HTTP response.
- The first Window ended at `3.900 s`.
- Running `Build-WhisperWords` independently per server segment split words across
  segment boundaries, producing fragments such as `facult ad`,
  `administr ación`, and other incorrect word boundaries.
- Reconstruction therefore did not receive the complete token stream as one Window.

This established that the problem was in the adapter's Window construction rather than in
`Build-WhisperWords` or `Reconstruct-WhisperWindows`.

## Implementation change

`src/Import/Convert-WhisperServer.ps1` was changed so that:

1. All `segments[].words[]` lexical units are accumulated into one ordered token array.
2. The first server segment establishes the Window start.
3. The final server segment establishes the Window end.
4. The adapter returns exactly one `{ Start, End, Tokens }` Window per HTTP response.
5. The adapter does not call `Build-WhisperWords`.
6. Existing validation for invalid, negative, inverted, and whitespace-only units remains
   in place.

No changes were made to:

- `src/Import/Convert-WhisperCpp.ps1`
- `src/Words/Build-WhisperWords.ps1`
- `src/Reconstruction/Reconstruct-WhisperWindows.ps1`

## Formal regression test

Test:

`tests/Convert-WhisperServer.SegmentContinuity.Tests.ps1`

Pester result after the fix:

```text
Passed: 3
Failed: 0
Skipped: 0
Pending: 0
Inconclusive: 0
``text

The regression contract verifies:

exactly 1 Window is returned;
exactly 45 token units are preserved;
the complete expected Spanish text is preserved;
Window start is 0.000 s;
Window end is 14.680 s.
Adapter -> Build -> Reconstruction validation

The corrected integration was also executed manually with all four required components
loaded:

Convert-WhisperServer
Build-WhisperWords
Find-WordOverlap
Reconstruct-WhisperWindows

Observed result:

Windows: 1
Token units: 45
Reconstructed words: 26
Empty words: 0
Invalid timings: 0

Reconstructed text:

a través del programa universitario de gobierno, la facultad de economía y las facultades de contaduría y administración, ciencias políticas y sociales, derecho, filosofía y letras.

The reconstructed text matched the expected complete Spanish transcript.

Result

POC7 Paso 4 — PASS.

The whisper-server adapter now preserves segment continuity by mapping one HTTP
verbose_json response to one normalized reconstruction Window while retaining all lexical
token units in order.

This validates the adapter-to-word-construction-to-reconstruction contract on the Spanish
turbo fixture.

Remaining validation

This PASS does not establish:

multiple independent real whisper-server responses through the corrected adapter in the
live POC7 runtime;
queue saturation or final overflow policy;
final real-time reconstruction behavior across repeated overlapping windows;
watchdog/restart behavior;
device reconnection;
end-to-end latency target;
long-duration soak behavior;
final production window geometry;
Phase 2 LLM/question detection.

The next validation step is therefore live POC7 end-to-end execution using the corrected
Convert-WhisperServer adapter.
