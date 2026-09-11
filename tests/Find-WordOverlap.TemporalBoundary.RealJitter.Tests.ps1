Describe "Find-WordOverlap temporal boundary on real-audio jitter" {
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"

    It "shows that anchor inversion does not imply prefix-boundary inversion" {
        $previousWords = @(
            [PSCustomObject]@{ Key='and'; Text='And'; From=2.84; To=4.00 }
            [PSCustomObject]@{ Key='i'; Text='I'; From=4.37; To=4.49 }
            [PSCustomObject]@{ Key='would'; Text='would'; From=4.84; To=5.32 }
            [PSCustomObject]@{ Key='like'; Text='like'; From=5.32; To=6.00 }
            [PSCustomObject]@{ Key='to'; Text='to'; From=6.00; To=6.16 }
            [PSCustomObject]@{ Key='extend'; Text='extend'; From=6.16; To=6.63 }
            [PSCustomObject]@{ Key='a'; Text='a'; From=6.63; To=6.71 }
            [PSCustomObject]@{ Key='very'; Text='very'; From=6.71; To=7.03 }
            [PSCustomObject]@{ Key='special'; Text='special'; From=7.03; To=7.58 }
            [PSCustomObject]@{ Key='shout'; Text='shout'; From=7.58; To=8.00 }
            [PSCustomObject]@{ Key='out'; Text='out'; From=8.00; To=9.19 }
            [PSCustomObject]@{ Key='to'; Text='to'; From=9.19; To=9.96 }
            [PSCustomObject]@{ Key='the'; Text='the'; From=9.97; To=10.00 }
            [PSCustomObject]@{ Key='84'; Text='84'; From=10.00; To=10.00 }
        )

        $currentWords = @(
            [PSCustomObject]@{ Key='i'; Text='I'; From=4.00; To=4.11 }
            [PSCustomObject]@{ Key='would'; Text='would'; From=4.11; To=4.66 }
            [PSCustomObject]@{ Key='like'; Text='like'; From=4.66; To=5.07 }
            [PSCustomObject]@{ Key='to'; Text='to'; From=5.07; To=5.26 }
            [PSCustomObject]@{ Key='extend'; Text='extend'; From=5.32; To=6.00 }
            [PSCustomObject]@{ Key='a'; Text='a'; From=6.00; To=6.15 }
            [PSCustomObject]@{ Key='very'; Text='very'; From=6.22; To=6.82 }
            [PSCustomObject]@{ Key='special'; Text='special'; From=6.82; To=7.95 }
            [PSCustomObject]@{ Key='shout'; Text='shout'; From=7.97; To=8.49 }
            [PSCustomObject]@{ Key='out'; Text='out'; From=8.49; To=8.79 }
            [PSCustomObject]@{ Key='to'; Text='to'; From=8.79; To=9.00 }
            [PSCustomObject]@{ Key='the'; Text='the'; From=9.00; To=9.29 }
            [PSCustomObject]@{ Key='84'; Text='84'; From=9.34; To=9.99 }
        )

        $result = Find-WordOverlap $previousWords $currentWords

        # The production guard currently rejects the lexical MATCH because
        # its selected current anchor starts at 4.00s instead of 4.37s.
        $result | Should Be $null

        # The same selected MATCH, without the guard, has a prefix boundary
        # at the first overlap word. Its boundary is the start of the MATCH,
        # not the previous anchor's timestamp.
        $previousAnchor = $previousWords[1]
        $currentAnchor = $currentWords[0]
        $prefixBoundary = $previousWords[0].To

        ($currentAnchor.From -lt $previousAnchor.From) | Should Be $true
        ($currentAnchor.From -eq $prefixBoundary) | Should Be $true
    }
}
