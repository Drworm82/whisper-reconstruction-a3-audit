# POC6 — Persistent whisper-server con Vulkan y contrato HTTP

**Fecha:** 2026-09-09  
**Estado:** PASS — servidor persistente, inferencia HTTP y salida `verbose_json` validados.  
**Alcance:** POC de backend ASR para la arquitectura de captura en tiempo casi real. No constituye todavía una validación de streaming end-to-end.

## 1. Objetivo

Evaluar `whisper-server` como proceso independiente de inferencia para Phase 1, manteniendo separada la captura/Grabación de la inferencia ASR.

El objetivo específico fue comprobar:

- compilación limpia de `whisper-server` con Vulkan;
- ejecución con la AMD Radeon RX 6600 XT;
- disponibilidad de la interfaz HTTP local;
- inferencia sobre un WAV real producido por POC3;
- rendimiento preliminar del servidor persistente;
- disponibilidad de timestamps por palabra mediante `verbose_json`.

## 2. Entorno

- Windows.
- AMD Radeon RX 6600 XT.
- Vulkan habilitado.
- whisper.cpp commit `c122757fddf358397bb7f33b6ac3aab24a5bca04`.
- whisper.cpp versión reportada por CMake: `1.9.3-dev`.
- Modelo: `C:\whisper.cpp\ggml-base.en.bin`.
- Build limpio: `C:\whisper.cpp\build-server-test`.
- WAV de prueba: `AudioCapturePOC\poc3-bounded-buffer.wav`.
- Duración del WAV: aproximadamente 15 segundos.

## 3. Incidente de Avast

Durante el primer intento de ejecución del `whisper-server.exe` generado en el build original, Avast mostró una detección `IDP.Generic` mediante el Escudo de comportamiento y movió el ejecutable a cuarentena.

Hechos observados:

1. El ejecutable desapareció del directorio de build.
2. El intento posterior de enlazado normal encontró `LNK1104` porque el archivo de salida no podía abrirse.
3. Las pruebas de permisos mostraron que el directorio permitía escritura.
4. Se creó un build independiente en `build-server-test` para separar el problema del estado del build original.
5. El build limpio generó correctamente `whisper-server.exe`.
6. Con Avast temporalmente desactivado, el servidor limpio inició correctamente y respondió por HTTP.

Este documento **no determina que la detección de Avast sea falsa ni certifica la seguridad del binario**. Registra únicamente el comportamiento observado y la estrategia utilizada para aislar el problema de build/ejecución.

## 4. Build limpio

Configuración utilizada:

```powershell
cmake -S C:\whisper.cpp -B C:\whisper.cpp\build-server-test -DWHISPER_BUILD_SERVER=ON -DGGML_VULKAN=ON
```

Resultado: configuración exitosa con Vulkan detectado.

Build:

```powershell
cmake --build C:\whisper.cpp\build-server-test --config Release --target whisper-server
```

Resultado:

```text
whisper-server.vcxproj -> C:\whisper.cpp\build-server-test\bin\Release\whisper-server.exe
```

El ejecutable generado tuvo un tamaño de `726016` bytes.

El build limpio elimina la dependencia de conclusiones basadas exclusivamente en el estado del build original que había sufrido la cuarentena.

## 5. Ejecución con GPU

El servidor inició con:

```text
AMD Radeon RX 6600 XT (AMD proprietary driver)
use gpu = 1
flash attn = 1
gpu_device = 0
```

El modelo se cargó correctamente y el servidor anunció:

```text
whisper server listening at http://127.0.0.1:8080
```

Esto valida que el backend persistente puede ejecutarse localmente usando la RX 6600 XT mediante Vulkan.

## 6. Comprobación HTTP

Solicitud:

```powershell
Invoke-WebRequest http://127.0.0.1:8080/ -UseBasicParsing | Select-Object StatusCode,Content
```

Resultado: `HTTP 200`.

La página de inicio expuso el endpoint `/inference` y documentó el envío de archivos WAV mediante `multipart/form-data`.

## 7. Inferencia persistente

Se envió el WAV producido por POC3 mediante `/inference`.

Resultado: JSON válido con texto transcrito.

Medición realizada con `Measure-Command`:

```text
Tiempo total: 0.5224209 s
```

Para aproximadamente 15 segundos de audio, esto equivale aproximadamente a `28.7×` tiempo real.

