# MVP Product Definition — Educational Live Transcription and Academic Assistant

**Fecha:** 2026-09-14  
**Estado:** Definición de producto  
**Referencia funcional:** ParakeetAI (como referencia de experiencia, no como especificación de copia)

## 1. Objetivo del producto

El objetivo del proyecto es construir una aplicación de escritorio para uso educativo que permita a un estudiante entrar a una clase, curso, conferencia o contenido educativo en línea y obtener una **transcripción continua del audio que reproduce su computadora**.

En una segunda etapa, la misma aplicación incorporará un **asistente de IA académico** capaz de utilizar la transcripción de la clase y material de estudio como contexto para ayudar al estudiante a comprender o responder preguntas relacionadas con la clase.

El producto no está orientado a entrevistas de trabajo. El caso de uso principal es el aprendizaje mediante clases y cursos en línea.

## 2. Caso de uso principal

Flujo esperado:

```text
Clase / curso en línea
        ↓
Audio reproducido por la computadora
        ↓
Captura de audio del sistema
        ↓
Transcripción en tiempo real
        ↓
Reconstrucción de ventanas superpuestas
        ↓
Transcripción continua visible al estudiante
```

El usuario no debería necesitar proporcionar manualmente un archivo de audio para cada segmento de la clase. La aplicación debe poder recibir el audio mientras la clase está ocurriendo.

Las fuentes de audio pueden incluir, según las capacidades que se validen posteriormente, plataformas como videollamadas, cursos en línea, reproductores de video o cualquier otra aplicación que reproduzca audio a través del sistema.

## 3. Fase 1 — Transcripción en vivo

La primera fase del producto tiene como objetivo entregar una transcripción continua y suficientemente estable durante una clase.

Arquitectura conceptual:

```text
Windows
   │
   ▼
WASAPI / NAudio
   │
   ▼
Buffer de audio
   │
   ▼
Scheduler de ventanas
   │
   ▼
Cola de inferencia
   │
   ▼
ASR / whisper.cpp
   │
   ▼
Datos ASR normalizados
   │
   ▼
Build-WhisperWords
   │
   ▼
Reconstruct-WhisperWindows
   │
   ▼
Transcripción continua
```

### Criterio principal de éxito de la Fase 1

No basta con demostrar que un archivo de audio puede transcribirse correctamente.

El MVP debe demostrar que la cadena puede mantenerse **de forma continua durante una clase real**, procesando nuevas ventanas, reconstruyendo la transcripción y manteniendo el orden temporal sin acumulación descontrolada de errores o trabajo pendiente.

Los parámetros concretos de producción (tamaño de ventana, stride, latencia objetivo, modelo y rendimiento sostenido) deben determinarse mediante validación experimental; no se consideran fijados por este documento.

## 4. Fase 2 — Asistente académico IA

La segunda fase utiliza la transcripción como una fuente de contexto para una capa de inteligencia artificial.

Arquitectura conceptual:

```text
Transcripción de la clase
          +
Material académico del usuario
(PDF, apuntes, libros, presentaciones, etc.)
          ↓
Contexto académico
          ↓
LLM / asistente IA
          ↓
Explicación / respuesta / apoyo al estudio
```

Un caso de uso representativo es que el profesor formule una pregunta durante la clase. La aplicación podría detectar o recibir esa pregunta y generar una respuesta o explicación utilizando el contexto disponible.

Ejemplo conceptual:

```text
Profesor:
"¿Cuál es la diferencia entre el espacio percibido y el espacio concebido?"

                    ↓

Transcripción
                    ↓

Contexto de la clase + materiales
                    ↓

Asistente IA
                    ↓

Respuesta sugerida / explicación
```

La forma exacta de detección de preguntas, presentación de respuestas, selección de contexto y modelo de IA queda fuera de la Fase 1 y deberá diseñarse posteriormente.

## 5. Separación deliberada entre las fases

La transcripción y la IA se consideran subsistemas separados.

### Fase 1 debe resolver

