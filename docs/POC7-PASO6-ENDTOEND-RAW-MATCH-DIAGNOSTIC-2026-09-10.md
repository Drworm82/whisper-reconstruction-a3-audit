# POC7 — Paso 6: diagnóstico MATCH/DEDUP sobre captura End-to-End

Fecha: 2026-09-10

## Objetivo

Inspeccionar la reconstrucción producida por una ejecución real de `AudioCapturePOC/EndToEndPOC` sin repetir la captura ni modificar los componentes ya validados.

La ejecución End-to-End válida más reciente produjo tres ventanas, 0 descartes de cola y 27 palabras reconstruidas con orden temporal correcto e IDs sin duplicar. La salida del harness, sin embargo, no expone los mensajes `MATCH`/`SIN MATCH` de `Reconstruct-WhisperWindows`, por lo que todavía no constituye evidencia suficiente sobre la lógica de MATCH/DEDUP con audio real.

## Cambio

Se añadió:

- `AudioCapturePOC/EndToEndPOC/InspectEndToEndRaw.ps1`

El inspector reutiliza exclusivamente:

- `Convert-WhisperServer.ps1`
- `Build-WhisperWords.ps1`
- `Find-WordOverlap.ps1`
- `Reconstruct-WhisperWindows.ps1`

Lee los tres JSON ya generados por EndToEndPOC y aplica los offsets globales de la geometría real:

- ventana 00: `0.0 s`
- ventana 01: `4.0 s`
- ventana 02: `8.0 s`

El script muestra directamente la salida de reconstrucción, incluyendo `MATCH`/`SIN MATCH`, y calcula:

- palabras construidas por ventana;
- palabras reconstruidas;
- número de transiciones;
- IDs duplicados;
- violaciones de orden temporal;
- resultado agregado de invariantes.

## Alcance

Este cambio es diagnóstico. No modifica:

- `Convert-WhisperServer.ps1`;
- `Build-WhisperWords.ps1`;
- `Find-WordOverlap.ps1`;
- `Reconstruct-WhisperWindows.ps1`;
- la geometría de EndToEndPOC;
- el servidor whisper.cpp.

## Prueba pendiente

Debe ejecutarse una nueva captura End-to-End para obtener JSON frescos y posteriormente ejecutar el inspector sobre esos JSON.

**Importante:** antes de iniciar la captura, debe estar reproduciéndose audio en Windows. El POC usa WASAPI loopback y no se debe asumir que el audio está activo.

No se declara PASS de Paso 6 hasta observar evidencia real de las transiciones y verificar las invariantes correspondientes.

## Commit

`c95a0839e997b591566771b354e26a764918567d` — Add EndToEnd raw JSON MATCH diagnostics
