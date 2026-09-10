# POC7 Paso 4 — Hallazgo de continuidad entre segmentos de whisper-server

**Fecha:** 2026-09-10  
**Branch:** `reconstruction-fixes`  
**Estado:** Hallazgo documentado; **sin cambios de implementación**

## 1. Resumen

Durante la validación de la integración `verbose_json → Convert-WhisperServer → Build-WhisperWords → Reconstruct-WhisperWindows` se identificó que `segments[].words[]` de whisper-server no debe tratarse como una lista de palabras lingüísticas completas.

Las unidades de `segments[].words[]` pueden ser fragmentos de token que continúan a través de la frontera entre dos `segment` internos de whisper.cpp. La frontera de `segment` es una decisión interna del decoder y no constituye una frontera lingüística confiable.

El hallazgo se demostró empíricamente con el modelo multilingüe `ggml-large-v3-turbo-q5_0.bin` y una respuesta `verbose_json` en español.

## 2. Evidencia A — procesamiento independiente por segmento

El fixture `AudioCapturePOC/poc7-language-es-turbo.json` contiene 4 segmentos y 45 unidades en `segments[].words[]`.

Una frontera problemática es:

```text
segment 0:
  facult   3.76–3.90

segment 1:
  ad       3.90–4.08
```

Al ejecutar `Build-WhisperWords` independientemente por segmento se obtiene:

```text
segment 0 → facult
segment 1 → ad
```

y, por tanto, la palabra queda artificialmente dividida como `facult ad`.

Dentro de una misma respuesta también existen fragmentos que sí se fusionan cuando permanecen en la misma llamada a `Build-WhisperWords`, por ejemplo:

```text
univers + itar + io       → universitario
facult + ades              → facultades
econom + ía               → economía
cont + ad + ur + ía        → contaduría
```

## 3. Evidencia B — continuidad global

Los 45 token units de los 4 segmentos fueron aplanados manualmente y entregados a una única llamada:

```powershell
$allWordsGlobal = @(Build-WhisperWords $allTokens 0)
```

Resultado:

```text
Tokens: 45
Words: 26
```

Texto obtenido:

```text
a través del programa universitario de gobierno, la facultad de economía y las facultades de contaduría y administración, ciencias políticas y sociales, derecho, filosofía y letras.
```

Los timestamps de las palabras fusionadas también conservan correctamente su envolvente temporal:

```text
facultad         3.76–4.08
economía         4.26–5.00
facultades       6.18–6.84
contaduría       7.05–7.60
administración,  7.68–8.20
```

## 4. Diagnóstico

El problema no está en `Build-WhisperWords`.

`Build-WhisperWords` ya implementa la continuidad requerida: utiliza el whitespace inicial de los token units para determinar nuevas palabras y fusiona correctamente fragmentos sin whitespace inicial.

Tampoco se identificó un problema de UTF-8 ni de preservación de acentos en `Convert-WhisperServer`: el adapter conserva las 45 unidades y el texto español correctamente.

El defecto está en la implementación actual de `Convert-WhisperServer`, que convierte cada `segments[]` interno de whisper-server en un objeto `Window`. Esto introduce una frontera de Window que no existe en la arquitectura de audio.

## 5. Relación real entre HTTP request y Window

POC7 Paso 3 validó que el scheduler WASAPI produce las ventanas de audio antes de la inferencia y realiza una petición HTTP por cada ventana:

```text
#00  0–5 s
#01  4–9 s
#02  8–13 s
```

Por tanto, en el flujo real:

```text
1 ventana de audio del scheduler
        =
1 petición HTTP a whisper-server
```

La respuesta de whisper-server puede contener varios `segments[]` internos, pero esos segmentos no representan varias ventanas del pipeline.

## 6. Contrato correcto

El adapter debe preservar la frontera de la ventana de audio que ya existe antes de la petición HTTP.

La forma conceptual correcta es:

```text
1 HTTP request / 1 audio Window
            │
            ▼
     whisper-server
            │
     segment 0 ─┐
     segment 1 ─┤
     segment 2 ─┼─→ token stream continuo
     segment 3 ─┘
            │
            ▼
   Convert-WhisperServer
            │
            ▼
   1 Window {Start, End, Tokens}
            │
            ▼
 Reconstruct-WhisperWindows
            │
            ▼
 Build-WhisperWords una vez
```

`Convert-WhisperServer` **no debe invocar `Build-WhisperWords`**. El contrato existente de `Reconstruct-WhisperWindows` ya realiza esa operación una vez por Window.

## 7. Cambio previsto, todavía no implementado

El cambio previsto queda acotado a `src/Import/Convert-WhisperServer.ps1`:

1. Aplanar `segments[].words[]` de una respuesta completa en un único array de token units, manteniendo el orden.
2. No utilizar la frontera interna de `segment` como frontera de Window.
3. Emitir un único objeto `{Start, End, Tokens}` por respuesta HTTP.
4. Mantener `Build-WhisperWords` fuera del adapter.
5. Mantener sin cambios `Convert-WhisperCpp.ps1` y `Reconstruct-WhisperWindows.ps1`.

Los límites `Start`/`End` del Window deberán derivarse de la respuesta completa y verificarse con más fixtures antes de aceptar la implementación como definitiva.

## 8. Estado de pruebas

### PASS

- Modelo `ggml-large-v3-turbo-q5_0.bin` identificado como modelo multilingüe y probado con `language=es`.
- `whisper-server` respondió correctamente en español.
- JSON `verbose_json` válido.
- UTF-8 y caracteres acentuados preservados.
- `Convert-WhisperServer` preserva los 45 token units del fixture actual.
- `Build-WhisperWords` produce 26 palabras correctas cuando recibe los 45 token units como una secuencia continua.
- Timestamps de las palabras fusionadas conservados.
- POC7 Paso 3 confirmó 1 petición HTTP por ventana de audio.

### No validado todavía

- Implementación corregida de `Convert-WhisperServer`.
- Test Pester formal del comportamiento esperado.
- Límites `Start`/`End` del Window para múltiples respuestas reales.
- Comportamiento con múltiples fixtures y distintas fronteras de segment.
- Integración corregida completa hasta reconstrucción.
- Saturación de la cola, watchdog, latencia y soak test.

## 9. Decisión

**No modificar `Build-WhisperWords`, `Convert-WhisperCpp` ni `Reconstruct-WhisperWindows`.**

Antes de modificar `Convert-WhisperServer`, se debe formalizar el fixture actual como prueba de regresión/contrato y verificar los límites temporales del Window.

## 10. Siguiente paso

Crear el **test Pester mínimo del contrato de continuidad** usando `poc7-language-es-turbo.json`, antes de implementar el cambio en `Convert-WhisperServer.ps1`.

El test debe demostrar que una respuesta con 4 segmentos internos y 45 token units representa **un solo Window**, y que su secuencia de tokens permite producir las 26 palabras esperadas sin pérdida de texto ni de timestamps.