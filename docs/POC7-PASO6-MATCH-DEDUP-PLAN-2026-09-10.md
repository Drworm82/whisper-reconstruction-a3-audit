# POC7 — Paso 6: prueba controlada de MATCH / DEDUP

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** diagnóstico local preparado

## Objetivo

Obtener evidencia directa de que `Reconstruct-WhisperWindows` puede producir un `MATCH` real entre dos ventanas consecutivas cuando ambas contienen la misma habla dentro de su intervalo físico de solapamiento.

El Paso 5 validó el flujo end-to-end real, pero las dos transiciones de esa ejecución no proporcionaron evidencia de un `MATCH` lingüístico real. Este paso aísla esa pregunta sin modificar la geometría de producción del Paso 5.

## Geometría experimental

| Parámetro | Valor |
|---|---:|
| Captura | WASAPI Loopback |
| Duración | 14 s |
| Ventana | 10 s |
| Solapamiento | 8 s |
| Paso | 2 s |
| Endpoint | `http://127.0.0.1:8080/inference` |
| Formato ASR | `verbose_json` |

```text
#00 = 0-10 s
#01 = 2-12 s
#02 = 4-14 s
```

La geometría es experimental y no sustituye los parámetros de producción de Paso 5 (`5 s / 1 s overlap / 4 s step`).

## Resultado de la primera ejecución local

La ejecución del harness produjo:

```text
VENTANA #00 | segments=3 | serverWords=31 | tokens=31
VENTANA #01 | segments=3 | serverWords=30 | tokens=30
VENTANA #02 | segments=3 | serverWords=30 | tokens=30

BuildCounts = 20,24,21
ReconstructedWords = 28
DuplicateIds = 0
OrderViolations = 1
```

No aparecieron líneas `MATCH` ni `SIN MATCH` en stdout. Por tanto, **no se declara PASS**.

La ausencia de esas líneas no se interpreta todavía como fallo de `Find-WordOverlap` o de `Reconstruct-WhisperWindows`, porque el harness ejecuta PowerShell Windows PowerShell como proceso hijo y la visibilidad de `Write-Host` en stdout no quedó demostrada por esta ejecución.

Además, `OrderViolations = 1` requiere inspección antes de modificar cualquier lógica validada de reconstrucción.

## Diagnóstico añadido

Se añadió:

`AudioCapturePOC/MatchDedupPOC/InspectMatchDedup.ps1`

El inspector reutiliza los tres JSON crudos ya generados por el harness y **no vuelve a capturar audio ni llamar a whisper-server**. Su función es hacer observable el punto exacto de diagnóstico:

1. palabras construidas de cada ventana;
2. palabras de cada banda de overlap;
3. resultado directo de `Find-WordOverlap` para cada transición;
4. anchor de `PreviousStart` y `CurrentStart` cuando existe candidato;
5. secuencia final de palabras devuelta por `Reconstruct-WhisperWindows`;
6. palabras exactas implicadas en cualquier `OrderViolations`;
7. IDs duplicados.

Esto permite distinguir tres casos sin modificar la reconstrucción validada:

- **MATCH CANDIDATE: FOUND** → `Find-WordOverlap` sí encuentra evidencia de coincidencia y debemos inspeccionar cómo la reconstrucción la consume.
- **MATCH CANDIDATE: NONE** → el problema está antes de la reconstrucción, en las palabras/Keys/timestamps producidos para el overlap.
- **MATCH encontrado pero OrderViolations > 0** → existe evidencia de MATCH y, separadamente, una anomalía de orden que debe localizarse con la secuencia final impresa.

## Criterio de PASS

La prueba completa solo puede declararse PASS cuando una ejecución demuestra simultáneamente:

1. al menos un `MATCH` real o un candidato equivalente directamente observable en el diagnóstico;
2. las ventanas contienen la misma habla dentro del intervalo de solapamiento;
3. la reconstrucción termina sin IDs duplicados;
4. el orden temporal no presenta regresiones;
5. el resultado reconstruido no duplica artificialmente la ocurrencia compartida.

Si no existe evidencia suficiente de coincidencia, el resultado será **NO MATCH / evidencia insuficiente**, no un PASS.

## No cambios arquitectónicos

Este diagnóstico no modifica:

- `Convert-WhisperServer.ps1`;
- `Build-WhisperWords.ps1`;
- `Find-WordOverlap.ps1`;
- `Reconstruct-WhisperWindows.ps1`;
- la geometría de Paso 5;
- el tratamiento de offsets globales.

## Siguiente validación local

Con los JSON de la ejecución anterior todavía presentes, sincronizar el commit y ejecutar únicamente:

```powershell
git pull --rebase origin reconstruction-fixes
```

Después:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AudioCapturePOC\MatchDedupPOC\InspectMatchDedup.ps1
```

No es necesario volver a ejecutar la captura todavía. El objetivo inmediato es explicar el `OrderViolations = 1` y comprobar directamente si `Find-WordOverlap` está encontrando candidatos.

## Commits

- `51e24614b617e1a6c2bb4ae757e99880109629a1` — Add controlled MATCH/DEDUP POC project
- `792779ce74c0ebaff921b795ddab0736afbc0387` — Add controlled MATCH/DEDUP POC harness
- `16773cc771e88c01e15fd149b64dc9fb0988b413` — Expose reconstruction MATCH logs in controlled POC
- `3a7b4d8429a3e06ea386e18c1a6ce8a887a5c4db` — Clarify MATCH logs are expected in stdout
- `1213c76124bd9ae60b1e7018eb34c529a789bdc4` — Add MATCH/DEDUP diagnostic inspector
