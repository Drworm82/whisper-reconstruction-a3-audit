# ============================================================
# Reconstruct-WhisperWindows
# ============================================================

function Reconstruct-WhisperWindows {
    param($windows)

    if ($null -eq $windows -or $windows.Count -eq 0) { return @() }

    for ($idx = 0; $idx -lt $windows.Count; $idx++) {
        $window = $windows[$idx]
        if (-not ($window.PSObject.Properties.Match("Start").Count)) { throw "Invalid window at index $idx : missing property 'Start'." }
        if (-not ($window.PSObject.Properties.Match("End").Count)) { throw "Invalid window at index $idx : missing property 'End'." }
        if (-not ($window.PSObject.Properties.Match("Tokens").Count)) { throw "Invalid window at index $idx : missing property 'Tokens'." }
    }

    $finalWords = @(Build-WhisperWords $windows[0].Tokens -WindowIndex 0)
    $previousOverlapMap = @{}
    if ($windows.Count -gt 1) {
        $overlapStart = $windows[1].Start
        $overlapEnd = $windows[0].End
        foreach ($word in @($finalWords | Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart })) {
            for ($idx=0; $idx -lt $finalWords.Count; $idx++) { if ($finalWords[$idx].Id -eq $word.Id) { $previousOverlapMap[$word.Id]=$idx; break } }
        }
    }

    # A word omitted from the visible reconstruction because it precedes the
    # selected MATCH anchor is retained as a deferred candidate. It becomes
    # visible later only when the same text/timing occurrence is selected as a
    # subsequent MATCH anchor.
    $deferredWordsByText = @{}

    for ($i=1; $i -lt $windows.Count; $i++) {
        $previous=$windows[$i-1]; $current=$windows[$i]
        $previousWords=@(Build-WhisperWords $previous.Tokens -WindowIndex ($i-1))
        $currentWords=@(Build-WhisperWords $current.Tokens -WindowIndex $i)
        $overlapStart=$current.Start; $overlapEnd=$previous.End
        $prevOverlap=@($previousWords | Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart })
        $currOverlap=@($currentWords | Where-Object { $_.From -lt $overlapEnd -and $_.To -gt $overlapStart })
        $match=Find-WordOverlap $prevOverlap $currOverlap

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "TRANSICION $($previous.Start)s -> $($current.Start)s"
        Write-Host "============================================================"

        if ($null -eq $previousOverlapMap) { $previousOverlapMap=@{} }

        if ($null -eq $match) {
            Write-Host "SIN MATCH"
            $bandDuration=$overlapEnd-$overlapStart
            $driftAllowance=[math]::Max(0.5,[math]::Min(1.5,$bandDuration*0.2))
            $prevBandByText=@{}; $currBandByText=@{}
            foreach ($w in $prevOverlap) { $t=($w.Text.ToLower()).Trim(); if($prevBandByText.ContainsKey($t)){$prevBandByText[$t]=@($prevBandByText[$t])+$w}else{$prevBandByText[$t]=@($w)} }
            foreach ($w in $currOverlap) { $t=($w.Text.ToLower()).Trim(); if($currBandByText.ContainsKey($t)){$currBandByText[$t]=@($currBandByText[$t])+$w}else{$currBandByText[$t]=@($w)} }
            function Test-BandPairEvidence { param([string]$text,[hashtable]$prevBandByText,[hashtable]$currBandByText,[double]$driftAllowance)
                if(-not($prevBandByText.ContainsKey($text)-and$currBandByText.ContainsKey($text))){return $false};$a=@($prevBandByText[$text]);$b=@($currBandByText[$text]);if($a.Count-lt1-or$b.Count-lt1-or$a.Count-ne$b.Count){return $false};for($n=0;$n-lt$a.Count;$n++){if([math]::Abs($a[$n].From-$b[$n].From)-gt$driftAllowance-or[math]::Abs($a[$n].To-$b[$n].To)-gt$driftAllowance){return $false}};return $true }
            function Test-WordAlreadyExists { param([object]$newWord,[object[]]$existingWords,[double]$bandStart,[double]$bandEnd,[double]$driftAllowance,[hashtable]$prevBandByText,[hashtable]$currBandByText,[System.Collections.Generic.HashSet[int]]$claimed)
                $t=($newWord.Text.ToLower()).Trim();if(-not($newWord.From-lt$bandEnd-and$newWord.To-gt$bandStart)){return $false};if([string]::IsNullOrEmpty($newWord.Key)){return $false};if(-not(Test-BandPairEvidence $t $prevBandByText $currBandByText $driftAllowance)){return $false};for($idx=0;$idx-lt$existingWords.Count;$idx++){ $e=$existingWords[$idx];if($t-ne(($e.Text.ToLower()).Trim())){continue};if([math]::Abs($newWord.From-$e.From)-le$driftAllowance-and[math]::Abs($newWord.To-$e.To)-le$driftAllowance){if($claimed.Contains($idx)){continue};$claimed.Add($idx)|Out-Null;return $true}};return $false }
            function Test-TransitiveWordAlreadyExists { param([object]$newWord,[object[]]$existingWords,[double]$bandStart,[double]$bandEnd,[double]$transitiveAllowance,[hashtable]$prevBandByText,[hashtable]$currBandByText,[hashtable]$accBandByText,[System.Collections.Generic.HashSet[int]]$claimed)
                $t=($newWord.Text.ToLower()).Trim();if(-not($newWord.From-lt$bandEnd-and$newWord.To-gt$bandStart)){return $false};if([string]::IsNullOrEmpty($newWord.Key)){return $false};if($prevBandByText.ContainsKey($t)){return $false};if(-not$accBandByText.ContainsKey($t)){return $false};$a=@($accBandByText[$t]);$b=@($currBandByText[$t]);if($a.Count-lt1-or$b.Count-lt1-or$a.Count-ne$b.Count){return $false};$a=@($a|Sort-Object From);$b=@($b|Sort-Object From);for($n=0;$n-lt$a.Count;$n++){if([math]::Abs($a[$n].From-$b[$n].From)-gt$transitiveAllowance-or[math]::Abs($a[$n].To-$b[$n].To)-gt$transitiveAllowance){return $false}};$slot=-1;for($n=0;$n-lt$b.Count;$n++){if($b[$n].Id-eq$newWord.Id){$slot=$n;break}};if($slot-lt0){return $false};$partner=$a[$slot];for($idx=0;$idx-lt$existingWords.Count;$idx++){if($existingWords[$idx].Id-eq$partner.Id){if($claimed.Contains($idx)){return $false};$claimed.Add($idx)|Out-Null;return $true}};return $false }
            function Add-NewWordsWithTiming { param([object[]]$currentWords,[object[]]$finalWords,[double]$bandStart,[double]$bandEnd,[double]$driftAllowance,[hashtable]$prevBandByText,[hashtable]$currBandByText,[double]$transitiveAllowance,[hashtable]$accBandByText)
                $r=@($finalWords);$claimed=New-Object 'System.Collections.Generic.HashSet[int]';foreach($w in$currentWords){if(-not(Test-WordAlreadyExists $w $r $bandStart $bandEnd $driftAllowance $prevBandByText $currBandByText $claimed)){if(-not(Test-TransitiveWordAlreadyExists $w $r $bandStart $bandEnd $transitiveAllowance $prevBandByText $currBandByText $accBandByText $claimed)){$r+=$w}}};return @($r) }
            $transitiveAllowance=[math]::Min($driftAllowance,0.5);$accBandByText=@{};foreach($e in$finalWords){if($e.From-lt$overlapEnd-and$e.To-gt$overlapStart){$t=($e.Text.ToLower()).Trim();if($accBandByText.ContainsKey($t)){$accBandByText[$t]=@($accBandByText[$t])+$e}else{$accBandByText[$t]=@($e)}}}
            $finalWords=@(Add-NewWordsWithTiming $currentWords $finalWords $overlapStart $overlapEnd $driftAllowance $prevBandByText $currBandByText $transitiveAllowance $accBandByText)
            $previousOverlapMap=@{};for($idx=0;$idx-lt$finalWords.Count;$idx++){$previousOverlapMap[$finalWords[$idx].Id]=$idx};continue
        }

        $matchedWord=$prevOverlap[$match.PreviousStart]
        if($null-eq$matchedWord){Write-Host "ERROR: EL ELEMENTO DEL MATCH ES NULL";continue}

        $prefixCount=$null
        if($previousOverlapMap.ContainsKey($matchedWord.Id)){$prefixCount=$previousOverlapMap[$matchedWord.Id]}
        if($null-eq$prefixCount){for($idx=0;$idx-lt$finalWords.Count;$idx++){if($finalWords[$idx].Id-eq$matchedWord.Id){$prefixCount=$idx;break}}}

        # The historical failure occurs when the next MATCH begins at a word
        # that an earlier MATCH had to omit. Recover that candidate before
        # rebuilding the prefix, preserving temporal order.
        if($null-eq$prefixCount){
            $anchorText=($matchedWord.Text.ToLower()).Trim();$candidate=$null
            if($deferredWordsByText.ContainsKey($anchorText)){
                foreach($d in @($deferredWordsByText[$anchorText])){
                    if([math]::Abs($d.From-$matchedWord.From)-le 0.000001-and[math]::Abs($d.To-$matchedWord.To)-le 0.000001){$candidate=$d;break}
                }
            }
            if($null-ne$candidate){
                $insertAt=$finalWords.Count
                for($idx=0;$idx-lt$finalWords.Count;$idx++){if($finalWords[$idx].From-gt$candidate.From){$insertAt=$idx;break}}
                if($insertAt-eq0){$finalWords=@($candidate)+$finalWords}elseif($insertAt-eq$finalWords.Count){$finalWords=@($finalWords)+$candidate}else{$finalWords=@($finalWords[0..($insertAt-1)])+$candidate+@($finalWords[$insertAt..($finalWords.Count-1)])}
                $prefixCount=$insertAt
                Write-Host "RECUPERADO ANCLA DIFERIDA: '$($candidate.Text)'"
                $remaining=@($deferredWordsByText[$anchorText]|Where-Object{$_.Id-ne$candidate.Id});if($remaining.Count-eq0){$deferredWordsByText.Remove($anchorText)|Out-Null}else{$deferredWordsByText[$anchorText]=$remaining}
            }
        }

        if($null-eq$prefixCount){Write-Host "ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA";continue}
        if($prefixCount-lt0-or$prefixCount-gt$finalWords.Count){Write-Host "ERROR: PREFIX COUNT INVALIDO";continue}

        $prefix=@();if($prefixCount-gt0){$prefix=@($finalWords|Select-Object -First $prefixCount)}
        $currentMatch=@($currOverlap|Select-Object -Skip $match.CurrentStart -First $match.CurrentConsumed);if($currentMatch.Count-eq0){Write-Host "MATCH INVALIDO";continue}
        $overlapStartInCurrent=-1
        for($j=0;$j-lt$currentWords.Count;$j++){if($currOverlap.Count-gt0-and$currentWords[$j].Id-eq$currOverlap[0].Id){$overlapStartInCurrent=$j;break}}
        if($overlapStartInCurrent-lt0){Write-Host "ERROR: NO SE PUDO LOCALIZAR EL INICIO DEL OVERLAP EN CURRENT WORDS";continue}
        $currentLastIndexInWords=$overlapStartInCurrent+$match.CurrentStart+$match.CurrentConsumed-1
        if($currentLastIndexInWords-lt0-or$currentLastIndexInWords-ge$currentWords.Count){Write-Host "ERROR: CURRENT LAST INDEX INVALIDO";continue}
        $after=@();if($currentLastIndexInWords+1-lt$currentWords.Count){$after=@($currentWords|Select-Object -Skip($currentLastIndexInWords+1))}

        # Save omitted pre-match words as deferred candidates before replacing finalWords.
        for($k=0;$k-lt$match.CurrentStart;$k++){$d=$currOverlap[$k];$t=($d.Text.ToLower()).Trim();if([string]::IsNullOrEmpty($d.Key)){continue};if($deferredWordsByText.ContainsKey($t)){$deferredWordsByText[$t]=@($deferredWordsByText[$t])+$d}else{$deferredWordsByText[$t]=@($d)}}

        $newFinal=@();foreach($w in$prefix){$newFinal+=$w};foreach($w in$currentMatch){$newFinal+=$w};foreach($w in$after){$newFinal+=$w};$finalWords=@($newFinal)
        $previousOverlapMap=@{};for($idx=0;$idx-lt$finalWords.Count;$idx++){$previousOverlapMap[$finalWords[$idx].Id]=$idx}
    }

    return @($finalWords)
}
