# POC7 Paso 12 — MVP de transcripción en vivo (sesión de duración variable + reconstrucción incremental + ventana WinForms)

**Fecha:** 2026-09-16
**Rama:** `poc7-paso12-live-mvp`
**Base:** `poc7-paso11-resilient-word-timing` @ `3429d7d`
**Commits de este paso (en orden):**
1. `9e87e76` — sesión de duración variable, detener con ENTER en vez de temporizador fijo de 130s
2. `a9f88f7` — reconstrucción incremental en vivo, TRANSCRIPT+ por ventana
3. `d18f243` — fix de encoding UTF-8 PowerShell → consola
4. `692fd7f` — idioma de transcripción configurable vía argumento (default `es`)
5. `025367e` — ventana WinForms para transcripción en vivo (hilo STA separado)

**Estado:** los 5 commits están aplicados y cada uno se validó con al menos una corrida real end-to-end antes de pasar al siguiente. No hay deuda de "código aplicado sin correr" en este paso — a diferencia de Paso 11, aquí sí se siguió la disciplina de "nunca declarar validado sin correrlo" en cada punto.

---

## Motivación / contexto de negocio

Hasta Paso 11, la app producía un transcript solo **al final** de una corrida de duración fija (130s), sin interfaz visible — un POC de validación de pipeline, no algo usable en una clase real. El objetivo explícito de Enrique para esta sesión fue: *"quiero tener un MVP funcionando, después afino lo que esté mal"* — específicamente, algo conceptualmente similar a parakeet-ai.com: capturar cualquier audio del sistema (video, Zoom, Discord — vía WASAPI loopback, ya agnóstico de fuente desde antes de este paso) y mostrar el texto transcrito en una ventana en vivo, mientras se habla.

Se investigó brevemente parakeet-ai.com (el producto de copiloto de entrevistas, no el modelo ASR de NVIDIA del mismo nombre) para no reinventar a ciegas. Conclusión: su overlay "invisible en screen-share" responde a un caso de uso (ocultarse del entrevistador) que no aplica a Enrique (apuntes de su propia clase, con OBS grabando su propia pantalla) — se descartó esa complejidad. El resto de su arquitectura (ASR en vivo → texto en pantalla → IA de sugerencias con contexto, en una fase posterior) coincide con el roadmap Fase 1 / Fase 2 ya trazado del proyecto.

---

## Cambios realizados

### 1. Sesión de duración variable (commit `9e87e76`)

Antes: `const int TestDurationSeconds = 130;` fijo, capturaba exactamente 130s y paraba.

Después: la captura corre indefinidamente; el usuario presiona **ENTER** para detenerla (`await Task.Run(() => Console.ReadLine());` en el hilo principal, en paralelo a scheduler/consumer/watchdog). El cálculo de `expectedWindows` (usado para la verificación de continuidad `captureContinuityOk`) se adaptó para derivarse de la duración real observada (`capturedFramesSnapshot / sampleRate`) en vez de la constante fija, preservando la verificación "no se perdió ninguna ventana" bajo duración variable.

**Validado:** corrida de ~24.6s, `producedJobs=5` = `expectedWindows` calculado, `POC 7 Paso 10 PASS`, `Stop reason: Normal`.

### 2. Reconstrucción incremental en vivo (commit `a9f88f7`)

Antes: la reconstrucción (`Convert-WhisperServer` → `Build-WhisperWords` → `Reconstruct-WhisperWindows`) corría **una sola vez**, al final, sobre todas las ventanas acumuladas.

Después: se extrajo el bloque de PowerShell (antes duplicado inline en el bloque final) a una función reutilizable `RunReconstructionAsync(IReadOnlyList<SuccessfulWindow> snapshot)`. Una tarea de fondo (`liveReconstructionTask`) la llama cada ~1s si hay ventanas nuevas desde la última vez, y imprime solo las palabras nuevas (`TRANSCRIPT+: ...`) comparando contra `lastPrintedWordCount`. El bloque final reusa la misma función (sin duplicar el comando PowerShell).

**Diseño deliberadamente simple, con deuda conocida:** cada ciclo recalcula la reconstrucción **desde cero** sobre todo el corpus acumulado (no es incremental a nivel algoritmo, solo a nivel de cuándo se dispara). Costo crece con la duración de la sesión — aceptable para clases de 1-2h en la forma actual, pendiente de optimizar si se vuelve un cuello de botella real (no medido aún en sesiones largas).

**Validado:** corrida de 8 ventanas — suma de palabras en las líneas `TRANSCRIPT+` (50) más las 12 palabras de la última ventana (no capturadas por el ciclo de 1s antes del stop) = 62 = `Palabras reconstruidas` del resumen final. Coincidencia exacta confirmada por conteo manual.

### 3. Fix de encoding UTF-8 (commit `d18f243`)

**Bug real encontrado**, expuesto por el cambio anterior (era la primera vez que se imprimía el texto reconstruido en consola — antes solo se imprimían conteos). Palabras con tildes/ñ salían corrompidas: `ah´┐¢` en vez de `ahí`, `L´┐¢pez` en vez de `López`. Causa raíz: Windows PowerShell 5.1 no usa UTF-8 por defecto al redirigir su salida estándar; el `Process` de .NET tampoco especificaba el encoding de lectura.

