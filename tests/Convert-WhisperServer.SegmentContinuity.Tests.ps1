Describe "Convert-WhisperServer - segment continuity" {
    BeforeAll {
        . "$PSScriptRoot\..\src\Import\Convert-WhisperServer.ps1"

        $fixture = Join-Path $PSScriptRoot "..\AudioCapturePOC\poc7-language-es-turbo.json"
    }

    It "preserves one pipeline Window per whisper-server response" {
        $windows = @(Convert-WhisperServer -Path $fixture)

        $windows.Count | Should Be 1
        $windows[0].Tokens.Count | Should Be 45
    }

    It "preserves token continuity across internal segments" {
        $windows = @(Convert-WhisperServer -Path $fixture)

        $tokens = @($windows[0].Tokens)
        $text = $tokens.Text -join ""

        $text | Should Be " a través del programa universitario de gobierno, la facultad de economía y las facultades de contaduría y administración, ciencias políticas y sociales, derecho, filosofía y letras."
    }

    It "preserves the complete Window timing envelope" {
        $windows = @(Convert-WhisperServer -Path $fixture)

        $windows[0].Start | Should Be 0
        $windows[0].End | Should Be 14.68
    }
}