- Captura de audio del sistema.
- Buffering y scheduling.
- Ventanas de audio.
- Inferencia ASR.
- Normalización de resultados.
- Reconstrucción de ventanas superpuestas.
- Orden temporal.
- Manejo de palabras diferidas.
- Persistencia o almacenamiento de la transcripción cuando corresponda.
- Funcionamiento continuo durante una sesión de clase.

### Fase 2 debe resolver

- Contexto de la clase.
- Materiales académicos.
- Recuperación de información relevante.
- Integración con un LLM.
- Detección o selección de preguntas.
- Generación de respuestas y explicaciones.
- Interfaz del asistente académico.

La integración de un LLM no debe utilizarse para ocultar problemas de la infraestructura de captura, ASR o reconstrucción.

## 6. Qué NO es el objetivo del producto

El proyecto no tiene como objetivo principal:

- asistencia para entrevistas laborales;
- generación de respuestas para entrevistas de trabajo;
- preparación de CV o procesos de contratación;
- copiar funcionalmente ParakeetAI;
- convertir el sistema actual de reconstrucción batch en un producto genérico sin validación;
- implementar la integración LLM antes de disponer de una transcripción en vivo suficientemente estable.

ParakeetAI se toma como **referencia de producto y experiencia de uso**, particularmente por el concepto de escucha/transcripción de conversaciones y asistencia contextual. Las decisiones de arquitectura del proyecto se mantienen independientes.

## 7. Estado actual del proyecto respecto al objetivo

A la fecha de este documento, el repositorio ya contiene pruebas de componentes fundamentales de la cadena de transcripción:

- captura WASAPI Loopback;
- buffering y scheduling de ventanas;
- cola de inferencia acotada;
- uso de whisper-server / whisper.cpp;
- normalización de resultados ASR;
- construcción de palabras normalizadas;
- reconstrucción de ventanas superpuestas;
- guardia temporal para MATCH;
- preservación de palabras diferidas al final de ejecución;
- validación con audio real de aproximadamente 125 segundos.

El Paso 6 de POC7 está documentado como **PASS / CLOSED**.

Sin embargo, esto no equivale todavía a un MVP de aplicación de escritorio para clases. Sigue siendo necesario validar la operación integrada de forma sostenida y definir la arquitectura de ejecución de la aplicación que mantendrá la captura, ASR, reconstrucción y presentación de la transcripción durante una sesión real.

## 8. Próximo objetivo técnico

Antes de implementar la segunda fase de IA, el siguiente objetivo debe ser demostrar la **transcripción continua end-to-end**:

```text
Audio del sistema
      ↓
WASAPI / NAudio
      ↓
Buffer
      ↓
Scheduler
      ↓
Cola
      ↓
ASR persistente
      ↓
Normalización
      ↓
Reconstrucción
      ↓
Transcript Store / UI futura
```

El siguiente POC debe definirse explícitamente alrededor de este objetivo y medir, como mínimo, estabilidad de ejecución, continuidad del procesamiento, backlog de la cola, orden temporal, errores de reconstrucción y comportamiento durante una sesión de duración significativa.

No se debe asumir que una prueba corta demuestra rendimiento de producción.

## 9. Principio de arquitectura

La arquitectura debe conservar una separación clara entre:

1. **captura y grabación de audio**;
2. **procesamiento ASR**;
3. **normalización y reconstrucción de transcripción**;
4. **almacenamiento/presentación de la transcripción**;
5. **asistente académico IA**.

Esto permite que una falla o reinicio del ASR no implique necesariamente pérdida del audio fuente y permite que la segunda fase de IA se construya sobre una transcripción persistente y temporalmente estructurada.

## 10. Definición resumida del producto

> **Una aplicación de escritorio para estudiantes que escucha el audio de una clase en línea, genera una transcripción continua en tiempo real y, posteriormente, utiliza esa transcripción y los materiales académicos disponibles para proporcionar asistencia mediante IA.**

La prioridad inmediata es hacer confiable la primera mitad de esta definición: **capturar, transcribir y reconstruir una clase de manera continua**.
