Describe "deferred orphan debug" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "prints the actual final words for an orphan candidate" {
        $windows = @(
            [PSCustomObject]@{ Start=0.0; End=5.0; Tokens=@(
                [PSCustomObject]@{ Text=' T0'; From=3.7; To=3.9 }
                [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
            ) }
            [PSCustomObject]@{ Start=4.0; End=9.0; Tokens=@(
                [PSCustomObject]@{ Text=' Y'; From=4.0; To=4.2 }
                [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
            ) }
        )

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })

        Write-Host "FINAL COUNT=$($words.Count)"
        foreach ($word in $words) {
            Write-Host "FINAL id=$($word.Id) text='$($word.Text)' from=$($word.From) to=$($word.To)"
        }

        $words.Count | Should BeGreaterThan 0
    }
}
