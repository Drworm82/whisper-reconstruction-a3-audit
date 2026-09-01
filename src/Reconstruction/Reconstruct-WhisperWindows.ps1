# ============================================================
# Reconstruct-WhisperWindows
# ============================================================

function Reconstruct-WhisperWindows {
    param($windows)

    if ($null -eq $windows -or $windows.Count -eq 0) {
        return @()
    }

    for ($idx = 0; $idx -lt $windows.Count; $idx++) {
        $window = $windows[$idx]

        if (-not $window.PSObject.Properties.Match("Start").Count) {
            throw "Invalid window at index $idx : missing property 'Start'."
        }

        if (-not $window.PSObject.Properties.Match("End").Count) {
            throw "Invalid window at index $idx : missing property 'End'."
        }

        if (-not $window.PSObject.Properties.Match("Tokens").Count) {
            throw "Invalid window at index $idx : missing property 'Tokens'."
        }
    }

    # ============================================================
    # PRIMERA VENTANA
    # ============================================================

    $finalWords = @(
        Build-WhisperWords $windows[0].Tokens -WindowIndex 0
    )

    # ============================================================
    # VENTANAS SIGUIENTES
    # ============================================================

    for ($i = 1; $i -lt $windows.Count; $i++) {

        $previous = $windows[$i - 1]
        $current  = $windows[$i]

        $previousWords = @(
            Build-WhisperWords `
                $previous.Tokens `
                -WindowIndex ($i - 1)
        )

        $currentWords = @(
            Build-WhisperWords `
                $current.Tokens `
                -WindowIndex $i
        )

        # ========================================================
        # OVERLAP SEMANTICO
        #
        # No usamos la intersección temporal literal de las
        # ventanas. Las ventanas reales son consecutivas
        # (5s -> 10s, 10s -> 15s, etc.), por lo que la región
        # compartida debe aproximarse desde ambos bordes.
        # ========================================================

        $overlapSeconds = 3

        $prevOverlap = @(
            $previousWords |
            Where-Object {
                $_.To -ge ($previous.End - $overlapSeconds)
            }
        )

        $currOverlap = @(
            $currentWords |
            Where-Object {
                $_.From -le ($current.Start + $overlapSeconds)
            }
        )

        # ========================================================
        # BUSCAR MATCH
        # ========================================================

        $match = Find-WordOverlap `
            -previousWords $prevOverlap `
            -currentWords $currOverlap

        Write-Host ""
        Write-Host "============================================================"
        Write-Host "TRANSICION $($previous.Start)s -> $($current.Start)s"
        Write-Host "============================================================"

        # ========================================================
        # SIN MATCH
        # ========================================================

        if ($null -eq $match) {

            Write-Host "SIN MATCH"

            foreach ($word in $currentWords) {
                $finalWords += $word
            }

            Write-Host "PALABRAS ACUMULADAS: $($finalWords.Count)"

            continue
        }

        # ========================================================
        # VALIDAR PreviousStart
        #
        # PreviousStart pertenece a prevOverlap.
        # Necesitamos localizar ese mismo objeto por Id dentro
        # del output acumulado real.
        # ========================================================

        if (
            $match.PreviousStart -lt 0 -or
            $match.PreviousStart -ge $prevOverlap.Count
        ) {
            Write-Host "ERROR: PreviousStart invalido."
            continue
        }

        $matchedPreviousWord =
            $prevOverlap[$match.PreviousStart]

        $globalPreviousStart = -1

        for ($k = 0; $k -lt $finalWords.Count; $k++) {

            if (
                $finalWords[$k].Id -eq
                $matchedPreviousWord.Id
            ) {
                $globalPreviousStart = $k
                break
            }
        }

        if ($globalPreviousStart -lt 0) {

            Write-Host (
                "ERROR: no se encontro PreviousStart en finalWords. " +
                "Id=$($matchedPreviousWord.Id)"
            )

            continue
        }

        # ========================================================
        # VALIDAR CurrentStart
        #
        # currOverlap es un filtro de currentWords. Por tanto
        # NO asumimos que CurrentStart sea automaticamente un
        # indice de currentWords.
        #
        # Se localiza por Id.
        # ========================================================

        if (
            $match.CurrentStart -lt 0 -or
            $match.CurrentStart -ge $currOverlap.Count
        ) {
            Write-Host "ERROR: CurrentStart invalido."
            continue
        }

        $matchedCurrentWord =
            $currOverlap[$match.CurrentStart]

        $globalCurrentStart = -1

        for ($k = 0; $k -lt $currentWords.Count; $k++) {

            if (
                $currentWords[$k].Id -eq
                $matchedCurrentWord.Id
            ) {
                $globalCurrentStart = $k
                break
            }
        }

        if ($globalCurrentStart -lt 0) {

            Write-Host (
                "ERROR: no se encontro CurrentStart en currentWords. " +
                "Id=$($matchedCurrentWord.Id)"
            )

            continue
        }

        # ========================================================
        # VALIDACION DIAGNOSTICA
        #
        # PreviousConsumed / CurrentConsumed NO participan
        # en el slicing.
        # ========================================================

        $previousMatchEnd =
            $match.PreviousStart +
            $match.PreviousConsumed

        $currentMatchEnd =
            $match.CurrentStart +
            $match.CurrentConsumed

        $previousOrphanSuffix =
            $prevOverlap.Count - $previousMatchEnd

        $currentOrphanSuffix =
            $currOverlap.Count - $currentMatchEnd

        Write-Host "PreviousStart       : $($match.PreviousStart)"
        Write-Host "CurrentStart        : $($match.CurrentStart)"
        Write-Host "PreviousConsumed    : $($match.PreviousConsumed)"
        Write-Host "CurrentConsumed     : $($match.CurrentConsumed)"
        Write-Host "GlobalPreviousStart : $globalPreviousStart"
        Write-Host "GlobalCurrentStart  : $globalCurrentStart"
        Write-Host "PreviousOrphanSuffix: $previousOrphanSuffix"
        Write-Host "CurrentOrphanSuffix : $currentOrphanSuffix"

        # ========================================================
        # RECONSTRUCCION POR SUSTITUCION
        #
        # OutputNuevo =
        #     OutputPrevio[0 .. GlobalPreviousStart)
        #     +
        #     CurrentWords[GlobalCurrentStart ..]
        #
        # NO usamos PreviousConsumed.
        # NO usamos CurrentConsumed.
        # NO concatenamos el output completo anterior.
        # ========================================================

        $prefix = @()

        if ($globalPreviousStart -gt 0) {

            $prefix = @(
                $finalWords |
                Select-Object -First $globalPreviousStart
            )
        }

        $currentFromStart = @(
            $currentWords |
            Select-Object -Skip $globalCurrentStart
        )

        if ($currentFromStart.Count -eq 0) {

            Write-Host "ERROR: currentFromStart esta vacio."
            continue
        }

        $finalWords = @(
            $prefix + $currentFromStart
        )

        Write-Host "PrefixCount : $($prefix.Count)"
        Write-Host "CurrentTail : $($currentFromStart.Count)"
        Write-Host "FinalWords  : $($finalWords.Count)"

        Write-Host ""
        Write-Host "MATCH:"
        Write-Host "  $($matchedPreviousWord.Text) -> $($matchedCurrentWord.Text)"
    }

    return @($finalWords)
}
