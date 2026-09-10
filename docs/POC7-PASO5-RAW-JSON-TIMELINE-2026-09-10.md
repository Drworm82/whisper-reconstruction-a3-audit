# POC7 Paso 5 - Raw verbose_json y referencia temporal

## 2026-09-10

### Estado

**PREPARACION / EVIDENCIA PARCIAL - Paso 5 todavia NO validado.**

Este documento registra la evidencia obtenida al preservar las respuestas
`verbose_json` de whisper-server durante una ejecucion real del POC7.

No constituye todavia validacion de la integracion
Convert -> Build -> Reconstruct ni de MATCH/DEDUP.

### Ejecucion

Se ejecuto:

```powershell
dotnet run --project .\AudioCapturePOC\EndToEndPOC\EndToEndPOC.csproj
```

con audio real reproduciendose durante la captura.

Resultado:

- Captura: 14.980 s
- Frames: 719040
- Bytes: 5752320
- Ring buffer drops: 0
- Jobs producidos: 3
- Jobs procesados: 3
- Jobs descartados: 0
- Profundidad maxima: 1
- Inferencias exitosas: 3
- Inferencias fallidas: 0
- Orden: #00 -> #01 -> #02
- HTTP: 200 para las tres inferencias
- Resultado del Paso 3: PASS

### JSON crudo preservado

Las tres respuestas se guardaron en:

`AudioCapturePOC/EndToEndPOC/bin/Debug/net10.0/raw-json/`

Archivos:

- `window-00-verbose.json` - 1087 bytes
- `window-01-verbose.json` - 1121 bytes
- `window-02-verbose.json` - 677 bytes

### Evidencia temporal

El scheduler genero:

| Job | Linea temporal del scheduler |
|---|---|
| #00 | 0.000 -> 5.000 s |
| #01 | 4.000 -> 9.000 s |
| #02 | 8.000 -> 13.000 s |

Las tres respuestas de whisper-server contienen timestamps relativos al
archivo enviado:

| JSON | Segmento devuelto |
|---|---|
| #00 | 0.0 -> 5.0 s |
| #01 | 0.0 -> 5.0 s |
| #02 | 0.0 -> 5.0 s |

Por tanto, para llevar los timestamps de ASR a la linea temporal del
scheduler se requiere aplicar el desplazamiento correspondiente a
`InferenceJob.StartSeconds`.

Conceptualmente:

`timestamp absoluto = timestamp relativo de whisper-server + StartSeconds`

Ejemplo:

- #00: 0.0 -> 5.0 + 0.0 = 0.0 -> 5.0
- #01: 0.0 -> 5.0 + 4.0 = 4.0 -> 9.0
- #02: 0.0 -> 5.0 + 8.0 = 8.0 -> 13.0

### Texto observado

Las respuestas de esta ejecucion fueron:

- #00: `and of course to my dear friends`
- #01: `my dear colleagues who are joining us`
- #02: `Thank you.`

Las tres respuestas son diferentes y esta ejecucion no proporciona evidencia
suficiente para validar MATCH/DEDUP.

### Restricciones

- No modificar `Convert-WhisperServer.ps1` para resolver el desplazamiento temporal.
- No modificar `Build-WhisperWords.ps1`.
- No modificar `Reconstruct-WhisperWindows.ps1`.
- No cambiar la geometria de ventanas.
- No afirmar MATCH/DEDUP hasta observarlo en una prueba controlada.
- No incorporar Phase 2/LLM.

### Siguiente paso controlado

Aplicar el desplazamiento temporal de `InferenceJob.StartSeconds` en el flujo
de integracion, manteniendo el adapter como frontera de normalizacion de
whisper-server.

Despues se debera validar:

1. timestamps absolutos;
2. Convert -> Build -> Reconstruct;
3. varias respuestas consecutivas;
4. MATCH;
5. DEDUP;
6. continuidad del texto.