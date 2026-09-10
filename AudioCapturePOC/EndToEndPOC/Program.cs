using NAudio.Wave;

const int TestDurationSeconds = 15;
const double WindowDurationSeconds = 5.0;
const double OverlapDurationSeconds = 1.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const double RingBufferDurationSeconds = 20.0;

const int QueueCapacity = 3;
const int SimulatedInferenceMs = 500;

Console.WriteLine("POC 7 - End-to-End Integration");
Console.WriteLine("Paso 2 - Scheduler + Bounded Inference Queue");
Console.WriteLine();

using var capture = new WasapiLoopbackCapture();

var sampleRate = capture.WaveFormat.SampleRate;
var channels = capture.WaveFormat.Channels;
var bitsPerSample = capture.WaveFormat.BitsPerSample;
var bytesPerFrame = (bitsPerSample / 8) * channels;

var ringBufferCapacityFrames =
    (long)(sampleRate * RingBufferDurationSeconds);

var ringBuffer =
    new byte[ringBufferCapacityFrames * bytesPerFrame];

long totalFramesCaptured = 0;
long totalBytesCaptured = 0;
long droppedFramesFromRingBuffer = 0;

var stateLock = new object();
var captureStopped = false;

long nextWindowStartFrame = 0;

var queue = new Queue<InferenceJob>();
var queueLock = new object();
var queueSignal = new SemaphoreSlim(0);

var producedJobs = 0;
var processedJobs = 0;
var droppedJobs = 0;
var maxQueueDepth = 0;

var droppedJobIndexes = new List<int>();
var processedJobIndexes = new List<int>();

Console.WriteLine($"Formato: {capture.WaveFormat}");
Console.WriteLine($"Sample rate: {sampleRate}");
Console.WriteLine($"Canales: {channels}");
Console.WriteLine($"Bits por muestra: {bitsPerSample}");
Console.WriteLine($"Bytes por frame: {bytesPerFrame}");
Console.WriteLine($"Ring buffer: {RingBufferDurationSeconds:F1}s");
Console.WriteLine(
    $"Ventana: {WindowDurationSeconds:F1}s | " +
    $"Solapamiento: {OverlapDurationSeconds:F1}s | " +
    $"Paso: {StepSeconds:F1}s");
Console.WriteLine();
Console.WriteLine($"Cola: capacidad {QueueCapacity}");
Console.WriteLine($"Inferencia simulada: {SimulatedInferenceMs} ms");
Console.WriteLine("Overflow experimental: DropOldest");
Console.WriteLine();

void WriteToRingBuffer(byte[] source, int bytesRecorded)
{
    lock (stateLock)
    {
        var incomingFrames = bytesRecorded / bytesPerFrame;

        if (incomingFrames == 0)
        {
            return;
        }

        var currentFrame = totalFramesCaptured;
        var ringStartFrame =
            Math.Max(0, currentFrame - ringBufferCapacityFrames);

        if (currentFrame + incomingFrames - ringStartFrame >
            ringBufferCapacityFrames)
        {
            var framesToDrop =
                currentFrame + incomingFrames
                - ringStartFrame
                - ringBufferCapacityFrames;

            droppedFramesFromRingBuffer += framesToDrop;
        }

        var sourceOffset = 0;
        var remainingBytes = bytesRecorded;

        while (remainingBytes > 0)
        {
            var absoluteFrame = totalFramesCaptured;
            var ringFrame =
                absoluteFrame % ringBufferCapacityFrames;

            var ringOffset =
                ringFrame * bytesPerFrame;

            var bytesUntilRingEnd =
                ringBuffer.Length - ringOffset;

            var bytesToCopy =
                (int)Math.Min(remainingBytes, bytesUntilRingEnd);

            Buffer.BlockCopy(
                source,
                sourceOffset,
                ringBuffer,
                (int)ringOffset,
                bytesToCopy);

            sourceOffset += bytesToCopy;
            remainingBytes -= bytesToCopy;

            totalBytesCaptured += bytesToCopy;
            totalFramesCaptured +=
                bytesToCopy / bytesPerFrame;
        }
    }
}

