Describe "minimal deferred recovery debug 2" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"

    It "prints every transition match for the minimal recovery fixture" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0; End = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' T0'; From=3.8; To=3.98 }
                    [PSCustomObject]@{ Text=' A';  From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' B';  From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' C';  From=4.4; To=4.6 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0; End = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0; End = 10.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
                )
            }
        )

        for ($i = 1; $i -lt $windows.Count; $i++) {
            $prev = @(Build-WhisperWords $windows[$i-1].Tokens -WindowIndex ($i-1))
            $curr = @(Build-WhisperWords $windows[$i].Tokens -WindowIndex $i)
            $overlapStart = $windows[$i].Start
            $overlapEnd = $windows[$i-1].End
            $prevOverlap = @($prev | Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart })
            $currOverlap = @($curr | Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart })
            $match = Find-WordOverlap $prevOverlap $currOverlap
            Write-Host "TRANSITION $i prev=$($prevOverlap.Count) curr=$($currOverlap.Count)"
            for ($p = 0; $p -lt $prevOverlap.Count; $p++) { Write-Host " PREV[$p] $($prevOverlap[$p].Text) $($prevOverlap[$p].From)->$($prevOverlap[$p].To) id=$($prevOverlap[$p].Id)" }
            for ($c = 0; $c -lt $currOverlap.Count; $c++) { Write-Host " CURR[$c] $($currOverlap[$c].Text) $($currOverlap[$c].From)->$($currOverlap[$c].To) id=$($currOverlap[$c].Id)" }
            if ($null -eq $match) { Write-Host " MATCH=NULL" }
            else {
                Write-Host " MATCH PreviousStart=$($match.PreviousStart) CurrentStart=$($match.CurrentStart) Matches=$($match.Matches) Exact=$($match.ExactTextMatches) CurrentConsumed=$($match.CurrentConsumed)"
                Write-Host " ANCHOR $($prevOverlap[$match.PreviousStart].Text) $($prevOverlap[$match.PreviousStart].From)->$($prevOverlap[$match.PreviousStart].To) id=$($prevOverlap[$match.PreviousStart].Id)"
            }
        }
        1 | Should Be 1
    }
}
