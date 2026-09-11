Describe "Find-WordOverlap deferred index characterization" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"

    It "reports anchor positions for repeated same-text words" {
        $previous = @(
            [PSCustomObject]@{ Text=' Extra'; From=4.5; To=4.8; Key='extra'; Id='0-1' }
            [PSCustomObject]@{ Text=' Extra'; From=4.8; To=5.1; Key='extra'; Id='0-2' }
            [PSCustomObject]@{ Text=' Seis';  From=5.1; To=5.8; Key='seis';  Id='0-3' }
            [PSCustomObject]@{ Text=' Siete'; From=5.8; To=6.8; Key='siete'; Id='0-4' }
        )
        $current = @(
            [PSCustomObject]@{ Text=' Extra'; From=4.0; To=4.3; Key='extra'; Id='1-0' }
            [PSCustomObject]@{ Text=' Extra'; From=4.3; To=4.6; Key='extra'; Id='1-1' }
            [PSCustomObject]@{ Text=' Seis';  From=5.0; To=5.7; Key='seis';  Id='1-2' }
            [PSCustomObject]@{ Text=' Siete'; From=5.7; To=6.7; Key='siete'; Id='1-3' }
        )

        $match = Find-WordOverlap $previous $current

        $match | Should Not Be $null
        $match.PreviousStart | Should Be 0
        $match.CurrentStart | Should Be 0
        $match.Matches | Should Be 4
    }
}
