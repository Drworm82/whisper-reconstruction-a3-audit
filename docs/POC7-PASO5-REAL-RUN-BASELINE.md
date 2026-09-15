# POC 7 — Paso 5: Baseline de ejecución real y punto de retorno

**Estado:** documentación / sin cambios de lógica
**Rama:** `poc7-paso6-temporal-guard-clean`
**Commit de referencia antes de esta documentación:** `4f4d89e`
**Objetivo:** dejar registrado el estado alcanzado antes de continuar con los siguientes pasos del POC.

## 1. Alcance de esta documentación

Esta nota congela el estado de trabajo alcanzado durante el análisis de la reconstrucción temporal. No modifica la lógica de producción de captura, scheduler, conversión, alineación ni reconstrucción.

La investigación detallada de `Find-WordOverlap` y de las transiciones individuales queda pausada. Se retomará únicamente si el resultado completo del sistema muestra un problema que requiera volver a esta zona.

## 2. Ejecución real con audio

Se ejecutó el POC con audio real capturado, no con una reconstrucción aislada.

Parámetros observados:

- Formato: 32-bit IEEEFloat, 48000 Hz, 2 canales.
- Ring buffer: 20 s.
- Ventana: 5 s.
- Overlap: 1 s.
- Step: 4 s.
- Capacidad de cola: 3.
- Política: `DropOldest`.
- Servidor Whisper: localhost:8080.
- Duración de captura: ~129.97 s.
- Jobs producidos: 32.
- Jobs procesados: 32.
- Jobs descartados: 0.
- Máxima profundidad de cola: 1.

## 3. Resultado de conversión y reconstrucción

En la ejecución real:

- Ventanas convertidas correctamente: 30.
- Ventanas con fallo de conversión: 2.
- Transiciones evaluadas: 29.
- Palabras reconstruidas: 250.
- Orden temporal: correcto.
- IDs duplicados: 0.

Por lo tanto, captura, scheduler y cola no presentaron pérdida de jobs en esta ejecución. La reconstrucción sí llegó a ejecutarse sobre las ventanas convertidas.

## 4. Fallos observados de Whisper / conversión

Los dos fallos fueron errores de timing invertido en la entrada de Whisper:

### Ventana #10

`Inverted whisper-server word timing for ' Lore': 3.66 > 3.29.`

### Ventana #27

`Inverted whisper-server word timing for ' We': 1 > 0.42.`

Estos errores pertenecen a la validación de la respuesta de Whisper realizada por `Convert-WhisperServer`. En este punto no se ha demostrado que sean causados por la reconstrucción temporal.

## 5. Investigación de `Find-WordOverlap`

Se revisaron las transiciones de ventanas y se observó que el matcher actual exige un mínimo de 3 coincidencias para producir `MATCH`. Varias transiciones reales contienen únicamente una o dos palabras coincidentes.

También se examinó el caso de ventanas consecutivas donde Whisper produce fronteras de palabra diferentes para el mismo audio superpuesto. El caso #17/#18 fue utilizado como diagnóstico de esta situación.

Conclusión provisional:

- La diferencia de timestamps entre ventanas puede impedir un `MATCH` estricto aun cuando ambas ventanas describan la misma zona de audio.
- Esto todavía no constituye, por sí solo, evidencia de que la reconstrucción final sea incorrecta.
- No se modificó el umbral de `Find-WordOverlap`.
- No se integró el matcher experimental `Find-WordOverlap-MatchGuard.ps1`.
- No se modificó la ruta `SIN MATCH`.

## 6. Reglas que quedan congeladas por ahora

Mientras avancemos al siguiente paso, mantener sin cambios:

- El temporal placement guard de producción.
- La lógica actual de `MATCH` / `SIN MATCH`.
- La lógica de deduplicación temporal de `SIN MATCH`.
- La caracterización de huérfanos `DEFERRED` ya documentada.
- El matcher experimental no integrado.
- El comportamiento de `Convert-WhisperServer` frente a timestamps invertidos.

## 7. Instrumentación de audio

Para poder regresar a evidencia reproducible se añadió instrumentación de auditoría de audio en `Program.cs`.

Las ventanas capturadas se guardan como WAV en:

`AudioCapturePOC/EndToEndPOC/bin/Debug/net10.0/audit-audio/`

La instrumentación utilizada guarda cada ventana individual como `window-XX.wav`. No se añadió un `master.wav`.

La instrumentación fue compilada correctamente; los warnings WASAPI/plataforma existentes no impidieron la ejecución.

## 8. Punto de retorno

Si en los siguientes pasos aparece cualquiera de estos síntomas:

- palabras duplicadas,
- palabras perdidas,
- palabras fuera de orden,
- fragmentación incorrecta de palabras,
- reconstrucción incorrecta de las zonas de overlap,
- exceso de `SIN MATCH`,
- comportamiento incorrecto de `DEFERRED`,

se debe regresar primero a esta baseline y analizar:

1. la salida raw de Whisper de las ventanas afectadas;
2. la geometría temporal de su overlap;
3. `Find-WordOverlap`;
4. la ruta `SIN MATCH` y sus reglas de deduplicación;
5. el temporal placement guard;
6. la conversión de timestamps de Whisper.

No asumir que el problema está en `Find-WordOverlap` sin evidencia del resultado final.

## 9. Decisión para continuar

**No realizar más tuning de la reconstrucción en este momento.**

El siguiente objetivo es avanzar con el flujo completo del POC y evaluar el resultado final. Si aparece un defecto observable, se utilizará esta baseline como punto de retorno para aislarlo.

**Principio de trabajo:** avanzar primero; diagnosticar profundamente solo cuando un resultado concreto indique dónde está el fallo.
