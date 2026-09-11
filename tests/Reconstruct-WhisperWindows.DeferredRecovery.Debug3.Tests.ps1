Describe "deferred recovery execution debug" {
    . "$PSScriptRoot/../src/Words/Build-WhisperWords.ps1"
    . "$PSScriptRoot/../src/Alignment/Find-WordOverlap.ps1"
    . "$PSScriptRoot/../src/Reconstruction/Reconstruct-WhisperWindows.ps1"

    It "prints exact reconstruction messages and words" {
        $windows = @(
            [PSCustomObject]@{
                Start=0.0; End=9.0
                Tokens=@(
                    [PSCustomObject]@{Text=' T0';From=3.8;To=3.98}
                    [PSCustomObject]@{Text=' A';From=4.0;To=4.2}
                    [PSCustomObject]@{Text=' B';From=4.2;To=4.4}
                    [PSCustomObject]@{Text=' C';From=4.4;To=4.6}
                )
            }
            [PSCustomObject]@{
                Start=4.0; End=9.0
                Tokens=@(
                    [PSCustomObject]@{Text=' X';From=4.0;To=4.2}
                    [PSCustomObject]@{Text=' A';From=4.2;To=4.4}
                    [PSCustomObject]@{Text=' B';From=4.4;To=4.6}
                    [PSCustomObject]@{Text=' C';From=4.6;To=4.8}
                )
            }
            [PSCustomObject]@{
                Start=4.0; End=10.0
                Tokens=@(
                    [PSCustomObject]@{Text=' X';From=4.0;To=4.2}
                    [PSCustomObject]@{Text=' A';From=4.2;To=4.4}
                    [PSCustomObject]@{Text=' B';From=4.4;To=4.6}
                    [PSCustomObject]@{Text=' C';From=4.6;To=4.8}
                    [PSCustomObject]@{Text=' D';From=8.0;To=8.3}
                )
            }
        )

        $built = @(Build-WhisperWords $windows[1].Tokens -WindowIndex 1)
        Write-Host "W1 WORDS"
        foreach ($w in $built) { Write-Host "id=$($w.Id) text='$($w.Text)' key='$($w.Key)' from=$($w.From) to=$($w.To)" }

        $output = @(& { Reconstruct-WhisperWindows $windows } 6>&1)
        Write-Host "RECONSTRUCTION OUTPUT"
        foreach ($item in $output) {
            if ($item -is [string]) { Write-Host "MSG: $item" }
            elseif ($item.PSObject.Properties['Text']) { Write-Host "WORD: id=$($item.Id) text='$($item.Text)' key='$($item.Key)' from=$($item.From) to=$($item.To)" }
            else { Write-Host "OTHER: $($item.GetType().FullName)" }
        }
        1 | Should Be 1
    }
}
