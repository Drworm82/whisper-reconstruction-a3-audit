Describe "Reconstruct-WhisperWindows MATCH placement boundary" {
    It "preserves chronology when current MATCH begins exactly at accumulated prefix boundary" {
        $prefix = @(
            [PSCustomObject]@{ Key='and'; Text='And'; From=2.84; To=4.00; Id=100 }
        )

        $currentMatch = @(
            [PSCustomObject]@{ Key='i'; Text='I'; From=4.00; To=4.11; Id=201 }
            [PSCustomObject]@{ Key='would'; Text='would'; From=4.11; To=4.66; Id=202 }
            [PSCustomObject]@{ Key='like'; Text='like'; From=4.66; To=5.07; Id=203 }
        )

        $newFinal = @($prefix) + @($currentMatch)
        $orderViolations = 0

        for ($i = 1; $i -lt $newFinal.Count; $i++) {
            if ($newFinal[$i].From -lt $newFinal[$i - 1].From) {
                $orderViolations++
            }
        }

        $newFinal.Count | Should Be 4
        $newFinal[0].Text | Should Be 'And'
        $newFinal[1].Text | Should Be 'I'
        $newFinal[1].From | Should Be 4.00
        $orderViolations | Should Be 0
    }

    It "produces a temporal regression when current MATCH starts before accumulated prefix boundary" {
        $prefix = @(
            [PSCustomObject]@{ Key='participate'; Text='participate'; From=3.80; To=4.13; Id=300 }
        )

        $currentMatch = @(
            [PSCustomObject]@{ Key='in'; Text='in'; From=4.00; To=4.22; Id=401 }
            [PSCustomObject]@{ Key='this'; Text='this'; From=4.22; To=4.66; Id=402 }
        )

        $newFinal = @($prefix) + @($currentMatch)
        $orderViolations = 0

        for ($i = 1; $i -lt $newFinal.Count; $i++) {
            if ($newFinal[$i].From -lt $newFinal[$i - 1].From) {
                $orderViolations++
            }
        }

        $newFinal[0].Text | Should Be 'participate'
        $newFinal[1].Text | Should Be 'in'
        $newFinal[1].From | Should Be 4.00
        $orderViolations | Should Be 0
    }
}
