using NAudio.Wave;

Console.WriteLine("POC 4 — WASAPI Loopback + Ring Buffer + Audio Scheduler");
Console.WriteLine("Iniciando captura...");

const int TestDurationSeconds = 15;
const double WindowDurationSeconds = 5.0;
const double OverlapDurationSeconds = 1.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const double RingBufferDurationSeconds = 20.0;

using var capture = new WasapiLoopbackCapture();

var sampleRate = capture.WaveFormat.SampleRate;
var channels = capture.WaveFormat.Channels;
var bitsPerSample = capture.WaveFormat.BitsPerSample;
var bytesPerFrame = (bitsPerSample / 8) * channels;

var ringBufferCapacityFrames =
    (long)(sampleRate * RingBufferDurationSeconds);

var ringBuffer = new byte[ringBufferCapacityFrames * bytesPerFrame];

long totalFramesCaptured = 0;
long totalBytesCaptured = 0;
long droppedFramesFromRingBuffer = 0;

var stateLock = new object();
var captureStopped = false;

long nextWindowStartFrame = 0;
var generatedWindows = new List<(int Index, long StartFrame, long EndFrame, byte[] Audio)>();

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

            var ringByteOffset =
                ringFrame * bytesPerFrame;

            var bytesUntilEnd =
                ringBuffer.Length - (int)ringByteOffset;

            var bytesToCopy =
                Math.Min(remainingBytes, bytesUntilEnd);

            Buffer.BlockCopy(
                source,
                sourceOffset,
                ringBuffer,
                (int)ringByteOffset,
                bytesToCopy);

            sourceOffset += bytesToCopy;
            remainingBytes -= bytesToCopy;
            totalFramesCaptured += bytesToCopy / bytesPerFrame;
            totalBytesCaptured += bytesToCopy;
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

        var earliestAvailableFrame =
            Math.Max(
                0,
                totalFramesCaptured - ringBufferCapacityFrames);

        if (startFrame < earliestAvailableFrame)
        {
            return false;
        }

        var frameCount = endFrame - startFrame;

        if (frameCount <= 0)
        {
            return false;
        }

        var output = new byte[frameCount * bytesPerFrame];

        for (long frame = 0; frame < frameCount; frame++)
        {
            var sourceFrame = startFrame + frame;

            var ringFrame =
                sourceFrame % ringBufferCapacityFrames;

            var sourceOffset =
                (int)(ringFrame * bytesPerFrame);

            var destinationOffset =
                (int)(frame * bytesPerFrame);

            Buffer.BlockCopy(
                ringBuffer,
                sourceOffset,
                output,
                destinationOffset,
                bytesPerFrame);
        }

        audio = output;
        return true;
    }
}

void SaveWindow(
    int index,
    long startFrame,
    long endFrame,
    byte[] audio)
{
    var outputDirectory =
        Path.GetFullPath(
            Path.Combine(
                AppContext.BaseDirectory,
                "scheduler-windows"));

    Directory.CreateDirectory(outputDirectory);

    var path =
        Path.Combine(
            outputDirectory,
            $"window-{index:D2}-{startFrame / (double)sampleRate:F3}s-{endFrame / (double)sampleRate:F3}s.wav");

    using var writer =
        new WaveFileWriter(path, capture.WaveFormat);

    writer.Write(audio, 0, audio.Length);

    generatedWindows.Add(
        (index, startFrame, endFrame, audio));

    Console.WriteLine(
        $"VENTANA #{index}: " +
        $"{startFrame / (double)sampleRate:F3}s -> " +
        $"{endFrame / (double)sampleRate:F3}s | " +
        $"{audio.Length} bytes | " +
        $"{path}");
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
                SaveWindow(
                    windowIndex,
                    nextWindowStartFrame,
                    windowEndFrame,
                    audio);

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

await Task.Delay(TestDurationSeconds * 1000);

capture.StopRecording();

await schedulerTask;

long finalFrames;

lock (stateLock)
{
    finalFrames = totalFramesCaptured;
}

var capturedDuration =
    finalFrames / (double)sampleRate;

Console.WriteLine();
Console.WriteLine("=== RESULTADO ===");
Console.WriteLine($"Frames capturados: {finalFrames}");
Console.WriteLine($"Bytes capturados: {totalBytesCaptured}");
Console.WriteLine($"Duración calculada: {capturedDuration:F3}s");
Console.WriteLine(
    $"Frames descartados del ring buffer: " +
    $"{droppedFramesFromRingBuffer}");
Console.WriteLine(
    $"Ventanas generadas: {generatedWindows.Count}");
Console.WriteLine();

Console.WriteLine("=== VALIDACIÓN DE VENTANAS ===");

foreach (var window in generatedWindows)
{
    var duration =
        (window.EndFrame - window.StartFrame)
        / (double)sampleRate;

    var expectedBytes =
        (window.EndFrame - window.StartFrame)
        * bytesPerFrame;

    var sizeOk =
        window.Audio.LongLength == expectedBytes;

    Console.WriteLine(
        $"Ventana #{window.Index}: " +
        $"duración={duration:F3}s | " +
        $"bytes={window.Audio.LongLength} | " +
        $"esperados={expectedBytes} | " +
        $"tamaño={(sizeOk ? "OK" : "ERROR")}");
}

Console.WriteLine();
Console.WriteLine("POC 4 finalizado.");