bool TryExtractWindow(
    long startFrame,
    long endFrame,
    out byte[] audio)
{
    lock (stateLock)
    {
        audio = Array.Empty<byte>();

        if (endFrame > totalFramesCaptured)
        {
            return false;
        }

        var oldestAvailableFrame =
            Math.Max(
                0,
                totalFramesCaptured - ringBufferCapacityFrames);

        if (startFrame < oldestAvailableFrame)
        {
            return false;
        }

        var frameCount = endFrame - startFrame;

        if (frameCount <= 0)
        {
            return false;
        }

        var byteCount =
            checked((int)(frameCount * bytesPerFrame));

        audio = new byte[byteCount];

        for (long frame = 0; frame < frameCount; frame++)
        {
            var absoluteFrame = startFrame + frame;

            var sourceRingFrame =
                absoluteFrame % ringBufferCapacityFrames;

            var sourceOffset =
                checked((int)(sourceRingFrame * bytesPerFrame));

            var destinationOffset =
                checked((int)(frame * bytesPerFrame));

            Buffer.BlockCopy(
                ringBuffer,
                sourceOffset,
                audio,
                destinationOffset,
                bytesPerFrame);
        }

        return true;
    }
}

bool TryEnqueue(InferenceJob job)
{
    InferenceJob? droppedJob = null;
    int currentDepth;

    lock (queueLock)
    {
        producedJobs++;

        if (queue.Count >= QueueCapacity)
        {
            droppedJob = queue.Dequeue();
            droppedJobs++;
            droppedJobIndexes.Add(droppedJob.WindowIndex);
        }

        queue.Enqueue(job);

        currentDepth = queue.Count;

        if (currentDepth > maxQueueDepth)
        {
            maxQueueDepth = currentDepth;
        }
    }

    if (droppedJob != null)
    {
        Console.WriteLine(
            $"COLA DESCARTA #{droppedJob.WindowIndex:D2} " +
            $"→ entra #{job.WindowIndex:D2} | " +
            $"cola={currentDepth}");
    }
    else
    {
        Console.WriteLine(
            $"COLA PRODUCE #{job.WindowIndex:D2} | " +
            $"cola={currentDepth}");
    }

    queueSignal.Release();

    return true;
}

capture.DataAvailable += (_, e) =>
{
    WriteToRingBuffer(e.Buffer, e.BytesRecorded);
};

capture.RecordingStopped += (_, e) =>
{
    lock (stateLock)
    {
        captureStopped = true;
    }

    queueSignal.Release();

    if (e.Exception != null)
    {
        Console.WriteLine($"CAPTURE ERROR: {e.Exception}");
    }
    else
    {
        Console.WriteLine("Captura detenida.");
    }
};

capture.StartRecording();

Console.WriteLine(
    $"Capturando durante {TestDurationSeconds} segundos...");
Console.WriteLine();

var consumerTask = Task.Run(async () =>
{
    while (true)
    {
        InferenceJob? job = null;

        lock (queueLock)
        {
            if (queue.Count > 0)
            {
                job = queue.Dequeue();
            }
        }

        if (job != null)
        {
            int currentDepth;

            lock (queueLock)
            {
                currentDepth = queue.Count;
            }

            Console.WriteLine(
                $"  INFERENCIA #{job.WindowIndex:D2} | " +
                $"{job.StartSeconds:F1}s -> " +
                $"{job.EndSeconds:F1}s | " +
                $"cola={currentDepth}");

            await Task.Delay(SimulatedInferenceMs);

            lock (queueLock)
            {
                processedJobs++;
                processedJobIndexes.Add(job.WindowIndex);
            }

            Console.WriteLine(
                $"  COMPLETADA #{job.WindowIndex:D2}");

            continue;
        }

        bool stopped;

        lock (stateLock)
        {
            stopped = captureStopped;
        }

        bool producerFinished;

        lock (queueLock)
        {
            producerFinished = stopped && queue.Count == 0;
        }

        if (producerFinished)
        {
            break;
        }

        await queueSignal.WaitAsync();
    }
});

