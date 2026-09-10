using NAudio.Wave;

const int TestDurationSeconds = 15;
const double WindowDurationSeconds = 5.0;
const double OverlapDurationSeconds = 1.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const double RingBufferDurationSeconds = 20.0;

Console.WriteLine("POC 7 - End-to-End Integration");
Console.WriteLine("Paso 1 - WASAPI Loopback + Ring Buffer + Scheduler");
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

var generatedWindows =
    new List<(int Index, long StartFrame, long EndFrame, byte[] Audio)>();

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
                (int)bytesToCopy);

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
                generatedWindows.Add(
                    (
                        windowIndex,
                        nextWindowStartFrame,
                        windowEndFrame,
                        audio
                    ));

                Console.WriteLine(
                    $"VENTANA #{windowIndex}: " +
                    $"{nextWindowStartFrame / (double)sampleRate:F3}s -> " +
                    $"{windowEndFrame / (double)sampleRate:F3}s | " +
                    $"{audio.Length} bytes");

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

capture.StopRecording();

await schedulerTask;

Console.WriteLine();
Console.WriteLine("=== RESULTADO ===");

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

Console.WriteLine(
    $"Ventanas generadas: {generatedWindows.Count}");

Console.WriteLine();
Console.WriteLine("=== VALIDACIÓN DE VENTANAS ===");

foreach (var window in generatedWindows)
{
    var expectedBytes =
        checked((int)(
            (window.EndFrame - window.StartFrame)
            * bytesPerFrame));

    var duration =
        (window.EndFrame - window.StartFrame)
        / (double)sampleRate;

    var sizeOk =
        window.Audio.Length == expectedBytes;

    Console.WriteLine(
        $"Ventana #{window.Index}: " +
        $"duración={duration:F3}s | " +
        $"bytes={window.Audio.Length} | " +
        $"esperados={expectedBytes} | " +
        $"tamaño={(sizeOk ? "OK" : "ERROR")}");
}

Console.WriteLine();
Console.WriteLine("Paso 1 finalizado.");
