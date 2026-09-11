Describe "Reconstruct-WhisperWindows temporal MATCH placement integration" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "accepts a lexical MATCH when the current block begins at the accumulated prefix boundary" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0
                End = 10
                Tokens = @(
                    [PSCustomObject]@{ Text=' And'; From=2.84; To=4.00 }
                    [PSCustomObject]@{ Text=' I'; From=4.37; To=4.49 }
                    [PSCustomObject]@{ Text=' would'; From=4.84; To=5.32 }
                    [PSCustomObject]@{ Text=' like'; From=5.32; To=6.00 }
                    [PSCustomObject]@{ Text=' to'; From=6.00; To=6.16 }
                    [PSCustomObject]@{ Text=' extend'; From=6.16; To=6.63 }
                    [PSCustomObject]@{ Text=' a'; From=6.63; To=6.71 }
                    [PSCustomObject]@{ Text=' very'; From=6.71; To=7.03 }
                    [PSCustomObject]@{ Text=' special'; From=7.03; To=7.58 }
                    [PSCustomObject]@{ Text=' shout'; From=7.58; To=8.00 }
                    [PSCustomObject]@{ Text=' out'; From=8.00; To=9.19 }
                    [PSCustomObject]@{ Text=' to'; From=9.19; To=9.96 }
                    [PSCustomObject]@{ Text=' the'; From=9.97; To=10.00 }
                    [PSCustomObject]@{ Text=' 84'; From=10.00; To=10.00 }
                )
            }
            [PSCustomObject]@{
                Start = 2
                End = 12
                Tokens = @(
                    [PSCustomObject]@{ Text=' And'; From=2.84; To=4.00 }
                    [PSCustomObject]@{ Text=' I'; From=4.00; To=4.11 }
                    [PSCustomObject]@{ Text=' would'; From=4.11; To=4.66 }
                    [PSCustomObject]@{ Text=' like'; From=4.66; To=5.07 }
                    [PSCustomObject]@{ Text=' to'; From=5.07; To=5.26 }
                    [PSCustomObject]@{ Text=' extend'; From=5.32; To=6.00 }
                    [PSCustomObject]@{ Text=' a'; From=6.00; To=6.15 }
                    [PSCustomObject]@{ Text=' very'; From=6.22; To=6.82 }
                    [PSCustomObject]@{ Text=' special'; From=6.82; To=7.95 }
                    [PSCustomObject]@{ Text=' shout'; From=7.97; To=8.49 }
                    [PSCustomObject]@{ Text=' out'; From=8.49; To=8.79 }
                    [PSCustomObject]@{ Text=' to'; From=8.79; To=9.00 }
                    [PSCustomObject]@{ Text=' the'; From=9.00; To=9.29 }
                    [PSCustomObject]@{ Text=' 84'; From=9.34; To=9.99 }
                    [PSCustomObject]@{ Text=' participants'; From=10.03; To=11.99 }
                )
            }
        )

        $output = @(& {
            Reconstruct-WhisperWindows $windows
        } 6>&1)

        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })
        $sinMatch = @($output | Where-Object { $v = $_; if ($v -is [System.Management.Automation.InformationRecord]) { $d = $v.MessageData; if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }; $v = $d }; $v -is [string] -and $v -match "^SIN MATCH$" })
        $rejected = @($output | Where-Object { $v = $_; if ($v -is [System.Management.Automation.InformationRecord]) { $d = $v.MessageData; if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }; $v = $d }; $v -is [string] -and $v -match 'MATCH REJECTED BY TEMPORAL PLACEMENT GUARD' })
        $orderViolations = 0
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ($words[$i].From -lt $words[$i - 1].To) {
                $orderViolations++
            }
        }

        $words.Count | Should Be 15
        $text | Should Match 'And I would like to extend a very special shout out to the 84 participants'
        $sinMatch.Count | Should Be 0
        $rejected.Count | Should Be 0
        $orderViolations | Should Be 0
    }

    It "routes a lexical MATCH that starts before the accumulated prefix boundary into SIN MATCH" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0
                End = 10
                Tokens = @(
                    [PSCustomObject]@{ Text=' participate'; From=3.80; To=4.13 }
                    [PSCustomObject]@{ Text=' in'; From=4.86; To=4.93 }
                    [PSCustomObject]@{ Text=' this'; From=5.00; To=5.30 }
                    [PSCustomObject]@{ Text=' fifth'; From=5.30; To=5.60 }
                )
            }
            [PSCustomObject]@{
                Start = 2
                End = 12
                Tokens = @(
                    [PSCustomObject]@{ Text=' in'; From=4.00; To=4.22 }
                    [PSCustomObject]@{ Text=' this'; From=4.22; To=4.66 }
                    [PSCustomObject]@{ Text=' fifth'; From=4.66; To=5.16 }
                    [PSCustomObject]@{ Text=' edition'; From=5.16; To=5.60 }
                )
            }
        )

        $output = @(& {
            Reconstruct-WhisperWindows $windows
        } 6>&1)

        $words = @($output | Where-Object { $_.PSObject.Properties.Match('Id').Count })
        $sinMatch = @($output | Where-Object { $v = $_; if ($v -is [System.Management.Automation.InformationRecord]) { $d = $v.MessageData; if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }; $v = $d }; $v -is [string] -and $v -match "^SIN MATCH$" })
        $rejected = @($output | Where-Object { $v = $_; if ($v -is [System.Management.Automation.InformationRecord]) { $d = $v.MessageData; if ($d -is [System.Management.Automation.HostInformationMessage]) { $d = $d.Message }; $v = $d }; $v -is [string] -and $v -match 'MATCH REJECTED BY TEMPORAL PLACEMENT GUARD' })
        $orderViolations = 0
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ($words[$i].From -lt $words[$i - 1].To) {
                $orderViolations++
            }
        }

        $sinMatch.Count | Should Be 1
        $rejected.Count | Should Be 1
        $words.Count | Should Be 5
        $words[0].Text | Should Be 'participate'
        $orderViolations | Should Be 0
    }
}
