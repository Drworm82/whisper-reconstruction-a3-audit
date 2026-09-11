Describe "deferred minimal characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "defers a unique prefix word before a three-word anchor" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 5.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Uno'; From=3.7; To=3.9 }
                    [PSCustomObject]@{ Text=' X'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Y'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' A'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' B'; From=4.4; To=4.6 }
                    [PSCustomObject]@{ Text=' C'; From=4.6; To=4.8 }
                    [PSCustomObject]@{ Text=' D'; From=8.0; To=8.3 }
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

        @($messages | Where-Object { $_ -eq 'SIN MATCH' }).Count | Should Be 0
        @($words | Where-Object { $_.Text -eq 'A' }).Count | Should Be 1
        @($words | Where-Object { $_.Text -eq 'B' }).Count | Should Be 1
        @($words | Where-Object { $_.Text -eq 'C' }).Count | Should Be 1
    }
}
