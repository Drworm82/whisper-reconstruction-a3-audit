Describe "deferred recovery debug" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "prints the deferred recovery fixture diagnostics" {
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
                    [PSCustomObject]@{ Text=' X'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' A'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' B'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' C'; From=4.8; To=5.0 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 10.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' B'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' C'; From=4.8; To=5.0 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                )
            }
        )

        $prev = @(Build-WhisperWords $windows[0].Tokens -WindowIndex 0) | Where-Object { $_.From -lt $windows[1].Start -and $_.To -gt $windows[1].Start -or $_.From -lt $windows[0].End -and $_.To -gt $windows[1].Start }
        $curr = @(Build-WhisperWords $windows[1].Tokens -WindowIndex 1)
        $match01 = Find-WordOverlap $prev $curr
        Write-Host "MATCH01 PreviousStart=$($match01.PreviousStart) CurrentStart=$($match01.CurrentStart) Matches=$($match01.Matches) Exact=$($match01.ExactTextMatches)"

        $final = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        foreach ($item in $final) {
            if ($item -is [string]) { Write-Host "MSG: $item" } else { Write-Host "WORD: $($item.Id) '$($item.Text)' $($item.From)->$($item.To)" }
        }

        $true | Should Be $true
    }
}
