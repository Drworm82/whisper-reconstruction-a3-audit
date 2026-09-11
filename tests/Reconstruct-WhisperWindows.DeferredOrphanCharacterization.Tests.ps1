Describe "Reconstruct-WhisperWindows deferred orphan characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "characterizes loss of a deferred word that is never recovered as an anchor" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 5.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' T0'; From=3.8; To=3.98 }
                    [PSCustomObject]@{ Text=' A';  From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' B';  From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' C';  From=4.4; To=4.6 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
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

        $output = @(& {
            Reconstruct-WhisperWindows $windows
        } 6>&1)

        $words = @(
            $output |
            Where-Object { $_.PSObject.Properties.Match('Id').Count }
        )

        $xWords = @($words | Where-Object { $_.Text -eq 'X' })

        # Characterization only: this is expected to FAIL until orphaned deferred
        # occurrences receive an explicit finalization policy.
        $xWords.Count | Should Be 1
    }
}
