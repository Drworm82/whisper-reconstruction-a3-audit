. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== AUDIT ISSUE 1: DOS MATCHES + RIESGO DE DUPLICACION ===" -ForegroundColor Cyan
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

# W0:
#   contenido exclusivo: A B
#   solapamiento: C D
#
# W1:
#   solapamiento: C D
#   contenido exclusivo: E F
#
# Solamente C,D coinciden.
$w0 = @(
    (T ' A' 1.0 1.3),
    (T ' B' 2.0 2.3),
    (T ' C' 6.0 6.3),
    (T ' D' 7.0 7.3)
)

$w1 = @(
    (T ' C' 6.0 6.3),
    (T ' D' 7.0 7.3),
    (T ' E' 11.0 11.3),
    (T ' F' 12.0 12.3)
)

$windows = @(
    (New-TestWindow 0 10 $w0),
    (New-TestWindow 5 15 $w1)
)

Write-Host "--- MATCH DIRECTO ---"

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
    Write-Host "[OK] Las 2 coincidencias no alcanzan el umbral de MATCH."
} else {
    Write-Host "[ERROR] Se encontro MATCH con solo 2 coincidencias: Matches=$($match.Matches)"
    Write-Host "=== AUDIT ISSUE 1 FAILED ===" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "--- RECONSTRUCCION ---"

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)

    $text = ($result | ForEach-Object { $_.Text.Trim() }) -join ' '

    Write-Host "Texto final: $text"
    Write-Host "Palabras: $($result.Count)"
    Write-Host ""

    foreach ($word in $result) {
        Write-Host "  '$($word.Text.Trim())' [$($word.From)-$($word.To)]"
    }

    Write-Host ""
    Write-Host "--- CONTEOS ---"

    $allCorrect = $true
    foreach ($expected in @("A","B","C","D","E","F")) {
        $count = @(
            $result | Where-Object {
                $_.Text.Trim() -eq $expected
            }
        ).Count

        Write-Host "  $expected = $count"
        if ($count -ne 1) {
            $allCorrect = $false
        }
    }

    if ($allCorrect -and $result.Count -eq 6) {
        Write-Host ""
        Write-Host "[OK] Las 2 coincidencias no provocaron perdida ni duplicacion." -ForegroundColor Green
        Write-Host "[OK] Las 6 palabras aparecen exactamente una vez."
        Write-Host "=== AUDIT ISSUE 1 PASSED ==="
        exit 0
    }

    Write-Host ""
    Write-Host "[ERROR] Se detecto perdida o duplicacion." -ForegroundColor Red
    Write-Host "=== AUDIT ISSUE 1 FAILED ==="
    exit 1
}
catch {
    Write-Host "[ERROR] Reconstruccion fallo: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "=== AUDIT ISSUE 1 FAILED ==="
    exit 1
}
