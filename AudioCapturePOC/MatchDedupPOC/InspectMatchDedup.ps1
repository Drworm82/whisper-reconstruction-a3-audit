param(
    [string]$RawDirectory = (Join-Path $PSScriptRoot 'bin\Debug\net10.0\raw-json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

. (Join-Path $repoRoot 'src\Import\Convert-WhisperServer.ps1')
. (Join-Path $repoRoot 'src\Words\Build-WhisperWords.ps1')
. (Join-Path $repoRoot 'src\Alignment\Find-WordOverlap.ps1')
. (Join-Path $repoRoot 'src\Reconstruction\Reconstruct-WhisperWindows.ps1')

$paths = @(
    Join-Path $RawDirectory 'window-00-verbose.json'
    Join-Path $RawDirectory 'window-01-verbose.json'
    Join-Path $RawDirectory 'window-02-verbose.json'
)

foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "No existe el JSON esperado: $path"
    }
}

$offsets = @(0.0, 2.0, 4.0)
$windows = @()
$builtWords = @()

for ($i = 0; $i -lt $paths.Count; $i++) {
    $converted = Convert-WhisperServer -Path $paths[$i]
    $tokens = @(
        $converted.Tokens | ForEach-Object {
            [PSCustomObject]@{
                Text = $_.Text
                From = [double]$_.From + $offsets[$i]
                To   = [double]$_.To   + $offsets[$i]
            }
        }
    )

    $words = @(Build-WhisperWords $tokens -WindowIndex $i)
    $builtWords += $words

    $windows += [PSCustomObject]@{
        Start = [double]$converted.Start + $offsets[$i]
        End   = [double]$converted.End   + $offsets[$i]
        Tokens = $tokens
    }

    Write-Host ""
    Write-Host "WINDOW #$i WORDS ($($words.Count))"
    $words | Select-Object Id,Key,Text,From,To | Format-Table -AutoSize | Out-String | Write-Host
}

for ($i = 1; $i -lt $windows.Count; $i++) {
    $previousWords = @(
        Build-WhisperWords $windows[$i - 1].Tokens -WindowIndex ($i - 1)
    )
    $currentWords = @(
        Build-WhisperWords $windows[$i].Tokens -WindowIndex $i
    )

    $overlapStart = $windows[$i].Start
    $overlapEnd = $windows[$i - 1].End

    $prevOverlap = @(
        $previousWords | Where-Object {
            $_.From -lt $overlapEnd -and $_.To -gt $overlapStart
        }
    )
    $currOverlap = @(
        $currentWords | Where-Object {
            $_.From -lt $overlapEnd -and $_.To -gt $overlapStart
        }
    )

    $match = Find-WordOverlap $prevOverlap $currOverlap

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "DIAGNOSTICO TRANSICION $($i - 1) -> $i"
    Write-Host "Overlap global: $overlapStart s -> $overlapEnd s"
    Write-Host "Previous overlap words: $($prevOverlap.Count)"
    Write-Host "Current overlap words:  $($currOverlap.Count)"
    Write-Host "============================================================"

    Write-Host "PREVIOUS OVERLAP"
    $prevOverlap | Select-Object Id,Key,Text,From,To | Format-Table -AutoSize | Out-String | Write-Host

    Write-Host "CURRENT OVERLAP"
    $currOverlap | Select-Object Id,Key,Text,From,To | Format-Table -AutoSize | Out-String | Write-Host

    if ($null -eq $match) {
        Write-Host "MATCH CANDIDATE: NONE"
    } else {
        Write-Host "MATCH CANDIDATE: FOUND"
        $match | Format-List | Out-String | Write-Host
        Write-Host "Anchor previous:"
        $prevOverlap[$match.PreviousStart] | Select-Object Id,Key,Text,From,To | Format-List | Out-String | Write-Host
        Write-Host "Anchor current:"
        $currOverlap[$match.CurrentStart] | Select-Object Id,Key,Text,From,To | Format-List | Out-String | Write-Host
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "RECONSTRUCCION + ORDEN FINAL"
Write-Host "============================================================"

$result = @(Reconstruct-WhisperWindows $windows)
$wordObjects = @(
    $result | Where-Object { $_.PSObject.Properties.Name -contains 'Id' }
)

$orderViolations = @()
for ($i = 1; $i -lt $wordObjects.Count; $i++) {
    if ([double]$wordObjects[$i].From -lt [double]$wordObjects[$i - 1].From) {
        $orderViolations += [PSCustomObject]@{
            Index = $i
            PreviousId = $wordObjects[$i - 1].Id
            PreviousText = $wordObjects[$i - 1].Text
            PreviousFrom = $wordObjects[$i - 1].From
            CurrentId = $wordObjects[$i].Id
            CurrentText = $wordObjects[$i].Text
            CurrentFrom = $wordObjects[$i].From
        }
    }
}

$wordObjects | Select-Object Id,Key,Text,From,To,WindowIndex | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "ORDER VIOLATIONS: $($orderViolations.Count)"
if ($orderViolations.Count -gt 0) {
    $orderViolations | Format-Table -AutoSize | Out-String | Write-Host
}

$duplicates = @(
    $wordObjects |
    Group-Object Id |
    Where-Object Count -gt 1
)

Write-Host "DUPLICATE IDS: $($duplicates.Count)"
Write-Host "FINAL WORD COUNT: $($wordObjects.Count)"