var schedulerTask = Task.Run(async () =>
{
    var windowIndex = 0;

    var windowFrames =
        (long)(WindowDurationSeconds * sampleRate);

    var stepFrames =
        (long)(StepSeconds * sampleRate);

    while (true)
    {
        long capturedFrames;
        bool stopped;

        lock (stateLock)
        {
            capturedFrames = totalFramesCaptured;
            stopped = captureStopped;
        }

        var windowEndFrame =
            nextWindowStartFrame + windowFrames;

        if (windowEndFrame <= capturedFrames)
        {
            if (TryExtractWindow(
                nextWindowStartFrame,
                windowEndFrame,
                out var audio))
            {
                var startSeconds =
                    nextWindowStartFrame / (double)sampleRate;

                var endSeconds =
                    windowEndFrame / (double)sampleRate;

                Console.WriteLine(
                    $"VENTANA #{windowIndex}: " +
                    $"{startSeconds:F3}s -> " +
                    $"{endSeconds:F3}s | " +
                    $"{audio.Length} bytes");

                TryEnqueue(
                    new InferenceJob(
                        WindowIndex: windowIndex,
                        StartSeconds: startSeconds,
                        EndSeconds: endSeconds,
                        Audio: audio));

                windowIndex++;
                nextWindowStartFrame += stepFrames;

                continue;
            }
        }

        if (stopped)
        {
            break;
        }

        await Task.Delay(100);
    }
});

await Task.Delay(
    TimeSpan.FromSeconds(TestDurationSeconds));

Console.WriteLine("ANTES DE STOP");
capture.StopRecording();
Console.WriteLine("DESPUÉS DE STOP");

await schedulerTask;
Console.WriteLine("SCHEDULER TERMINADO");

await consumerTask;
Console.WriteLine("CONSUMIDOR TERMINADO");

int remainingJobs;

lock (queueLock)
{
    remainingJobs = queue.Count;
}

Console.WriteLine();
Console.WriteLine("=== RESULTADO CAPTURA ===");

lock (stateLock)
{
    Console.WriteLine($"Frames capturados: {totalFramesCaptured}");
    Console.WriteLine($"Bytes capturados: {totalBytesCaptured}");

    var duration =
        totalFramesCaptured / (double)sampleRate;

    Console.WriteLine(
        $"Duración calculada: {duration:F3}s");

    Console.WriteLine(
        $"Frames descartados del ring buffer: " +
        $"{droppedFramesFromRingBuffer}");
}

Console.WriteLine();
Console.WriteLine("=== RESULTADO COLA ===");

Console.WriteLine($"Jobs producidos: {producedJobs}");
Console.WriteLine($"Jobs procesados: {processedJobs}");
Console.WriteLine($"Jobs descartados: {droppedJobs}");
Console.WriteLine($"Jobs pendientes: {remainingJobs}");
Console.WriteLine($"Profundidad máxima: {maxQueueDepth}");

Console.WriteLine();
Console.WriteLine("=== VALIDACIÓN COLA ===");

var accountingOk =
    producedJobs ==
    processedJobs +
    droppedJobs +
    remainingJobs;

var capacityOk =
    maxQueueDepth <= QueueCapacity;

Console.WriteLine(
    $"Contabilidad: " +
    $"{producedJobs} = {processedJobs} + " +
    $"{droppedJobs} + {remainingJobs} " +
    $"| {(accountingOk ? "OK" : "ERROR")}");

Console.WriteLine(
    $"Capacidad máxima: " +
    $"{maxQueueDepth} <= {QueueCapacity} " +
    $"| {(capacityOk ? "OK" : "ERROR")}");

Console.WriteLine();
Console.WriteLine("=== ORDEN DE PROCESAMIENTO ===");

foreach (var index in processedJobIndexes)
{
    Console.WriteLine($"#{index:D2}");
}

Console.WriteLine();
Console.WriteLine("=== JOBS DESCARTADOS ===");

foreach (var index in droppedJobIndexes)
{
    Console.WriteLine($"#{index:D2}");
}

Console.WriteLine();
Console.WriteLine(
    $"POC 7 Paso 2 " +
    $"{(accountingOk && capacityOk ? "PASS" : "FAIL")}.");

record InferenceJob(
    int WindowIndex,
    double StartSeconds,
    double EndSeconds,
    byte[] Audio);


