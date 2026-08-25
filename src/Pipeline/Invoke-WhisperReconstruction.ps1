# ============================================================
# Invoke-WhisperReconstruction
# ============================================================

function Invoke-WhisperReconstruction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WhisperXPath,

        [Parameter(Mandatory = $true)]
        [double]$WindowDurationSeconds,

        [Parameter(Mandatory = $true)]
        [double]$OverlapDurationSeconds
    )

    if (-not (Test-Path -LiteralPath $WhisperXPath)) {
        throw "WhisperX file not found: $WhisperXPath"
    }

    $scriptRoot = $PSScriptRoot
    if (-not $scriptRoot) {
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

    . "$projectRoot\src\Import\Convert-WhisperX.ps1"
    . "$projectRoot\src\Windowing\New-WhisperWindows.ps1"
    . "$projectRoot\src\Reconstruction\Reconstruct-WhisperWindows.ps1"

    $segmentWindows = Convert-WhisperX -Path $WhisperXPath

    $flatWords = @()
    foreach ($window in $segmentWindows) {
        foreach ($token in $window.Tokens) {
            $flatWords += [PSCustomObject]@{
                Text = $token.Text.Trim()
                From = $token.From
                To   = $token.To
            }
        }
    }

    if ($flatWords.Count -eq 0) {
        throw "No words found in WhisperX output."
    }

    $flatWords = $flatWords | Sort-Object -Property From

    $windows = New-WhisperWindows -Words $flatWords `
                                  -WindowDurationSeconds $WindowDurationSeconds `
                                  -OverlapDurationSeconds $OverlapDurationSeconds

    if ($windows.Count -eq 0) {
        throw "No windows generated. Check WindowDurationSeconds and OverlapDurationSeconds."
    }

    $result = Reconstruct-WhisperWindows $windows

    return $result
}
