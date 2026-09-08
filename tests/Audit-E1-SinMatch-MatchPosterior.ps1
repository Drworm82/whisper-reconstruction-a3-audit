. .\src\Load-WhisperReconstruction.ps1

Write-Host "=== AUDIT E1: SIN MATCH -> MATCH POSTERIOR (FIXTURE FINAL) ===" -ForegroundColor Cyan
Write-Host ""

function New-TestToken {
    param([string]$Text, [double]$From, [double]$To)
    [PSCustomObject]@{ Text = $Text; From = $From; To = $To }
}

function New-TestWindow {
    param([double]$Start, [double]$End, [object[]]$Tokens)
    [PSCustomObject]@{ Start = $Start; End = $End; Tokens = @($Tokens) }
}

function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

$pass = $true

$w0 = @(
    (T ' A' 1.0 1.3),
    (T ' B' 2.0 2.3),
    (T ' C' 3.0 3.3),
    (T ' M' 8.0 8.3),
    (T ' N' 8.5 8.8),
    (T ' Q' 9.0 9.3)
)

$w1 = @(
    (T ' X' 0.5 0.8),
    (T ' Y' 4.0 4.3),
    (T ' Z' 5.0 5.3),
    (T ' M' 8.0 8.3),
    (T ' N' 8.5 8.8),
    (T ' O' 9.0 9.3)
)

$w2 = @(
    (T ' M' 8.0 8.3),
    (T ' N' 8.5 8.8),
    (T ' O' 9.0 9.3),
    (T ' R' 11.0 11.3)
)

$windows = @(
    (New-TestWindow 0 10 $w0),
    (New-TestWindow 5 15 $w1),
    (New-TestWindow 8 18 $w2)
)

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)

    Write-Host ""
    Write-Host "--- RESULTADO FINAL ---"
    foreach ($word in $result) {
        Write-Host "  '$($word.Text.Trim())' [$($word.From)-$($word.To)]"
    }

    $text = ($result | ForEach-Object { $_.Text.Trim() }) -join ' '
    Write-Host ""
    Write-Host "Texto:"
    Write-Host $text

    Write-Host ""
    Write-Host "--- CONTEOS ---"

    $expectedCounts = @{
        A = 1
        B = 1
        C = 1
        M = 1
        N = 1
        O = 1
        # Q belongs to W1's overlap hypothesis and is replaced by O
        # when the posterior W1 -> W2 MATCH is resolved.
        Q = 0
        X = 1
        Y = 1
        Z = 1
        R = 1
    }

    foreach ($expected in $expectedCounts.Keys) {
        $count = @(
            $result | Where-Object { $_.Text.Trim() -eq $expected }
        ).Count
        Write-Host "  $expected = $count (esperado=$($expectedCounts[$expected]))"

        if ($count -ne $expectedCounts[$expected]) {
            $pass = $false
            Write-Host "[ERROR] $expected esperado=$($expectedCounts[$expected]) obtenido=$count"
        }
    }

    if ($result.Count -ne 10) {
        $pass = $false
        Write-Host "[ERROR] Conteo total esperado=10 obtenido=$($result.Count)"
    }
    else {
        Write-Host "[OK] Conteo total de palabras: 10"
    }

    Write-Host ""
    Write-Host "--- ORDEN TEMPORAL ---"
    for ($i = 1; $i -lt $result.Count; $i++) {
        if ($result[$i].From -lt $result[$i - 1].From) {
            $pass = $false
            Write-Host "[ERROR] Orden roto: '$($result[$i-1].Text.Trim())'@$($result[$i-1].From) -> '$($result[$i].Text.Trim())'@$($result[$i].From)"
        }
    }

    if ($pass) {
        Write-Host "[OK] Orden temporal monotono."
        Write-Host "[OK] Todas las invariantes E1 se cumplen."
        Write-Host ""
        Write-Host "=== AUDIT E1 PASSED ==="
        exit 0
    }

    Write-Host "[ATENCION] La auditoria E1 fallo." -ForegroundColor Yellow
    Write-Host "=== AUDIT E1 FAILED ==="
    exit 1
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "=== AUDIT E1 FAILED ==="
    exit 1
}
