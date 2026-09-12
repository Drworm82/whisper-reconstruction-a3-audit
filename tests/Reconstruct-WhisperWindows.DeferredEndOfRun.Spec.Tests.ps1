# ============================================================
# DeferredWordsByText — End-of-run finalization SPEC
# ============================================================
# Purpose
#
# This file EXPRESSES the future specification for words left pending in
# $deferredWordsByText when Reconstruct-WhisperWindows terminates. It does
# NOT implement any solution: no flush, no production change.
#
# Audit basis (commit 08dff04):
#   - $deferredWordsByText is local to Reconstruct-WhisperWindows.
#   - An unrecovered deferred occurrence is excluded from $finalWords and,
#     because no final flush exists, disappears when the function returns.
#   - Real-audio run: 44 deferred created / 0 recovered / 44 pending.
#
# Invariant under specification:
#   For every deferred occurrence pending at end of run:
#     A) if its content is ALREADY represented in $finalWords by another
#        equivalent occurrence, no second representation may be produced;
#     B) if its content is NOT represented in $finalWords, exactly ONE
#        representation must be preserved, in correct chronological place;
#     C) the result must stay chronologically ordered;
#     D) behavior of already-correctly-represented words must not change.
#
# Expected outcome against the CURRENT implementation:
#   - Redundant-pending case (A): PASSES, because discarding incidentally
#     keeps a single representation. A blind flush would violate it.
#   - Orphaned-pending case    (B): FAILS  with "Expected: {1} But was: {0}",
#     demonstrating precisely that the pending occurrence is discarded.

Describe "Reconstruct-WhisperWindows end-of-run deferredWordsByText specification" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "spec A: keeps ONE representation when the pending deferred content is redundant" {
        # W1 repeats W0's content 'P' inside the overlap. The accepted MATCH
        # selects A as anchor (CurrentStart=1), so W1's 'P' is deferred and is
        # never formally recovered by later transitions. W0's 'P', however, is
        # already in $finalWords through the accumulated prefix, so the content
        # is represented exactly once already.
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 6.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' P'; From=3.6; To=3.9 }
                    [PSCustomObject]@{ Text=' A'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' B'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' C'; From=4.4; To=4.6 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' P'; From=3.9; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                    [PSCustomObject]@{ Text=' E'; From=8.3; To=8.6 }
                    [PSCustomObject]@{ Text=' F'; From=8.6; To=8.8 }
                )
            }
            [PSCustomObject]@{
                Start = 8.0
                End   = 13.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                    [PSCustomObject]@{ Text=' E'; From=8.3; To=8.6 }
                    [PSCustomObject]@{ Text=' F'; From=8.6; To=8.9 }
                    [PSCustomObject]@{ Text=' G'; From=9.0; To=9.2 }
                )
            }
        )

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        $messages = @($output | ForEach-Object {
            $v = $_
            if ($v -is [System.Management.Automation.InformationRecord]) {
                $d = $v.MessageData
                if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }
                $v = $d
            }
            if ($v -is [string]) { $v }
        })
        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })

        # The deferred occurrence was never formally recovered: its only legal
        # re-entry path is the deferred-anchor recovery, which did not fire.
        @($messages | Where-Object { $_ -like 'RECUPERADO ANCLA DIFERIDA:*' }).Count | Should Be 0

        # Invariant A: a redundant pending deferred must not produce a second
        # representation. A blind flush of the pending bucket would turn this
        # count into 2 and fail here.
        @($words | Where-Object { $_.Text.Trim() -eq 'P' }).Count | Should Be 1

        # Invariant C: the result remains chronologically ordered.
        $ordered = $true
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ([double]$words[$i].From -lt [double]$words[$i - 1].From) { $ordered = $false }
        }
        $ordered | Should Be $true
    }

    It "spec B: preserves the orphaned pending occurrence exactly once, positioned chronologically (expected to FAIL on the current implementation)" {
        # Same geometry as the redundant case, but W0 does NOT contain 'P'.
        # The accepted MATCH defers W1's 'P' (CurrentStart=1) and no later
        # transition recovers it. Because no other occurrence of this content
        # exists in $finalWords, invariant B demands that the pending 'P'
        # survive exactly once, placed between 'Q' and 'A'.
        #
        # Current implementation discard: no final flush, so 'P' is absent
        # from the transcript and this block fails. The failure ("Expected:
        # Q,P,A,B,C,D,E,F,G But was: Q,A,B,C,D,E,F,G") is the specification
        # violation this test is meant to pin before production is touched.
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 6.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Q'; From=3.6; To=3.9 }
                    [PSCustomObject]@{ Text=' A'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' B'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' C'; From=4.4; To=4.6 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' P'; From=3.9; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                    [PSCustomObject]@{ Text=' E'; From=8.3; To=8.6 }
                    [PSCustomObject]@{ Text=' F'; From=8.6; To=8.8 }
                )
            }
            [PSCustomObject]@{
                Start = 8.0
                End   = 13.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                    [PSCustomObject]@{ Text=' E'; From=8.3; To=8.6 }
                    [PSCustomObject]@{ Text=' F'; From=8.6; To=8.9 }
                    [PSCustomObject]@{ Text=' G'; From=9.0; To=9.2 }
                )
            }
        )

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        $messages = @($output | ForEach-Object {
            $v = $_
            if ($v -is [System.Management.Automation.InformationRecord]) {
                $d = $v.MessageData
                if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }
                $v = $d
            }
            if ($v -is [string]) { $v }
        })
        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })

        # No formal recovery fired: the occurrence stayed pending.
        @($messages | Where-Object { $_ -like 'RECUPERADO ANCLA DIFERIDA:*' }).Count | Should Be 0

        # Invariant B: expected chronological transcript, single representation.
        $transcript = @($words | ForEach-Object { $_.Text.Trim() }) -join ','
        $transcript | Should Be 'Q,P,A,B,C,D,E,F,G'

        # Invariant C: whatever is present stays ordered.
        $ordered = $true
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ([double]$words[$i].From -lt [double]$words[$i - 1].From) { $ordered = $false }
        }
        $ordered | Should Be $true
    }
}