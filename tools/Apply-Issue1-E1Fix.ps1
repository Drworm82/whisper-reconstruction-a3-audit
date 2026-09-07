$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$path = Join-Path $projectRoot 'src\Reconstruction\Reconstruct-WhisperWindows.ps1'
$content = Get-Content $path -Raw

$old = @'
            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }

            continue
'@

$new = @'
            # SIN MATCH appends/deduplicates current words, so the surviving
            # representative may keep the previous window's ID. The next
            # transition, however, addresses the overlap using the current
            # window's IDs. Keep aliases from current overlap IDs to the
            # surviving accumulated representative, and restore chronological
            # order before the next transition.
            $finalWords = @(
                $finalWords | Sort-Object -Property From, To
            )

            $previousOverlapMap = @{}
            for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                $previousOverlapMap[$finalWords[$idx].Id] = $idx
            }

            $claimedAliases = New-Object 'System.Collections.Generic.HashSet[int]'

            foreach ($word in $currOverlap) {
                if ($previousOverlapMap.ContainsKey($word.Id)) {
                    continue
                }

                $text = ($word.Text.ToLower()).Trim()
                if ([string]::IsNullOrEmpty($text)) {
                    continue
                }

                $bestIndex = -1
                $bestScore = [double]::PositiveInfinity

                for ($idx = 0; $idx -lt $finalWords.Count; $idx++) {
                    if ($claimedAliases.Contains($idx)) {
                        continue
                    }

                    $candidate = $finalWords[$idx]
                    if ($text -ne (($candidate.Text.ToLower()).Trim())) {
                        continue
                    }

                    $fromDiff = [math]::Abs($word.From - $candidate.From)
                    $toDiff   = [math]::Abs($word.To   - $candidate.To)

                    if ($fromDiff -le $driftAllowance -and $toDiff -le $driftAllowance) {
                        $score = $fromDiff + $toDiff
                        if ($score -lt $bestScore) {
                            $bestScore = $score
                            $bestIndex = $idx
                        }
                    }
                }

                if ($bestIndex -ge 0) {
                    $previousOverlapMap[$word.Id] = $bestIndex
                    $claimedAliases.Add($bestIndex) | Out-Null
                }
            }

            continue
'@

if (-not $content.Contains($old)) {
    throw 'Issue 1 target block was not found. Refusing to modify the production file.'
}

if ($content.Contains('# SIN MATCH appends/deduplicates current words')) {
    Write-Host 'Issue 1 E1 patch already present; no changes made.'
    exit 0
}

$content = $content.Replace($old, $new)
Set-Content -Path $path -Value $content -Encoding UTF8
Write-Host "Applied Issue 1 E1 fix to $path"
