. "C:\Users\Enrique\whisper-reconstruction\whisper-reconstruct.ps1"

function New-Token {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-Window {
    param([int]$Index, [double]$Start, [double]$End, [string[]]$Words)
    $duration = $End - $Start
    $totalTokens = $Words.Count * 2
    $tokenDuration = $duration / $totalTokens
    $tokens = @()
    $current = $Start
    foreach ($w in $Words) {
        $space = New-Token -Text " " -From $current -To ($current + $tokenDuration)
        $tokens += $space
        $current += $tokenDuration
        $word = New-Token -Text $w -From $current -To ($current + $tokenDuration)
        $tokens += $word
        $current += $tokenDuration
    }
    [PSCustomObject]@{
        Start = $Start
        End   = $End
        Tokens = $tokens
    }
}

$basePhrase = @("la","casa","es","grande","y","blanca","con","un","jardin","hermoso","el","sol","brilla","en","el","cielo","azul")

$windows = @()
for ($i = 0; $i -lt 110; $i++) {
    $start = $i * 5.0
    $end = $start + 6.0
    $offset = ($i * 3) % ($basePhrase.Count - 5)
    $segment = @()
    for ($j = 0; $j -lt 10; $j++) {
        $segment += $basePhrase[($offset + $j) % $basePhrase.Count]
    }
    $windows += New-Window -Index $i -Start $start -End $end -Words $segment
}

Write-Host "Ejecutando prueba con $($windows.Count) ventanas..."
$result = Reconstruct-WhisperWindows $windows
Write-Host "Prueba completada. Palabras finales: $($result.Count)"
