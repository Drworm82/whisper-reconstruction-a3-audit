# POC7 — Chuleta de continuación

**Propósito:** documento corto para reanudar el trabajo sin releer todo el repositorio.

**Branch:** `reconstruction-fixes`  
**Repositorio:** `Drworm82/whisper-reconstruction-a3-audit`  
**Último HEAD local conocido:** `162add2`  
**Checkpoint remoto posterior:** `c2c1ccb` — preparación de Paso 5.

---

## 1. Estado actual

| Paso | Estado |
|---|---|
| POC7 Paso 1 — WASAPI scheduler | PASS |
| POC7 Paso 2 — bounded queue | PASS (no saturado) |
| POC7 Paso 3 — whisper-server HTTP | PASS |
| POC7 Paso 4 — continuidad de segmentos | PASS |
| POC7 Paso 5 — integración live Convert → Build → Reconstruct | **NO VALIDADO** |

Objetivo inmediato: integrar el adapter corregido en el flujo live y validar varias respuestas HTTP consecutivas.

No incluir todavía LLM, detección de preguntas ni Phase 2.

---

## 2. Dos terminales

### Terminal servidor

```powershell
cd C:\whisper.cpp
.\build-server-test\bin\Release\whisper-server.exe -m .\ggml-large-v3-turbo-q5_0.bin --host 127.0.0.1 --port 8080
```

Debe mostrar:

```text
whisper server listening at http://127.0.0.1:8080
```

Runtime validado: **AMD Radeon RX 6600 XT + Vulkan**.

### Terminal proyecto

```powershell
cd C:\Users\Enrique\whisper-reconstruction
```

Comprobación:

```powershell
Invoke-WebRequest http://127.0.0.1:8080/ -UseBasicParsing
```

Esperado: `StatusCode : 200`.

---

## 3. NO perder el WIP local

`AudioCapturePOC/EndToEndPOC/Program.cs` está modificado localmente y corresponde al WIP real del Paso 3.

La copia de GitHub de ese archivo es un baseline anterior. **No reemplazar el WIP local con GitHub.**

También existen muchos archivos `??` de trabajo (`bin/`, `obj/`, WAV, JSON, backups, etc.).

No ejecutar:

```text
git clean
git reset --hard
```

No borrar ni sobrescribir artefactos no rastreados sin razón explícita.

---

## 4. Componentes validados: no modificar

### `src/Import/Convert-WhisperServer.ps1`

Contrato:

```text
verbose_json
  -> valida estructura y tiempos
  -> acumula todos los segments[].words[]
  -> UNA Window por respuesta HTTP
  -> Start = primer segmento
  -> End   = último segmento
  -> Tokens = unidades de palabra utilizables
```

Paso 4 corrigió el error que generaba una Window por segmento interno y podía partir palabras como `facult ad` / `administr ación`.

**No modificar el adapter para resolver el offset temporal.**

### `Build-WhisperWords.ps1`

Validado. No modificar para acomodar whisper-server.

### `Find-WordOverlap.ps1`

Cargar antes de reconstrucción:

```powershell
. .\src\Alignment\Find-WordOverlap.ps1
```

### `Reconstruct-WhisperWindows.ps1`

Validado. No modificar salvo que una regresión demostrada lo exija.

---

## 5. Hallazgo crítico de Paso 5

El `verbose_json` del servidor usa tiempos relativos al WAV enviado.

Fixture live ya inspeccionado:

```text
window-00: 0.0 -> 5.0
window-01: 0.0 -> 2.58
window-02: 0.0 -> 5.0
```

Pero el scheduler ubica esas ventanas en:

```text
#00: 0 -> 5 s
#01: 4 -> 9 s
#02: 8 -> 13 s
```

Por tanto, antes de reconstrucción, los tiempos relativos deben mapearse a la línea temporal absoluta usando la posición del `InferenceJob`, especialmente:

