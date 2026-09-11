Describe "deferred state debug" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"

    It "characterizes the matcher state for deferred X" {
        $w0 = @(Build-WhisperWords @(
            [PSCustomObject]@{ Text=' T0'; From=3.8; To=3.98 }
            [PSCustomObject]@{ Text=' A'; From=4.0; To=4.2 }
            [PSCustomObject]@{ Text=' B'; From=4.2; To=4.4 }
            [PSCustomObject]@{ Text=' C'; From=4.4; To=4.6 }
        ) -WindowIndex 0)
        $w1 = @(Build-WhisperWords @(
            [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
            [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
            [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
            [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
        ) -WindowIndex 1)
        $w2 = @(Build-WhisperWords @(
            [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
            [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
            [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
            [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
            [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
        ) -WindowIndex 2)

        $m1 = Find-WordOverlap $w0 $w1
        $m2 = Find-WordOverlap $w1 $w2
        Write-Host "M1 prev=$($m1.PreviousStart) curr=$($m1.CurrentStart) matches=$($m1.Matches)"
        Write-Host "M1 anchor=$($w0[$m1.PreviousStart].Text) deferredCount=$($m1.CurrentStart)"
        Write-Host "M2 prev=$($m2.PreviousStart) curr=$($m2.CurrentStart) matches=$($m2.Matches)"
        Write-Host "M2 anchor=$($w1[$m2.PreviousStart].Text) anchorId=$($w1[$m2.PreviousStart].Id)"
        Write-Host "M2 anchorKey=$($w1[$m2.PreviousStart].Key)"
        Write-Host "M2 anchorFrom=$($w1[$m2.PreviousStart].From) anchorTo=$($w1[$m2.PreviousStart].To)"
        1 | Should Be 1
    }
}
