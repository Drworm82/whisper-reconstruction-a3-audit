# POC7 Paso 6 — Temporal MATCH boundary integration

**Date:** 2026-09-10  
**Branch:** `reconstruction-fixes`

## Objective

Move temporal MATCH validation away from the lexical characterization of `Find-WordOverlap` and validate the selected anchor against the accumulated reconstruction prefix during a production reconstruction call.

## Evidence before the change

The direct characterization tests passed 2/2 for both the valid real-jitter shape and the historical temporal regression.

The first production-level integration attempt failed 2/2:

- valid jitter case returned 15 words instead of the expected 16;
- historical regression did not produce the expected `SIN MATCH` path.

This showed that the previous temporal guard was intercepting the lexical matcher before reconstruction could apply the accumulated-prefix boundary.

## Implemented change

`Find-WordOverlap.ps1` now returns the selected lexical MATCH normally for standalone calls. During a production reconstruction call, it can inspect the caller's accumulated `$finalWords` state and validate the selected anchor against the word immediately preceding the matched accumulated anchor.

The rejection condition is:

```text
current MATCH start < accumulated prefix boundary
```

A valid equality at the boundary is accepted:

```text
current MATCH start == accumulated prefix boundary
```

The existing `Reconstruct-WhisperWindows` null-MATCH path remains responsible for the subsequent `SIN MATCH` reconstruction behavior.

## Test changes

`tests/Find-WordOverlap.TemporalPlacement.Tests.ps1` was converted to lexical-alignment coverage. It now verifies that `Find-WordOverlap` itself returns a lexical MATCH even when its current anchor begins earlier than the previous anchor. Temporal rejection is covered at reconstruction integration level instead.

`tests/Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1` exercises the actual `Reconstruct-WhisperWindows` function with deterministic synthetic windows for:

1. valid real-jitter MATCH at the accumulated prefix boundary;
2. historical temporal regression where the current MATCH begins before the accumulated prefix boundary.

## Validation status

The production change has been committed but has **not yet been locally revalidated after the latest code changes**.

The next local validation must run:

```powershell
git pull --rebase origin reconstruction-fixes

Invoke-Pester .\tests\Find-WordOverlap.TemporalPlacement.Tests.ps1
Invoke-Pester .\tests\Find-WordOverlap.TemporalPlacementBoundary.Tests.ps1
Invoke-Pester .\tests\Reconstruct-WhisperWindows.TemporalBoundaryCharacterization.Tests.ps1
Invoke-Pester .\tests\Reconstruct-WhisperWindows.TemporalBoundaryIntegration.Tests.ps1
```

No audio capture or whisper-server is required for these tests.

## Architectural note

This is an incremental migration toward reconstruction-owned temporal validation. The current implementation uses caller-scope access from the alignment function as a narrow compatibility seam because `Reconstruct-WhisperWindows` has not yet been structurally refactored into a reusable MATCH/SIN-MATCH helper. The behavioral contract is now tested at the reconstruction boundary.
