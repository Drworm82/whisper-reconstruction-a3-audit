# PRUEBA ISSUE 6 — ESTADO DEL ANCLA DESPUES DE MATCH
#
# Reproduce el caso en que un MATCH conserva palabras de la ventana actual
# que quedan FUERA del overlap inmediato, y una transicion posterior necesita
# una de esas palabras como ancla. El mapa anterior, si solo contiene
# currOverlap de la transicion previa, no puede localizar ese ancla.
#
# Escenario:
#   W0 [0,10]  -> historia + A B C
#   W1 [5,15]  -> A B C + D E F G
#   W2 [8,18]  -> D E F + G
#
# En W0->W1, A B C forman el MATCH. D E F G quedan como "after" y se
# conservan en finalWords, pero D (la primera palabra del siguiente overlap)
# esta fuera del currOverlap de la primera transicion.
#
# En W1->W2, D E F forman el siguiente MATCH. El bug aparece si
# previousOverlapMap no contiene D aunque D ya este en finalWords.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

Write-Host "=== PRUEBA ISSUE 6: ESTADO DEL ANCLA DESPUES DE MATCH ==="
Write-Host ""

function New-TestToken {
    param(
        [string]$Text,
        [double]$From,
        [double]$To
    )

    [PSCustomObject]@{
        Text = $Text
        From = $From
        To   = $To
    }
}

function New-TestWindow {
    param(
        [double]$Start,
        [double]$End,
        [object[]]$Tokens
    )

    [PSCustomObject]@{
        Start  = $Start
        End    = $End
        Tokens = @($Tokens)
    }
}

# W0 [0,10]: la primera transicion tiene A B C como bloque comun.
$w0 = @(
    (New-TestToken 'inicio' 1.0 1.5),
    (New-TestToken 'A'      6.0 6.4),
    (New-TestToken 'B'      6.5 6.9),
    (New-TestToken 'C'      7.0 7.4)
)

# W1 [5,15]: A B C son el MATCH con W0. D E F G quedan despues del
# overlap [5,10] y por tanto deben sobrevivir en finalWords.
$w1 = @(
    (New-TestToken 'A' 6.0 6.4),
    (New-TestToken 'B' 6.5 6.9),
    (New-TestToken 'C' 7.0 7.4),
    (New-TestToken 'D' 10.5 10.9),
    (New-TestToken 'E' 11.0 11.4),
    (New-TestToken 'F' 11.5 11.9),
    (New-TestToken 'G' 12.0 12.4)
)

# W2 [8,18]: su overlap con W1 es [8,15], por lo que D E F G pertenecen
# a la banda. No incluimos C porque termina antes de 8s.
$w2 = @(
    (New-TestToken 'D' 10.5 10.9),
    (New-TestToken 'E' 11.0 11.4),
    (New-TestToken 'F' 11.5 11.9),
    (New-TestToken 'G' 12.0 12.4),
    (New-TestToken 'H' 13.0 13.4)
)

$windows = @(
    (New-TestWindow 0 10  $w0),
    (New-TestWindow 5 15  $w1),
    (New-TestWindow 8 18  $w2)
)

try {
    $result = @(Reconstruct-WhisperWindows -Windows $windows)
    Write-Host "[OK] Reconstruct-WhisperWindows termino sin excepcion"
} catch {
    Write-Host "[FAIL] Reconstruct-WhisperWindows lanzo excepcion: $_"
    exit 1
}

if ($result.Count -eq 0) {
    Write-Host "[FAIL] Resultado vacio"
    exit 1
}

$text = ($result | ForEach-Object { $_.Text }) -join ' '
Write-Host "Resultado: $text"
Write-Host "Palabras: $($result.Count)"

$expected = 'inicio A B C D E F G H'

if ($text -ne $expected) {
    Write-Host "[FAIL] Texto final inesperado"
    Write-Host "Esperado: $expected"
    Write-Host "Obtenido: $text"
    exit 1
}

if ($result.Count -ne 9) {
    Write-Host "[FAIL] Conteo inesperado: $($result.Count), esperado 9"
    exit 1
}

for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host "[FAIL] Orden temporal no monotono en indice $i"
        exit 1
    }
}

Write-Host "[OK] El ancla D sobrevivio al primer MATCH y permitio el segundo MATCH"
Write-Host "[OK] Prefijo historico conservado"
Write-Host "[OK] 9 palabras finales"
Write-Host "[OK] Orden temporal monotono"
Write-Host ""
Write-Host "=== PRUEBA ISSUE 6 PASSED ==="
exit 0
