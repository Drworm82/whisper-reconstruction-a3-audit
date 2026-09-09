# Architecture — Boundary between whisper.cpp `-ojf` and `whisper-server` `verbose_json`

**Fecha:** 2026-09-09  
**Estado:** DECISIÓN ARQUITECTÓNICA — documentada; implementación pendiente.

## 1. Contexto

La Phase 1 requiere utilizar `whisper-server` como posible worker ASR persistente, separado del proceso de captura. POC6 demostró que el servidor HTTP devuelve una salida `verbose_json` con segmentos y timestamps por palabra.

El repositorio ya dispone de `src/Import/Convert-WhisperCpp.ps1`, validado contra el formato de salida `whisper.cpp -ojf`. La revisión del código demuestra que ese adaptador no consume el contrato `verbose_json` del servidor.

## 2. Contrato actual de `Convert-WhisperCpp.ps1`

El adaptador existente exige en la raíz del JSON la propiedad `transcription`. Cada elemento de `transcription` debe contener:

- `timestamps.from`;
- `timestamps.to`;
- `tokens`.

Cada token debe contener:

- `text`;
- `offsets.from`;
- `offsets.to`.

Los timestamps de segmento se esperan como cadenas `HH:MM:SS,mmm` o `HH:MM:SS.mmm`. Los offsets de token se interpretan en milisegundos y se convierten a segundos.

Además, el adaptador filtra tokens de control como `[_BEG_]` y `[_TT_nnn]` y conserva el texto de los tokens restantes, incluido su espacio inicial, porque `Build-WhisperWords` utiliza ese espacio para detectar límites de palabra.

## 3. Contrato observado de `whisper-server` `verbose_json`

La respuesta observada del endpoint `/inference` contiene, entre otros:

```text
 task
 language
 duration
 text
 segments[]
 detected_language
 detected_language_probability
 language_probabilities
```

Cada segmento observado contiene campos como:

```text
 id
 text
 start
 end
 tokens[]
 words[]
 temperature
 avg_logprob
 no_speech_prob
```

Los elementos de `words[]` proporcionan información temporal por palabra, incluyendo:

```text
 word
 start
 end
 probability
```

Este contrato es estructuralmente diferente del contrato consumido por `Convert-WhisperCpp.ps1`.

## 4. Resultado de compatibilidad

**Resultado: INCOMPATIBLE DIRECTAMENTE.**

No debe intentarse utilizar `Convert-WhisperCpp.ps1` sobre `verbose_json` como si ambos fueran el mismo formato.

El adaptador actual fallaría en la validación inicial porque espera `transcription`, mientras que la salida del servidor observada utiliza `segments`.

Incluso si se añadiera compatibilidad superficial con `segments`, el modelo de datos también es diferente: el adaptador actual obtiene lexical tokens y sus offsets desde `tokens[].offsets`, mientras que `verbose_json` expone explícitamente `words[]` con `start` y `end`.

## 5. Decisión

**No modificar `src/Import/Convert-WhisperCpp.ps1` para soportar ambos contratos.**

Ese archivo permanece como adaptador del contrato `whisper.cpp -ojf`, cuya corrección de filtrado de tokens de control ya fue validada.

La integración de `whisper-server` deberá utilizar un adaptador separado, candidato:

```text
src/Import/Convert-WhisperServer.ps1
```

La implementación de ese adaptador queda pendiente de un POC específico. No se crea todavía el archivo ni se modifica código de producción en esta decisión.

## 6. Normalización objetivo

El nuevo adaptador deberá producir el mismo modelo normalizado que espera el pipeline posterior, evitando que `Build-WhisperWords`, `New-WhisperWindows` o `Reconstruct-WhisperWindows` tengan que conocer detalles del protocolo HTTP.

Conceptualmente:

```text
whisper.cpp -ojf ────────> Convert-WhisperCpp ────────┐
                                                       │
                                                       ├──> modelo ASR normalizado
                                                       │
whisper-server verbose_json -> Convert-WhisperServer ─┘
                                                       │
                                                       ↓
                                          word construction / windowing /
                                              reconstruction
```

La frontera de normalización permite mantener independientes los backends ASR y protege la lógica de reconstrucción ya validada.

## 7. Preguntas que el POC del nuevo adaptador debe resolver

Antes de implementar el adaptador definitivo se debe determinar, con el JSON real del servidor:

1. Si `words[]` es suficiente para reconstrucción o si también se necesita `tokens[]`.
2. Cómo conservar exactamente los espacios y la puntuación necesarios para `Build-WhisperWords`.
3. Cómo representar palabras con `start == end`, puntuación y otros casos no léxicos.
4. Cómo tratar palabras sin timestamps válidos, si aparecen.
5. Cómo mapear `segments[].start/end` y `words[].start/end` al modelo normalizado del repositorio.
6. Qué contrato deberá utilizar el futuro scheduler para ventanas parciales.

## 8. Regla de regresión

No se debe alterar el camino ya validado:

```text
whisper.cpp -ojf
    ↓
Convert-WhisperCpp
    ↓
Build-WhisperWords
    ↓
New-WhisperWindows
    ↓
Reconstruct-WhisperWindows
```

La incorporación de `whisper-server` debe ser aditiva y aislada.

## 9. Estado

### Validado

- `whisper-server` persistente ejecutándose con Vulkan/RX 6600 XT.
- `/inference` funcionando.
- `verbose_json` válido.
- Timestamps por palabra presentes.
- Incompatibilidad estructural con `Convert-WhisperCpp.ps1` establecida mediante inspección del contrato actual y del formato observado.

### Pendiente

- Diseñar e implementar `Convert-WhisperServer.ps1`.
- Crear fixture de prueba reproducible para el nuevo adaptador.
- Probar salida normalizada contra `Build-WhisperWords`.
- Probar posteriormente integración con windowing/reconstruction.
- No se ha decidido todavía la geometría final de las ventanas ni el scheduler de streaming.
