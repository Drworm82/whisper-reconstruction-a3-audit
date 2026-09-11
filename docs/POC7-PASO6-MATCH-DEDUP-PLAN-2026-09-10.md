# POC7 — Paso 6: prueba controlada de MATCH / DEDUP

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** implementación preparada para validación local

## Objetivo

Obtener evidencia directa de que `Reconstruct-WhisperWindows` puede producir un `MATCH` real entre dos ventanas consecutivas cuando ambas contienen la misma habla dentro de su intervalo físico de solapamiento.

El Paso 5 validó el flujo end-to-end real, pero las dos transiciones de esa ejecución no proporcionaron evidencia de un `MATCH` lingüístico real. Este paso aísla esa pregunta sin modificar la geometría de producción del Paso 5.

## Geometría experimental

El harness utiliza deliberadamente una geometría más solapada:

| Parámetro | Valor |
|---|---:|
| Captura | WASAPI Loopback |
| Duración | 14 s |
| Ventana | 10 s |
| Solapamiento | 8 s |
| Paso | 2 s |
| Endpoint | `http://127.0.0.1:8080/inference` |
| Formato ASR | `verbose_json` |

Las primeras ventanas son:

```text
#00 = 0-10 s
#01 = 2-12 s
#02 = 4-14 s
```

Esto hace que una frase pronunciada aproximadamente entre los segundos 3 y 9 esté presente en las tres ventanas y, por tanto, en los intervalos de comparación.

Esta geometría es **experimental**. No sustituye los parámetros validados de Paso 5 (`5 s / 1 s overlap / 4 s step`).

## Procedimiento controlado

El programa muestra al usuario una frase fija para pronunciar repetidamente durante aproximadamente los segundos 3 a 9:

> Esta es una prueba controlada de coincidencia de palabras para la reconstruccion.

El objetivo es que la misma secuencia lexical aparezca en más de una respuesta de `whisper-server`.

El flujo es:

```text
WASAPI Loopback
    -> captura PCM
    -> ventanas 10 s / 8 s overlap
    -> WAV
    -> whisper-server /inference
    -> raw verbose_json
    -> Convert-WhisperServer
    -> offset global
    -> Build-WhisperWords
    -> Reconstruct-WhisperWindows
```

Los timestamps del adapter siguen siendo relativos a cada WAV. El offset global se suma fuera del adapter antes de reconstruir.

## Criterio de PASS

La prueba **solo** puede declararse PASS si la ejecución local demuestra simultáneamente:

1. al menos un `MATCH` explícito en la salida de `Reconstruct-WhisperWindows`;
2. las ventanas contienen la misma habla dentro del intervalo de solapamiento;
3. la reconstrucción termina sin IDs duplicados;
4. el orden temporal no presenta regresiones;
5. el resultado reconstruido contiene las palabras esperadas sin duplicar artificialmente la ocurrencia compartida.

Si el ASR no reconoce suficiente contenido común y todas las transiciones resultan `SIN MATCH`, el resultado será **NO MATCH / evidencia insuficiente**, no un PASS.

## Archivos

- `AudioCapturePOC/MatchDedupPOC/MatchDedupPOC.csproj`
- `AudioCapturePOC/MatchDedupPOC/Program.cs`

El harness guarda los WAV y JSON crudos en:

```text
AudioCapturePOC/MatchDedupPOC/bin/Debug/net10.0/raw-json/
```

## No cambios arquitectónicos

Este paso no modifica:

- `Convert-WhisperServer.ps1`;
- `Build-WhisperWords.ps1`;
- `Reconstruct-WhisperWindows.ps1`;
- la geometría de Paso 5;
- el adapter para introducir offsets globales.

## Validación pendiente

El código debe:

1. sincronizarse localmente;
2. compilarse;
3. ejecutarse con `whisper-server` activo;
4. producir las ventanas experimentales;
5. registrar las respuestas HTTP y los JSON crudos;
6. mostrar las transiciones `MATCH` / `SIN MATCH` emitidas por la reconstrucción;
7. registrar el resultado de invariantes.

No se declara ningún resultado antes de esa ejecución local.

## Commits de implementación

- `51e24614b617e1a6c2bb4ae757e99880109629a1` — Add controlled MATCH/DEDUP POC project
- `792779ce74c0ebaff921b795ddab0736afbc0387` — Add controlled MATCH/DEDUP POC harness
