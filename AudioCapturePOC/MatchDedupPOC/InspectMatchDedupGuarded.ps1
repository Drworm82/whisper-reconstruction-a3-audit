param(
    [string]$RawDirectory = (Join-Path $PSScriptRoot 'bin\Debug\net10.0\raw-json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

. (Join-Path $repoRoot 'src\Import\Convert-WhisperServer.ps1')
. (Join-Path $repoRoot 'src\Words\Build-WhisperWords.ps1')
. (Join-Path $repoRoot 'src\Alignment\Find-WordOverlap.ps1')
. (Join-Path $repoRoot 'src\Alignment\Find-WordOverlap-MatchGuard.ps1')
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
    $windows += [PSCustomObject]@{
        Start = [double]$converted.Start + $offsets[$i]
        End   = [double]$converted.End   + $offsets[$i]
        Tokens = $tokens
    }

    Write-Host "WINDOW #$i WORDS: $($words.Count)"
}

Write-Host ""
Write-Host "=== GUARDED RECONSTRUCTION ==="
Write-Host "The original Find-WordOverlap is wrapped by the temporal placement guard."
Write-Host "No audio capture or whisper-server call is performed."

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

$duplicates = @(
    $wordObjects |
    Group-Object Id |
    Where-Object Count -gt 1
)

$wordObjects | Select-Object Id,Key,Text,From,To,WindowIndex | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "ORDER VIOLATIONS: $($orderViolations.Count)"
if ($orderViolations.Count -gt 0) {
    $orderViolations | Format-Table -AutoSize | Out-String | Write-Host
}
Write-Host "DUPLICATE IDS: $($duplicates.Count)"
Write-Host "FINAL WORD COUNT: $($wordObjects.Count)"

[PSCustomObject]@{
    Windows = $windows.Count
    ReconstructedWords = $wordObjects.Count
    DuplicateIds = $duplicates.Count
    OrderViolations = $orderViolations.Count
    Pass = ($orderViolations.Count -eq 0 -and $duplicates.Count -eq 0)
} | ConvertTo-Json -Compress