Esta cifra es **solo un benchmark de esta ejecución**. No demuestra rendimiento sostenido durante sesiones largas ni latencia end-to-end de la futura arquitectura.

## 8. Parámetros `offset_t` y `duration`

Se realizó una prueba intentando enviar `offset_t` y `duration` como campos multipart de `/inference`.

El resultado no produjo la segmentación esperada.

La conclusión operativa es que estos parámetros no deben tratarse como campos multipart de la API `/inference` utilizada en este POC. Son parámetros de configuración de ejecución de whisper.cpp/servidor, no el mecanismo validado para solicitar una región arbitraria por petición HTTP.

Por tanto, **no se adopta esta vía para implementar el scheduler de streaming**.

## 9. Salida `verbose_json`

Se solicitó:

```text
response_format=verbose_json
```

La respuesta contiene, entre otros campos:

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

Cada segmento observado contiene:

```text
 id
 text
 start
 end
 tokens
 words[]
 temperature
 avg_logprob
 no_speech_prob
```

Los elementos de `words[]` contienen timestamps individuales y probabilidad, por ejemplo conceptualmente:

```text
word
start
end
probability
```

Esto es especialmente relevante para la arquitectura porque demuestra que el servidor persistente puede entregar **información temporal por palabra**, no únicamente texto plano.

La respuesta fue guardada localmente como fixture de prueba en:

```text
AudioCapturePOC\poc6-server-verbose.json
```

## 10. Observación sobre idioma

En la respuesta observada apareció `language: english`, mientras que `detected_language` reportó otra distribución con probabilidad baja y prácticamente uniforme.

No se considera este comportamiento una validación de detección automática de idioma. Para el POC actual, el dato importante es la estructura temporal de la salida y no la calidad de la detección de idioma.

## 11. Qué queda validado

### PASS

- `whisper-server` puede compilarse en un build limpio con `WHISPER_BUILD_SERVER=ON` y `GGML_VULKAN=ON`.
- El servidor puede ejecutarse con la RX 6600 XT mediante Vulkan.
- El endpoint HTTP local responde correctamente.
- `/inference` acepta el WAV producido por POC3.
- El servidor persistente devuelve una transcripción JSON.
- El rendimiento preliminar medido sobre el WAV de 15 s fue aproximadamente `28.7×` tiempo real.
- `verbose_json` proporciona segmentos y timestamps por palabra.
- Existe un fixture local de la salida `verbose_json` para la siguiente etapa.

## 12. Qué NO queda validado

Todavía no se ha demostrado:

- streaming real desde PCM capturado por WASAPI hasta whisper-server;
- scheduler de ventanas solapadas;
- latencia end-to-end de captura → ASR → reconstrucción;
- tamaño/periodicidad óptimos de las ventanas;
- política definitiva de overflow del pipeline de inferencia;
- recuperación automática del servidor después de un fallo;
- cambio/desaparición del dispositivo de audio durante una sesión;
- estabilidad Vulkan durante sesiones de varias horas;
- equivalencia de reconstrucción cuando las ventanas llegan incrementalmente;
- integración directa de esta salida `verbose_json` con `Convert-WhisperCpp.ps1`.

## 13. Decisión arquitectónica provisional

`whisper-server` queda como **candidato válido para el worker ASR de Phase 1**, ejecutándose como proceso independiente del capturador/Grabador.

No se integra todavía dentro del proceso de captura. La separación mantiene la posibilidad de que un fallo del backend ASR no detenga la grabación completa de la sesión.

Arquitectura provisional:

```text
Windows audio
     ↓
WASAPI Loopback / NAudio
     ↓
fan-out
 ┌───────────────┐
 │               │
 ↓               ↓
Grabación       buffer/scheduler ASR
completa             ↓
                 whisper-server
                     ↓
                salida temporal
                     ↓
              normalización/reconstrucción
```

La arquitectura de scheduler y buffer todavía debe probarse antes de congelar tamaños, frecuencia de envío o política de overflow.

## 14. Siguiente paso

Antes de modificar `Convert-WhisperCpp.ps1`, verificar el fixture `poc6-server-verbose.json` y comparar su esquema con el contrato actual del adaptador.

No se debe modificar el adaptador validado únicamente para acomodar este nuevo formato sin primero establecer si corresponde crear un adaptador específico para `whisper-server`.
