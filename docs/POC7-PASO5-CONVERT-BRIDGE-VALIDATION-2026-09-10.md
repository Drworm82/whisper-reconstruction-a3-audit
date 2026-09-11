# POC7 — Paso 5: bridge `whisper-server -> Convert -> Build -> Reconstruct`

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** **PASS — validado localmente**

## Objetivo

Integrar el adapter ya validado `Convert-WhisperServer.ps1` dentro del harness end-to-end de POC7 y validar el flujo real:

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

## Cambio implementado

`AudioCapturePOC/EndToEndPOC/Program.cs` fue actualizado para:

- capturar audio mediante WASAPI Loopback;
- mantener el ring buffer de 20 s;
- producir ventanas de 5 s con 1 s de solapamiento y paso de 4 s;
- mantener la cola acotada a 3 jobs con política experimental `DropOldest`;
- enviar cada ventana como WAV a `whisper-server` mediante `POST /inference`;
- solicitar `verbose_json`;
- guardar el JSON crudo por ventana;
- invocar `Convert-WhisperServer.ps1` mediante `powershell.exe` sin modificar el adapter;
- conservar los timestamps del adapter como relativos a cada WAV;
- aplicar el offset global de `job.StartSeconds` solamente después de la conversión, dentro del puente de reconstrucción;
- ejecutar `Build-WhisperWords` sobre los tokens normalizados;
- ejecutar `Reconstruct-WhisperWindows` sobre todas las ventanas exitosas juntas;
- comprobar orden temporal e IDs duplicados;
- reportar el resultado final del Paso 5.

## Validación local

### Compilación

Comando ejecutado:

```powershell
dotnet build .\AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

Resultado:

- **0 errores**
- **11 advertencias**
- compilación correcta de `EndToEndPOC net10.0`
- las advertencias corresponden a `WasapiLoopbackCapture` obsoleto y advertencias `CA1416` por APIs específicas de Windows.

### Ejecución end-to-end

Comando ejecutado:

```powershell
dotnet run --project .\AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

Configuración observada:

```text
Formato: 32 bit IEEEFloat: 48000Hz 2 channels
Ring buffer: 20.0s
Ventana: 5.0s | Solapamiento: 1.0s | Paso: 4.0s
Cola: capacidad 3 | Overflow: DropOldest
Whisper server: http://127.0.0.1:8080/inference
```

### Captura y scheduler

```text
Frames capturados: 720000
Bytes capturados: 5760000
Duración calculada: 15.000s
Frames descartados del ring buffer: 0
```

Se produjeron exactamente tres ventanas:

```text
#00 = 0.000s -> 5.000s
#01 = 4.000s -> 9.000s
#02 = 8.000s -> 13.000s
```

### Cola

```text
Jobs producidos: 3
Jobs procesados: 3
Jobs descartados: 0
Jobs pendientes: 0
Profundidad máxima: 1
Contabilidad: 3 = 3 + 0 + 0 | OK
Capacidad máxima: 1 <= 3 | OK
```

### whisper-server + Convert

Las tres ventanas obtuvieron respuesta HTTP 200 y fueron convertidas correctamente:

| Ventana | HTTP | Segmentos | serverWords | convertedTokens | Latencia |
|---|---:|---:|---:|---:|---:|
| #00 | 200 | 2 | 13 | 13 | 2484.6 ms |
| #01 | 200 | 2 | 11 | 11 | 2397.3 ms |
| #02 | 200 | 1 | 9 | 9 | 2377.8 ms |

Para las tres respuestas, `Convert-WhisperServer` produjo una ventana relativa con `Start=0.000s` y `End=5.000s`, confirmando que el offset global no fue introducido en el adapter.

### Build + Reconstruct

Resultado reportado por el harness:

```text
Windows convertidas: 3
Build words por ventana: 12, 10, 8
Palabras reconstruidas: 30
Orden temporal: OK
IDs duplicados: 0
TRANSICIONES evaluadas: 2
```

## Resultado

**POC 7 Paso 5 PASS.**

Queda validado el flujo real local:

```text
WASAPI -> scheduler -> bounded queue -> whisper-server
       -> Convert-WhisperServer -> Build-WhisperWords
       -> Reconstruct-WhisperWindows
```

La reconstrucción se ejecutó sobre las ventanas exitosas juntas, preservando el modelo de procesamiento batch requerido por `Reconstruct-WhisperWindows`.

## Límite de la evidencia

Este PASS valida la integración end-to-end y sus invariantes observados en esta ejecución. No constituye todavía una validación de calidad lingüística de una conversación arbitraria ni una decisión final sobre la geometría de ventanas de producción.

Tampoco se modifica el resultado previamente validado del Paso 4.

## Commit de implementación

- `946a14947fb7e80924ece8fafc3b3fa70ad60b98` — Implement POC7 Paso 5 real ASR bridge

## Commit de documentación de validación

- `78d8e344698c060d28f4edc2d020a9f038217e1f` — Document POC7 Paso 5 Convert bridge validation
