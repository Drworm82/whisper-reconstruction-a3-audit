using System.Diagnostics;

const int QueueCapacity = 3;
const int ProducerIntervalMs = 100;
const int ConsumerProcessingMs = 500;
const int TestDurationMs = 5000;

var queue = new Queue<InferenceJob>();

var stateLock = new object();
var queueSignal = new SemaphoreSlim(0);

var produced = 0;
var processed = 0;
var dropped = 0;
var maxQueueDepth = 0;

var droppedJobs = new List<InferenceJob>();
var processedJobs = new List<InferenceJob>();

var testStopwatch = Stopwatch.StartNew();

Console.WriteLine("POC 6 — Bounded Inference Queue");
Console.WriteLine();
Console.WriteLine($"Capacidad de cola: {QueueCapacity}");
Console.WriteLine($"Intervalo productor: {ProducerIntervalMs} ms");
Console.WriteLine($"Procesamiento consumidor: {ConsumerProcessingMs} ms");
Console.WriteLine($"Duración: {TestDurationMs} ms");
Console.WriteLine("Overflow: DropOldest");
Console.WriteLine();

var producerTask = Task.Run(async () =>
{
    var windowIndex = 0;

    while (testStopwatch.ElapsedMilliseconds < TestDurationMs)
    {
        var job = new InferenceJob(
            WindowIndex: windowIndex,
            StartSeconds: windowIndex * 4.0,
            EndSeconds: windowIndex * 4.0 + 5.0,
            CreatedAt: DateTime.UtcNow);

        InferenceJob? droppedJob = null;
        int currentDepth;

        lock (stateLock)
        {
            produced++;

            if (queue.Count >= QueueCapacity)
            {
                droppedJob = queue.Dequeue();
                dropped++;

                droppedJobs.Add(droppedJob);
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
                $"DESCARTADO #{droppedJob.WindowIndex:D2} " +
                $"→ entra #{job.WindowIndex:D2} | " +
                $"cola={currentDepth}");
        }
        else
        {
            Console.WriteLine(
                $"PRODUCIDO #{job.WindowIndex:D2} | " +
                $"cola={currentDepth}");
        }

        queueSignal.Release();

        windowIndex++;

        await Task.Delay(ProducerIntervalMs);
    }
});

var consumerTask = Task.Run(async () =>
{
    while (true)
    {
        InferenceJob? job = null;

        lock (stateLock)
        {
            if (queue.Count > 0)
            {
                job = queue.Dequeue();
            }
        }

        if (job != null)
        {
            int currentDepth;

            lock (stateLock)
            {
                currentDepth = queue.Count;
            }

            Console.WriteLine(
                $"  PROCESANDO #{job.WindowIndex:D2} | " +
                $"cola={currentDepth}");

            await Task.Delay(ConsumerProcessingMs);

            lock (stateLock)
            {
                processed++;
                processedJobs.Add(job);
            }

            Console.WriteLine(
                $"  COMPLETADO #{job.WindowIndex:D2}");

            continue;
        }

        if (producerTask.IsCompleted)
        {
            break;
        }

        await queueSignal.WaitAsync();
    }

    while (true)
    {
        InferenceJob? job = null;

        lock (stateLock)
        {
            if (queue.Count > 0)
            {
                job = queue.Dequeue();
            }
            else
            {
                break;
            }
        }

        Console.WriteLine(
            $"  PROCESANDO FINAL #{job.WindowIndex:D2}");

        await Task.Delay(ConsumerProcessingMs);

        lock (stateLock)
        {
            processed++;
            processedJobs.Add(job);
        }

        Console.WriteLine(
            $"  COMPLETADO FINAL #{job.WindowIndex:D2}");
    }
});

await producerTask;
await consumerTask;

int remaining;

lock (stateLock)
{
    remaining = queue.Count;
}

Console.WriteLine();
Console.WriteLine("=== RESULTADO ===");

Console.WriteLine($"Jobs producidos: {produced}");
Console.WriteLine($"Jobs procesados: {processed}");
Console.WriteLine($"Jobs descartados: {dropped}");
Console.WriteLine($"Jobs pendientes: {remaining}");
Console.WriteLine($"Profundidad máxima: {maxQueueDepth}");
Console.WriteLine();

var accountingOk =
    produced == processed + dropped + remaining;

var capacityOk =
    maxQueueDepth <= QueueCapacity;

Console.WriteLine("=== VALIDACIÓN ===");

Console.WriteLine(
    $"Contabilidad: " +
    $"{produced} = {processed} + {dropped} + {remaining} " +
    $"| {(accountingOk ? "OK" : "ERROR")}");

Console.WriteLine(
    $"Capacidad máxima: " +
    $"{maxQueueDepth} <= {QueueCapacity} " +
    $"| {(capacityOk ? "OK" : "ERROR")}");

Console.WriteLine();

Console.WriteLine("=== JOBS DESCARTADOS ===");

foreach (var job in droppedJobs)
{
    Console.WriteLine(
        $"#{job.WindowIndex:D2} | " +
        $"{job.StartSeconds:F1}s -> {job.EndSeconds:F1}s");
}

Console.WriteLine();

Console.WriteLine("=== ORDEN DE PROCESAMIENTO ===");

foreach (var job in processedJobs)
{
    Console.WriteLine(
        $"#{job.WindowIndex:D2} | " +
        $"{job.StartSeconds:F1}s -> {job.EndSeconds:F1}s");
}

Console.WriteLine();
Console.WriteLine(
    $"POC 6 {(accountingOk && capacityOk ? "PASS" : "FAIL")}.");

record InferenceJob(
    int WindowIndex,
    double StartSeconds,
    double EndSeconds,
    DateTime CreatedAt);