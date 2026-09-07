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
#   W2 [8,18]  -> D E F + G H
#
# En W0->W1, A B C forman el MATCH. D E F G quedan como "after" y se
# conservan en finalWords, pero D no pertenece al currOverlap de la primera
# transicion porque esta despues de 10s.
#
# En W1->W2, D E F G forman el MATCH. El test verifica que el estado del
# mapa permita continuar sin perder la historia ni el contenido posterior.

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

# Build-WhisperWords usa el espacio inicial del token para detectar una
# frontera de palabra. El primer token de cada palabra no inicial lleva
# espacio; asi reproducimos la semantica de tokens de WhisperX.
function T {
    param([string]$Text, [double]$From, [double]$To)
    New-TestToken $Text $From $To
}

# W0 [0,10]: historia inicial + A B C.
$w0 = @(
    (T 'inicio' 1.0 1.5),
    (T ' A'     6.0 6.4),
    (T ' B'     6.5 6.9),
    (T ' C'     7.0 7.4)
)

# W1 [5,15]: A B C forman el MATCH. D E F G estan despues del overlap
# [5,10] y se conservan como contenido nuevo de la ventana.
$w1 = @(
    (T ' A' 6.0 6.4),
    (T ' B' 6.5 6.9),
    (T ' C' 7.0 7.4),
    (T ' D' 10.5 10.9),
    (T ' E' 11.0 11.4),
    (T ' F' 11.5 11.9),
    (T ' G' 12.0 12.4)
)

# W2 [8,18]: D E F G estan en el overlap [8,15] y deben formar el
# segundo MATCH. H queda como contenido posterior.
$w2 = @(
    (T ' D' 10.5 10.9),
    (T ' E' 11.0 11.4),
    (T ' F' 11.5 11.9),
    (T ' G' 12.0 12.4),
    (T ' H' 13.0 13.4)
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
