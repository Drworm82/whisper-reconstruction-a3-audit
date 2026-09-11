Describe "Find-WordOverlap lexical alignment" {
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"

    It "returns the lexical MATCH even when the current anchor starts earlier" {
        $previousWords = @(
            [PSCustomObject]@{ Key = 'uno'; Text = 'uno'; From = 4.86; To = 5.00 }
            [PSCustomObject]@{ Key = 'dos'; Text = 'dos'; From = 5.00; To = 5.20 }
            [PSCustomObject]@{ Key = 'tres'; Text = 'tres'; From = 5.20; To = 5.40 }
        )

        $currentWords = @(
            [PSCustomObject]@{ Key = 'uno'; Text = 'uno'; From = 4.00; To = 4.20 }
            [PSCustomObject]@{ Key = 'dos'; Text = 'dos'; From = 4.20; To = 4.40 }
            [PSCustomObject]@{ Key = 'tres'; Text = 'tres'; From = 4.40; To = 4.60 }
        )

        $result = Find-WordOverlap $previousWords $currentWords

        $result | Should Not Be $null
        $result.Matches | Should Be 3
        $result.PreviousStart | Should Be 0
        $result.CurrentStart | Should Be 0
    }

    It "accepts a selected MATCH when the current anchor is chronologically valid" {
        $previousWords = @(
            [PSCustomObject]@{ Key = 'uno'; Text = 'uno'; From = 4.00; To = 4.20 }
            [PSCustomObject]@{ Key = 'dos'; Text = 'dos'; From = 4.20; To = 4.40 }
            [PSCustomObject]@{ Key = 'tres'; Text = 'tres'; From = 4.40; To = 4.60 }
        )

        $currentWords = @(
            [PSCustomObject]@{ Key = 'uno'; Text = 'uno'; From = 4.10; To = 4.30 }
            [PSCustomObject]@{ Key = 'dos'; Text = 'dos'; From = 4.30; To = 4.50 }
            [PSCustomObject]@{ Key = 'tres'; Text = 'tres'; From = 4.50; To = 4.70 }
        )

        $result = Find-WordOverlap $previousWords $currentWords

        $result | Should Not Be $null
        $result.Matches | Should Be 3
        $result.PreviousStart | Should Be 0
        $result.CurrentStart | Should Be 0
    }
}
