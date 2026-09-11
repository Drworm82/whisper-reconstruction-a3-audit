Describe "Reconstruct-WhisperWindows deferred anchor temporal guard" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "rejects a MATCH after recovering a deferred anchor when the current anchor starts before the accumulated prefix boundary" {
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

        $words = @(
            $output |
            Where-Object { $_.PSObject.Properties.Match('Id').Count }
        )

        $recovered = @($messages | Where-Object { $_ -eq "RECUPERADO ANCLA DIFERIDA: 'Extra'" })
        $rejected  = @($messages | Where-Object { $_ -eq 'MATCH REJECTED BY TEMPORAL PLACEMENT GUARD' })
        $sinMatch  = @($messages | Where-Object { $_ -eq 'SIN MATCH' })

        $recovered.Count | Should Be 1
        $rejected.Count | Should Be 1
        $sinMatch.Count | Should Be 1
        $words.Count | Should Be 9
        $words[0].Text | Should Be 'Uno'
        $words[4].Text | Should Be 'Extra'
        $words[4].From | Should Be 4.0
        $words[8].Text | Should Be 'Ocho'
    }
}
