Describe "deferred duplicate characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "recovers one deferred occurrence while retaining another same-text occurrence" {
        $windows = @(
            [PSCustomObject]@{ Start=0.0; End=7.0; Tokens=@(
                [PSCustomObject]@{ Text=' Uno'; From=0.0; To=1.0 }
                [PSCustomObject]@{ Text=' Extra'; From=4.0; To=4.3 }
                [PSCustomObject]@{ Text=' Extra'; From=4.3; To=4.6 }
                [PSCustomObject]@{ Text=' A'; From=4.6; To=5.0 }
                [PSCustomObject]@{ Text=' B'; From=5.0; To=5.5 }
                [PSCustomObject]@{ Text=' C'; From=5.5; To=6.0 }
            ) }
            [PSCustomObject]@{ Start=4.0; End=9.0; Tokens=@(
                [PSCustomObject]@{ Text=' Extra'; From=4.0; To=4.3 }
                [PSCustomObject]@{ Text=' Extra'; From=4.3; To=4.6 }
                [PSCustomObject]@{ Text=' A'; From=4.6; To=5.0 }
                [PSCustomObject]@{ Text=' B'; From=5.0; To=5.5 }
                [PSCustomObject]@{ Text=' C'; From=5.5; To=6.0 }
                [PSCustomObject]@{ Text=' D'; From=6.0; To=6.5 }
            ) }
            [PSCustomObject]@{ Start=4.1; End=10.0; Tokens=@(
                [PSCustomObject]@{ Text=' Extra'; From=4.0; To=4.3 }
                [PSCustomObject]@{ Text=' A'; From=4.6; To=5.1 }
                [PSCustomObject]@{ Text=' B'; From=5.1; To=5.6 }
                [PSCustomObject]@{ Text=' C'; From=5.6; To=6.1 }
                [PSCustomObject]@{ Text=' E'; From=6.1; To=6.6 }
            ) }
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

        @($messages | Where-Object { $_ -eq "RECUPERADO ANCLA DIFERIDA: 'Extra'" }).Count | Should Be 1
        @($words | Where-Object { $_.Text -eq 'Extra' }).Count | Should Be 1
    }
}
