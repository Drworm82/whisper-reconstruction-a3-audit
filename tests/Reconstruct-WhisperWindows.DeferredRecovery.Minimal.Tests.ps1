Describe "minimal deferred recovery characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "recovers a unique deferred prefix occurrence" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 9.0
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
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 10.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                )
            }
        )

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        $messages = @($output | Where-Object { $_ -is [string] })
        $words = @($output | Where-Object { $_.PSObject.Properties['Text'] })

        @($messages | Where-Object { $_ -eq 'RECUPERADO ANCLA DIFERIDA: ''X''' }).Count | Should Be 1
        @($messages | Where-Object { $_ -eq 'MATCH REJECTED BY TEMPORAL PLACEMENT GUARD' }).Count | Should Be 0
        @($messages | Where-Object { $_ -eq 'SIN MATCH' }).Count | Should Be 0
        @($words | Where-Object { $_.Text -eq ' X' }).Count | Should Be 1
        @($words | Where-Object { $_.Text -eq ' X' -and $_.Id -eq '2-0' }).Count | Should Be 1
    }
}
