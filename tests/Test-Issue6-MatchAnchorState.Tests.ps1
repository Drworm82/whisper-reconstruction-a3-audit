# PRUEBA ISSUE 6 — ESTADO DEL ANCLA DESPUES DE MATCH
#
# Reproduce la secuencia en la que un MATCH reconstruye finalWords usando
# currentOverlap, pero el siguiente MATCH necesita como ancla una palabra
# que ya sobrevivio en finalWords y no pertenece al currOverlap inmediato.
#
# El comportamiento correcto es que el segundo MATCH pueda localizar el
# ancla por Id y continuar reconstruyendo sin:
#   ERROR: EL ELEMENTO DEL MATCH NO TIENE MAPA
#
# Este test NO modifica produccion. Solo verifica la regresion descrita.

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$projectRoot\src\Load-WhisperReconstruction.ps1"

Write-Host "=== PRUEBA ISSUE 6: ESTADO DEL ANCLA DESPUES DE MATCH ==="
Write-Host ""

function New-TestWord {
    param(
        [int]$Id,
        [string]$Text,
        [double]$From,
        [double]$To
    )

    $key = ($Text.ToLower() -replace '[^a-z0-9áéíóúüñ]', '')

    [PSCustomObject]@{
        Id   = $Id
        Text = $Text
        From = $From
        To   = $To
        Key  = $key
    }
}

function New-TestWindow {
    param(
        [double]$Start,
        [double]$End,
        [object[]]$Words
    )

    [PSCustomObject]@{
        Start = $Start
        End   = $End
        Words = @($Words)
    }
}

# W0: historia inicial.
$w0 = @(
    (New-TestWord  1 'uno'     0.2 0.7),
    (New-TestWord  2 'dos'     0.8 1.3),
    (New-TestWord  3 'tres'    1.4 1.9),
    (New-TestWord  4 'cuatro'  2.0 2.6),
    (New-TestWord  5 'cinco'   2.7 3.3),
    (New-TestWord  6 'seis'    3.4 3.9),
    (New-TestWord  7 'siete'   4.0 4.6),
    (New-TestWord  8 'ocho'    5.0 5.5),
    (New-TestWord  9 'nueve'   5.6 6.2)
)

# W1 comparte un bloque con W0. El MATCH debe anclar la historia en
# 'seis/siete/ocho' y reconstruir conservando el prefijo anterior.
$w1 = @(
    (New-TestWord  6 'seis'    3.4 3.9),
    (New-TestWord  7 'siete'   4.0 4.6),
    (New-TestWord  8 'ocho'    5.0 5.5),
    (New-TestWord 10 'diez'    6.3 6.9),
    (New-TestWord 11 'once'    7.0 7.6),
    (New-TestWord 12 'doce'    7.7 8.3)
)

# W2 contiene como overlap inmediato solo el tramo final de W1, pero
# su MATCH posterior debe poder usar 'diez' (ID 10), que ya forma parte
# de finalWords pero no necesariamente del overlap que genero el mapa.
$w2 = @(
    (New-TestWord 11 'once'    7.0 7.6),
    (New-TestWord 12 'doce'    7.7 8.3),
    (New-TestWord 13 'trece'   8.4 9.0),
    (New-TestWord 14 'catorce' 9.1 9.7),
    (New-TestWord 15 'quince'  9.8 10.4)
)

$windows = @(
    (New-TestWindow 0 6  $w0),
    (New-TestWindow 3 9  $w1),
    (New-TestWindow 6 12 $w2)
)

# El fixture se ejecuta directamente contra el reconstruidor para aislar
# el estado entre transiciones. Los objetos ya contienen Id/Key/tiempos.
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

$hasErrorAnchor = $false
foreach ($w in $result) {
    if ($null -eq $w.Id) {
        $hasErrorAnchor = $true
        break
    }
}

if ($text -notmatch 'uno.*dos.*tres') {
    Write-Host "[FAIL] Se perdio el prefijo historico tras los MATCH"
    exit 1
}

if ($text -notmatch 'diez.*once.*doce') {
    Write-Host "[FAIL] Se perdio la secuencia reconstruida despues del primer MATCH"
    exit 1
}

if ($text -notmatch 'trece.*catorce.*quince') {
    Write-Host "[FAIL] Se perdio contenido posterior al segundo MATCH"
    exit 1
}

if ($result.Count -ne 15) {
    Write-Host "[FAIL] Conteo inesperado: $($result.Count), esperado 15"
    exit 1
}

for ($i = 1; $i -lt $result.Count; $i++) {
    if ($result[$i].From -lt $result[$i - 1].From) {
        Write-Host "[FAIL] Orden temporal no monotono en indice $i"
        exit 1
    }
}

Write-Host "[OK] Prefijo historico conservado"
Write-Host "[OK] Secuencia intermedia conservada"
Write-Host "[OK] Contenido posterior conservado"
Write-Host "[OK] 15 palabras"
Write-Host "[OK] Orden temporal monotono"
Write-Host ""
Write-Host "=== PRUEBA ISSUE 6 PASSED ==="
exit 0