```text
InferenceJob.StartSeconds
```

**La correspondencia debe demostrarse con una respuesta live fresca; no asumirla.**

---

## 6. Evidencia que NO cuenta como MATCH/DEDUP

Los JSON guardados actuales contienen principalmente:

```text
#00: "♪ I say you're in it long ♪"
#01: "(upbeat music)"
#02: "[Music]"
```

Al reconstruirlos sin offset todos aparecen como `0 -> 5`, y se observaron:

```text
TRANSICION 0s -> 0s
SIN MATCH
```

Esto demuestra el problema de timestamps relativos, **no un defecto de reconstrucción**.

Tampoco demuestra MATCH/DEDUP real. Para afirmar MATCH/DEDUP debe existir contenido léxico repetido dentro de ventanas solapadas y debe observarse correctamente a través de reconstrucción.

---

## 7. Secuencia exacta para terminar Paso 5

### A. Preservar respuesta live

Cambiar únicamente el camino de `RunInferenceAsync` para conservar el `verbose_json` crudo de cada respuesta exitosa.

Luego:

1. compilar;
2. ejecutar el POC;
3. inspeccionar JSON fresco + `InferenceJob.StartSeconds`;
4. documentar la evidencia.

### B. Aplicar offset

Una vez demostrado el mapeo, aplicar el offset en la **capa de integración**.

Mantener `Convert-WhisperServer` como frontera ASR/import.

No poner el offset dentro de `Build` ni `Reconstruct`.

### C. Integrar pipeline live

```text
HTTP verbose_json
  -> Convert-WhisperServer
  -> offset absoluto del job
  -> Build-WhisperWords
  -> Reconstruct-WhisperWindows
```

Validar varias ventanas consecutivas:

- tiempos absolutos;
- tiempos de palabras;
- orden temporal;
- contabilidad de cola;
- errores HTTP/inferencia;
- ausencia de pérdida accidental de tokens;
- salida reconstruida.

### D. MATCH/DEDUP

Solo después de C, probar un caso con habla repetida en la zona de solapamiento.

### E. Documentar y commit

Cada cambio lógico debe tener:

- Markdown bajo `docs/`;
- prueba real ejecutada;
- diff revisado;
- commit descriptivo;
- SHA reportado;
- estado validado/no validado explícito.

---

## 8. Comandos mínimos útiles

Estado:

```powershell
git status --short
git log -1 --oneline
```

Cargar funciones:

```powershell
. .\src\Import\Convert-WhisperServer.ps1
. .\src\Words\Build-WhisperWords.ps1
. .\src\Alignment\Find-WordOverlap.ps1
. .\src\Reconstruction\Reconstruct-WhisperWindows.ps1
```

Probar adapter:

```powershell
$w = Convert-WhisperServer -Path .\AudioCapturePOC\SchedulerPOC\window-00-verbose.json
$w | Format-List Start,End
$w.Tokens.Count
```

Servidor:

```powershell
Invoke-WebRequest http://127.0.0.1:8080/ -UseBasicParsing
```

---

## 9. Invariantes de arquitectura

```text
Windows audio
 -> WASAPI / NAudio
 -> recording independiente
 -> scheduler
 -> bounded inference queue
 -> whisper-server persistente
 -> ASR/import adapter
 -> Build
 -> reconstruction
 -> transcript continuo
 -> Phase 2
```

La grabación completa debe permanecer independiente de fallos de ASR/reconstrucción/IA durante la experimentación.

No cambiar silenciosamente la geometría de ventanas.

---

## 10. Regla de parada

Detener y documentar si:

- los timestamps live no mapean limpiamente al timeline del scheduler;
- una prueba validada regresa FAIL;
- falla la contabilidad de cola;
- cambia la geometría de ventanas sin decisión explícita;
- la solución exige modificar Build/Reconstruct sin una regresión demostrada;
- el WIP local entra en conflicto con el estado remoto.
