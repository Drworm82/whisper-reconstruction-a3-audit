Describe "deferred recovery message capture" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "captures the deferred recovery message from PowerShell 5.1 InformationRecord output" {
        $windows = @(
            [PSCustomObject]@{
                Start = 0.0
                End   = 9.0
                Tokens = @(
                    [PSCustomObject]@{ Text=' T0'; From=3.8; To=3.98 }
                    [PSCustomObject]@{ Text=' A'; From=4.0; To=4.2 }
                    [PSCustomObject]@{ Text=' B'; From=4.2; To=4.4 }
                    [PSCustomObject]@{ Text=' C'; From=4.4; To=4.6 }
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

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        $messages = @($output | ForEach-Object {
            $value = $_
            if ($value -is [System.Management.Automation.InformationRecord]) {
                $data = $value.MessageData
                if ($data -is [System.Management.Automation.HostInformationMessage]) {
                    $data = $data.Message
                }
                $value = $data
            }
            if ($value -is [string]) { $value }
        })

        @($messages | Where-Object { $_ -eq 'RECUPERADO ANCLA DIFERIDA: ''X''' }).Count | Should Be 1
    }
}
