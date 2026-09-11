Describe "MATCH temporal placement against accumulated prefix boundary" {
    It "accepts the real jitter shape when current MATCH starts at the prefix boundary" {
        $finalPrefix = @(
            [PSCustomObject]@{ Key='and'; Text='And'; From=2.84; To=4.00; Id=100 }
        )

        $previousAnchor = [PSCustomObject]@{ Key='i'; Text='I'; From=4.37; To=4.49; Id=101 }
        $currentMatch = @(
            [PSCustomObject]@{ Key='i'; Text='I'; From=4.00; To=4.11; Id=201 }
            [PSCustomObject]@{ Key='would'; Text='would'; From=4.11; To=4.66; Id=202 }
            [PSCustomObject]@{ Key='like'; Text='like'; From=4.66; To=5.07; Id=203 }
        )

        $prefixBoundary = $finalPrefix[-1].To
        $replacement = @($finalPrefix) + @($currentMatch)
        $orderViolations = 0

        for ($i = 1; $i -lt $replacement.Count; $i++) {
            if ($replacement[$i].From -lt $replacement[$i - 1].From) {
                $orderViolations++
            }
        }

        ($currentMatch[0].From -lt $previousAnchor.From) | Should Be $true
        ($currentMatch[0].From -ge $prefixBoundary) | Should Be $true
        $orderViolations | Should Be 0
    }

    It "rejects the prior bad shape when current MATCH starts before the accumulated prefix" {
        $finalPrefix = @(
            [PSCustomObject]@{ Key='participate'; Text='participate'; From=3.80; To=4.13; Id=300 }
        )

        $previousAnchor = [PSCustomObject]@{ Key='in'; Text='in'; From=4.86; To=4.93; Id=301 }
        $currentMatch = @(
            [PSCustomObject]@{ Key='in'; Text='in'; From=4.00; To=4.22; Id=401 }
            [PSCustomObject]@{ Key='this'; Text='this'; From=4.22; To=4.66; Id=402 }
        )

        $prefixBoundary = $finalPrefix[-1].To
        $replacement = @($finalPrefix) + @($currentMatch)
        $orderViolations = 0

        for ($i = 1; $i -lt $replacement.Count; $i++) {
            if ($replacement[$i].From -lt $replacement[$i - 1].From) {
                $orderViolations++
            }
        }

        ($currentMatch[0].From -lt $previousAnchor.From) | Should Be $true
        ($currentMatch[0].From -lt $prefixBoundary) | Should Be $true
        $orderViolations | Should Be 1
    }
}
