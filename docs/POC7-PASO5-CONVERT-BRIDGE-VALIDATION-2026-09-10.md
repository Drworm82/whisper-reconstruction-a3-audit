# POC7 — Paso 5: bridge `whisper-server -> Convert -> Build -> Reconstruct`

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** implementación preparada para validación local

## Objetivo

Integrar el adapter ya validado `Convert-WhisperServer.ps1` dentro del harness end-to-end de POC7 y dejar preparado el flujo real:

```text
WASAPI Loopback
    -> ring buffer
    -> scheduler 5 s / 1 s overlap
    -> bounded queue
    -> whisper-server HTTP /inference
    -> raw verbose_json
    -> Convert-WhisperServer
    -> Build-WhisperWords
    -> Reconstruct-WhisperWindows
```

El objetivo de este paso no es todavía declarar validada la reconstrucción continua. La validación debe ejecutarse después de sincronizar el commit en el entorno local y comprobar el resultado real.

## Cambio implementado

`AudioCapturePOC/EndToEndPOC/Program.cs` fue actualizado para:

- capturar audio mediante WASAPI Loopback;
- mantener el ring buffer de 20 s;
- producir ventanas de 5 s con 1 s de solapamiento y paso de 4 s;
- mantener la cola acotada a 3 jobs con política experimental `DropOldest`;
- enviar cada ventana como WAV a `whisper-server` mediante `POST /inference`;
- solicitar `verbose_json`;
- guardar el JSON crudo por ventana en `bin/Debug/net10.0/raw-json/`;
- invocar `Convert-WhisperServer.ps1` mediante `powershell.exe` sin modificar el adapter;
- conservar los timestamps del adapter como relativos a cada WAV;
- aplicar el offset global de `job.StartSeconds` solamente después de la conversión, dentro del puente de reconstrucción;
- ejecutar `Build-WhisperWords` sobre los tokens normalizados;
- ejecutar `Reconstruct-WhisperWindows` sobre todas las ventanas exitosas juntas;
- comprobar orden temporal e IDs duplicados;
- reportar el resultado final del Paso 5.

## Límite arquitectónico importante

`Convert-WhisperServer` continúa representando el tiempo relativo a la respuesta HTTP. No se introdujo conocimiento del scheduler ni del `StartSeconds` global dentro del adapter.

Para las ventanas del scheduler:

```text
#00 = 0-5 s
#01 = 4-9 s
#02 = 8-13 s
```

el adapter puede devolver para cada respuesta:

```text
Start = 0
End   = 5
```

El puente end-to-end suma posteriormente el desplazamiento de cada job:

```text
#00 -> +0 s
#01 -> +4 s
#02 -> +8 s
```

Esto mantiene separadas las responsabilidades del adapter y del scheduler.

## Validación pendiente

Este commit **no declara PASS** del Paso 5. Falta ejecutar en el entorno local:

1. sincronización de `origin/reconstruction-fixes`;
2. compilación de `AudioCapturePOC/EndToEndPOC`;
3. ejecución con `whisper-server` activo;
4. comprobación de las tres respuestas HTTP reales;
5. comprobación de los JSON crudos;
6. comprobación de `Convert` para cada ventana;
7. comprobación de `Build` y `Reconstruct` sobre las ventanas globalmente desplazadas;
8. comprobación de orden temporal e IDs duplicados;
9. ejecución de la suite de tests existente.

## Evidencia anterior que se conserva

El Paso 4 ya validó formalmente la continuidad interna de segmentos de `whisper-server` a través de `Convert-WhisperServer`, `Build-WhisperWords` y `Reconstruct-WhisperWindows`. Ese resultado no se modifica.

El adapter continúa devolviendo una sola Window por respuesta HTTP, acumulando todos los `segments[].words[]` y conservando la envolvente temporal del primer/último segmento.

## Riesgos conocidos del puente

- El proceso usa Windows PowerShell 5.1 (`System32\WindowsPowerShell\v1.0\powershell.exe`) para respetar el entorno existente del proyecto.
- El JSON crudo se guarda antes de convertirlo, de modo que un fallo del adapter no elimina la evidencia de la respuesta del servidor.
- Los timestamps globales se ajustan fuera del adapter.
- `Reconstruct-WhisperWindows` emite mensajes de transición mediante `Write-Host`; el puente redirige el stream de información durante la captura del JSON final para evitar contaminar la salida estructurada.

## Commit

- `946a14947fb7e80924ece8fafc3b3fa70ad60b98` — Implement POC7 Paso 5 real ASR bridge
