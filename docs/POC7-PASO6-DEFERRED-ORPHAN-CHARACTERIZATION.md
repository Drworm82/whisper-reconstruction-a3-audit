# POC7 — Paso 6: Deferred orphan characterization

## Status

Characterization only. No production fix is proposed by this document.

## Finding

The current reconstruction algorithm can silently lose a word that is placed in `$deferredWordsByText` but is never subsequently recovered.

This is a real behavior of the current control flow. It is **not** a demonstrated production-frequency problem yet.

## Minimal observed transition

Fixture:

```text
W0: T0 X A B C
W1: Y  A B C D
```

Relevant timings:

```text
W0: T0 3.7-3.9
    X  4.0-4.2
    A  4.2-4.4
    B  4.4-4.6
    C  4.6-4.8

W1: Y  4.0-4.2
    A  4.2-4.4
    B  4.4-4.6
    C  4.6-4.8
    D  8.0-8.3
```

The matcher accepts the contiguous `A B C` block:

```text
PreviousStart    = 1
CurrentStart     = 1
Matches           = 3
```

Therefore the accepted MATCH path constructs:

```text
prefix      = T0 X
currentMatch = A B C
after       = D
```

and stores `Y` as deferred because it precedes `CurrentStart` in the current overlap:

```text
$deferredWordsByText['y'] = Y
```

The resulting `finalWords` are:

```text
T0 X A B C D
```

`X` is retained normally through the accumulated prefix. It is **not** deferred, recovered, aliased, or inserted by `Add-NewWordsWithTiming` in this transition.

## Control-flow conclusion

`Add-NewWordsWithTiming` and the SIN MATCH branch are not involved in this fixture because the MATCH is accepted.

The deferred lifecycle has an entry path for words before `$match.CurrentStart`, but its only demonstrated exit path is later recovery when a subsequent transition reaches the deferred word through the anchor-resolution logic.

If no later transition recovers the deferred occurrence, it remains in `$deferredWordsByText` and disappears when the reconstruction function terminates.

Thus the behavior is a **silent deferred-word loss**.

## Temporal guard interaction

The temporal placement guard does not cause this loss in the observed fixture.

The relevant boundary is exact:

```text
$currentMatch[0].From = 4.2
$prefix[-1].To       = 4.2
```

The guard rejects only when:

```text
$currentMatch[0].From -lt $prefix[-1].To
```

so `4.2 < 4.2` is false and the MATCH is accepted.

This equality is diagnostically important: a small timing displacement could instead cause temporal rejection and route the transition through SIN MATCH. Therefore this synthetic fixture must not be treated as representative of Whisper timing jitter without real capture evidence.

## What this proves

### Proven by code trace and characterization

- A word can enter `$deferredWordsByText` when an accepted MATCH has `CurrentStart > 0`.
- In this fixture, `Y` is the deferred word.
- `X` survives because it is part of the accumulated prefix.
- `A`, `B`, and `C` enter through `currentMatch`.
- `D` enters through `after`.
- SIN MATCH, alias mapping, and `Add-NewWordsWithTiming` are not responsible for the observed result.
- The deferred `Y` has no recovery within the two-window fixture and is therefore not emitted in `finalWords`.

### Not proven yet

- That deferred orphaning occurs frequently in real POC7/Whisper data.
- That Whisper's actual `Start`/`End` jitter produces this exact pattern often enough to affect reconstruction quality materially.
- Which ASR witness (`X` or `Y`) is semantically correct when two overlapping windows disagree at the same time interval.

A third-window fixture can demonstrate permanent non-recovery geometrically, but production impact still requires real POC7 capture/ASR evidence.

## Terminology correction

For this characterization:

```text
X = accumulated prefix word
Y = deferred word
```

Earlier discussion that described `X` as the deferred word was incorrect for this fixture.

## Architectural implication

The current deferred mechanism behaves as a temporary recovery cache rather than a guaranteed-lossless reconciliation queue. There is no finalization step that promotes unrecovered deferred words into the output or explicitly reports them as unresolved.

No fix is proposed yet. The next investigation should determine whether real POC7 data contains deferred words that remain unrecovered and whether those words correspond to genuine transcript loss.

## Evidence

Independent audit of the current reconstruction control flow, together with the synthetic characterization fixture and its observed output:

```text
FINAL COUNT=6
FINAL id=0-0 text='T0' from=3.7 to=3.9
FINAL id=0-1 text='X' from=4 to=4.2
FINAL id=1-1 text='A' from=4.2 to=4.4
FINAL id=1-2 text='B' from=4.4 to=4.6
FINAL id=1-3 text='C' from=4.6 to=4.8
FINAL id=1-4 text='D' from=8 to=8.3
```

The characterization test itself is intentionally not treated as a regression test for a future fix; it documents the current behavior and should remain separate from any eventual remediation test.
