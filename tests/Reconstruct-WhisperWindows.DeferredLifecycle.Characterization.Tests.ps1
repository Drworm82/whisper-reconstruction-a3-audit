Describe "Reconstruct-WhisperWindows deferred word lifecycle characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "preserves the existing deferred-anchor recovery behavior" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 7.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Uno';    From=0.0; To=1.0 }
                    [PSCustomObject]@{ Text=' Dos';    From=1.0; To=2.0 }
                    [PSCustomObject]@{ Text=' Tres';   From=2.0; To=3.0 }
                    [PSCustomObject]@{ Text=' Cuatro'; From=3.0; To=4.0 }
                    [PSCustomObject]@{ Text=' Cinco';  From=4.0; To=5.0 }
                    [PSCustomObject]@{ Text=' Seis';   From=5.0; To=6.0 }
                    [PSCustomObject]@{ Text=' Siete';  From=6.0; To=7.0 }
                )
            }
            [PSCustomObject]@{
                Start = 4.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Extra'; From=4.0; To=4.3 }
                    [PSCustomObject]@{ Text=' Cinco'; From=4.3; To=5.0 }
                    [PSCustomObject]@{ Text=' Seis';  From=5.0; To=6.0 }
                    [PSCustomObject]@{ Text=' Siete'; From=6.0; To=6.8 }
                )
            }
            [PSCustomObject]@{
                Start = 4.1
                End   = 10.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' Extra'; From=3.9; To=4.4 }
                    [PSCustomObject]@{ Text=' Cinco'; From=4.4; To=5.1 }
                    [PSCustomObject]@{ Text=' Seis';  From=5.1; To=6.1 }
                    [PSCustomObject]@{ Text=' Ocho';  From=6.1; To=7.0 }
                )
            }
        )

        $output = @(& {
            Reconstruct-WhisperWindows $windows
        } 6>&1)

        $messages = @(
            $output |
            ForEach-Object {
                $v = $_
                if ($v -is [System.Management.Automation.InformationRecord]) {
                    $d = $v.MessageData
                    if ($d -is [System.Management.Automation.HostInformationMessage]) {
                        $d = $d.Message
                    }
                    $v = $d
                }
                if ($v -is [string]) { $v }
            }
        )

        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })

        @($messages | Where-Object { $_ -eq "RECUPERADO ANCLA DIFERIDA: 'Extra'" }).Count | Should Be 1
        @($words | Where-Object { $_.Text -eq 'Extra' }).Count | Should Be 1
    }

    It "characterizes that a deferred occurrence can remain without recovery" {
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

        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })
        @($words | Where-Object { $_.Text -eq 'X' }).Count | Should Be 1
    }
}