**Fix, en el único punto compartido por todas las llamadas a PowerShell (`RunPowerShellAsync`)**, no duplicado por script:
- Se antepone `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` a cualquier comando ejecutado.
- `ProcessStartInfo.StandardOutputEncoding` / `StandardErrorEncoding` fijados a `UTF8Encoding(false)`.
- Además, `Console.OutputEncoding = Encoding.UTF8;` al inicio del programa, para que la propia terminal de la app muestre bien los caracteres ya correctos.

**Validado:** misma clase de audio corrida de nuevo, comparación línea por línea — sin ningún `´┐¢`, tildes y ñ correctos (`inauguración`, `López`, `Rodríguez`, etc.).

### 4. Idioma de transcripción configurable (commit `692fd7f`)

**Bug de calidad encontrado durante la validación del fix anterior**, no relacionado con encoding: el transcript alternaba español/inglés ventana por ventana (ej. *"the government program reaffirma his compromise"*). Causa raíz: la llamada a whisper-server (`RunInferenceAsync`) nunca fijaba el parámetro `language` — el servidor detectaba el idioma en cada ventana de 5s de forma independiente, y con clips cortos/nombres propios a veces adivinaba inglés.

**Fix:** nuevo parámetro de arranque, `var language = args.Length > 0 ? args[0].Trim().ToLowerInvariant() : "es";`, usado en el form-data de cada llamada a whisper-server (`form.Add(new StringContent(language), "language");`). Default `es` sin argumentos (caso normal de Enrique); para otro idioma: `dotnet run ... -- en`. Se imprime al arrancar (`Idioma de transcripción: {language}`).

**Validado:** misma clase corrida de nuevo (~47s, 11 ventanas) — 100% español, sin ninguna palabra en inglés, `PASS`.

### 5. Ventana WinForms para transcripción en vivo (commit `025367e`)

Cambios:
- `EndToEndPOC.csproj`: `TargetFramework` cambiado de `net10.0` a `net10.0-windows`, + `<UseWindowsForms>true</UseWindowsForms>`. Efecto colateral positivo: bajó de 21 a 5 advertencias de compilación (la mayoría de las `CA1416` de plataforma desaparecieron al declarar el TFM explícitamente Windows-only, que ya era la realidad de facto por WASAPI).
- Nueva clase `LiveTranscriptWindow : Form` — un `TextBox` multilínea de solo lectura, con scroll y auto-scroll al final en cada actualización.
- La ventana corre en su **propio hilo STA** (`Thread` con `ApartmentState.STA`, marcado `IsBackground = true`), separado del flujo async principal de captura/scheduler/consumer, sincronizado al arranque con un `ManualResetEventSlim` para esperar a que el `HandleCreated` del form dispare antes de continuar con `AttachCaptureHandlers`.
- El mismo punto donde se imprime `TRANSCRIPT+:` en consola ahora también llama `liveWindow?.AppendWords(...)` con el mismo texto — consola y ventana muestran exactamente lo mismo.

**Validado:** corrida de ~60s, 14 ventanas — confirmado por Enrique que la ventana aparece y el texto se va actualizando en vivo junto con la consola. `PASS`, `Palabras reconstruidas: 114`.

---

## Bugs encontrados hoy (fuera del alcance de este paso, no corregidos)

1. **Fusión de palabras en frontera de ventana** (visto en esta sesión: `"presiden este actoestra"` seguido de `"La maestra..."` — se perdió el "ma" inicial de "maestra"). Coincide con el bug **A2** ya documentado como pendiente (pérdida de palabras en fronteras de `New-WhisperWindows` / geometría de solapamiento). No se investigó ni se tocó código hoy — queda igual de pendiente que antes, solo más visible ahora por la ventana en vivo.
2. **Errores de reconocimiento en nombres propios** (ej. "Acatlán" salió como "a Catlán" en una corrida, correcto en otra). No es un bug del pipeline, es comportamiento normal de un modelo ASR con vocabulario poco frecuente. Mitigación futura sugerida (no implementada): usar el parámetro `initial_prompt` de whisper-server para sembrar vocabulario esperado (nombres de profesores, siglas de facultades, etc.) si se vuelve un patrón recurrente.

---

## Deuda conocida (documentada, no bloqueante para el MVP actual)

- **Reconstrucción incremental es O(n) por ciclo, recalculando desde cero** — no medido en sesiones largas (1h+); el rezago creciente es una hipótesis razonada, no una medición real todavía.
- **Bug A2** (pérdida de palabras en fronteras) sigue sin arreglarse.
- **Archivos sin trackear en el repo** (backups `.bak`, logs, WAVs de pruebas viejas, `docs/*.local-backup.md`, etc.) — no bloquea nada, pero ensucia `git status`. Pendiente de `.gitignore` + limpieza, no se tocó hoy.
- **Puerto de whisper-server:** se confirmó 8080 como vigente durante esta sesión (tras un reinicio de PC, el servidor se relanzó manualmente en 8080 sin problema). Sin cambios respecto a lo que ya establecía el doc de Paso 10.

---

## Próximos pasos sugeridos (sin decidir todavía)

1. Corrida larga (10+ min) para medir el rezago real de la reconstrucción incremental conforme crece el corpus — dato pendiente, no asumido.
2. Decidir si vale la pena investigar el bug A2 ahora que es visible en vivo, o seguir priorizando MVP y posponerlo.
3. Fase 2 (deferida, sin tocar): detección de preguntas/contexto, integración LLM, sugerencias on-demand durante la clase — la ventana WinForms de hoy es la base de UI sobre la que probablemente se construiría esto (un segundo panel o modo en la misma ventana).
