# Project State Addendum — POC7 Paso 5

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** **PASS — validado localmente**

Este addendum actualiza el estado operativo de POC7 mientras `docs/PROJECT-STATE.md` conserva el historial previo del checkpoint.

## POC7 Paso 5

Se validó localmente el flujo end-to-end real:

```text
WASAPI Loopback
 -> ring buffer
 -> scheduler 5 s / 1 s overlap / 4 s step
 -> bounded queue (capacity 3, DropOldest)
 -> whisper-server HTTP /inference
 -> verbose_json
 -> Convert-WhisperServer
 -> Build-WhisperWords
 -> Reconstruct-WhisperWindows
```

### Compilación

```powershell
dotnet build .\AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

Resultado: **0 errores, 11 advertencias**. Las advertencias son las conocidas de `WasapiLoopbackCapture` obsoleto y `CA1416` por APIs específicas de Windows.

### Ejecución

```powershell
dotnet run --project .\AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

Resultado de captura:

- `720000` frames
- `5760000` bytes
- `15.000 s` de duración calculada
- `0` frames descartados del ring buffer
- 3 ventanas: `#00 0-5 s`, `#01 4-9 s`, `#02 8-13 s`

Resultado de cola:

- Jobs producidos: `3`
- Jobs procesados: `3`
- Jobs descartados: `0`
- Jobs pendientes: `0`
- Profundidad máxima: `1`
- Contabilidad: `3 = 3 + 0 + 0 | OK`
- Capacidad: `1 <= 3 | OK`

Resultado ASR/adapter:

| Ventana | HTTP | Segmentos | serverWords | convertedTokens | Latencia |
|---|---:|---:|---:|---:|---:|
| #00 | 200 | 2 | 13 | 13 | 2484.6 ms |
| #01 | 200 | 2 | 11 | 11 | 2397.3 ms |
| #02 | 200 | 1 | 9 | 9 | 2377.8 ms |

Las tres respuestas fueron convertidas con `Start=0.000 s`, `End=5.000 s`; el offset global permanece fuera del adapter.

Resultado Build/Reconstruct:

- Windows convertidas: `3`
- Build words por ventana: `12, 10, 8`
- Palabras reconstruidas: `30`
- Orden temporal: `OK`
- IDs duplicados: `0`
- Transiciones evaluadas: `2`

**Conclusión:** `POC7 Paso 5 PASS`.

## Qué queda demostrado

La integración de múltiples respuestas HTTP consecutivas del `whisper-server` con el adapter corregido funciona en el harness real, y las ventanas se pasan juntas a la reconstrucción con offset global aplicado fuera del adapter.

## Qué no queda demostrado todavía

Este PASS no valida todavía:

- MATCH/DEDUP real con habla repetida en los intervalos de solapamiento;
- saturación real de la cola;
- latencia end-to-end objetivo;
- watchdog/reinicio de `whisper-server`;
- reconexión del dispositivo de audio;
- operación prolongada/soak test;
- geometría final de ventanas de producción;
- integración de Fase 2/LLM.

## Referencias

- `946a14947fb7e80924ece8fafc3b3fa70ad60b98` — implementación POC7 Paso 5.
- `99b18a3484102bcb7ec9b74d54f3c9a7ae7c2475` — documentación de validación PASS del Paso 5.
