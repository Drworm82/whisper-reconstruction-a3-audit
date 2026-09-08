. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== AUDIT ISSUE 1: CASO FUNCIONAL CON SOLO 2 MATCHES ===" -ForegroundColor Cyan
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-TestWindow {
    param([double]$Start, [double]$End, [object[]]$Tokens)
    [PSCustomObject]@{
        Start  = $Start
        End    = $End
        Tokens = @($Tokens)
    }
}

function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

# Ventana 0: A B X
$w0 = @(
    (T ' A' 5.0 5.3),
    (T ' B' 5.4 5.7),
    (T ' X' 5.8 6.1)
)

# Ventana 1: A B Y
# Solo A y B coinciden con W0.
$w1 = @(
    (T ' A' 5.0 5.3),
    (T ' B' 5.4 5.7),
    (T ' Y' 5.8 6.1)
)

$windows = @(
    (New-TestWindow 0 10 $w0),
    (New-TestWindow 5 15 $w1)
)

Write-Host "--- FIND-WORDOVERLAP DIRECTO ---"

$prevWords = @(Build-WhisperWords $w0 -WindowIndex 0)
$currWords = @(Build-WhisperWords $w1 -WindowIndex 1)

$prevOverlap = @(
    $prevWords | Where-Object {
        $_.From -lt 10 -and $_.To -gt 5
    }
)

$currOverlap = @(
    $currWords | Where-Object {
        $_.From -lt 10 -and $_.To -gt 5
    }
)

$match = Find-WordOverlap $prevOverlap $currOverlap

if ($null -eq $match) {
    Write-Host "[OK] Find-WordOverlap no genera MATCH con solo 2 coincidencias."
} else {
    Write-Host "[ERROR] Find-WordOverlap genero MATCH con solo 2 coincidencias: Matches=$($match.Matches)" -ForegroundColor Red
    Write-Host "=== AUDIT ISSUE 1 FAILED ==="
    exit 1
}

Write-Host ""
Write-Host "--- RECONSTRUCCION COMPLETA ---"

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)

    Write-Host "Palabras resultantes: $($result.Count)"

    foreach ($word in $result) {
        Write-Host "  '$($word.Text)' [$($word.From)-$($word.To)]"
    }

    $text = ($result | ForEach-Object { $_.Text.Trim() }) -join ' '

    Write-Host ""
    Write-Host "Texto final: $text"

    $aCount = @($result | Where-Object { $_.Text.Trim() -eq "A" }).Count
    $bCount = @($result | Where-Object { $_.Text.Trim() -eq "B" }).Count
    $xCount = @($result | Where-Object { $_.Text.Trim() -eq "X" }).Count
    $yCount = @($result | Where-Object { $_.Text.Trim() -eq "Y" }).Count

    Write-Host ""
    Write-Host "Conteos:"
    Write-Host "  A = $aCount"
    Write-Host "  B = $bCount"
    Write-Host "  X = $xCount"
    Write-Host "  Y = $yCount"

    if (
        $aCount -eq 1 -and
        $bCount -eq 1 -and
        $xCount -eq 1 -and
        $yCount -eq 1
    ) {
        Write-Host ""
        Write-Host "[OK] No hubo perdida ni duplicacion." -ForegroundColor Green
        Write-Host "=== AUDIT ISSUE 1 PASSED ==="
        exit 0
    }

    Write-Host ""
    Write-Host "[ERROR] El caso produjo perdida o duplicacion." -ForegroundColor Red
    Write-Host "=== AUDIT ISSUE 1 FAILED ==="
    exit 1
}
catch {
    Write-Host "[ERROR] Reconstruccion fallo: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "=== AUDIT ISSUE 1 FAILED ==="
    exit 1
}
