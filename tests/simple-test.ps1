. 'C:\Users\Enrique\whisper-reconstruction\whisper-reconstruction.ps1'

function New-Token {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-Window {
    param([double]$Start, [double]$End, [string[]]$Words)
    $duration = $End - $Start
    $step = $duration / ($Words.Count * 2)
    $tokens = @()
    $current = $Start
    foreach ($w in $Words) {
        $tokens += New-Token -Text " " -From $current -To ($current + $step)
        $current += $step
        $tokens += New-Token -Text $w -From $current -To ($current + $step)
        $current += $step
    }
    [PSCustomObject]@{
        Start = $Start
        End   = $End
        Tokens = $tokens
    }
}

$w1 = New-Window -Start 0.0 -End 5.0 -Words @("hola","mundo","esto","es","una","prueba","de","whisper")
$w2 = New-Window -Start 5.0 -End 10.0 -Words @("una","prueba","de","whisper","reconstruccion","ventanas","solapadas")
$w3 = New-Window -Start 10.0 -End 15.0 -Words @("reconstruccion","ventanas","solapadas","funciona","correctamente","en","powershell")

$windows = @($w1, $w2, $w3)

Write-Host "Running simple reconstruction test with $($windows.Count) windows..."
$result = Reconstruct-WhisperWindows $windows
Write-Host "Result count: $($result.Count)"
if ($result.Count -gt 0) {
    Write-Host "First word: $($result[0].Text)"
    Write-Host "Last word: $($result[-1].Text)"
}
