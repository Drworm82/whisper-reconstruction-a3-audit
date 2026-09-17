using System.Diagnostics;
using System.Text;
using System.Text.Json;
using NAudio.Wave;

const double WindowDurationSeconds = 5.0;
const double OverlapDurationSeconds = 1.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const double RingBufferDurationSeconds = 20.0;
const int QueueCapacity = 3;
const string WhisperServerUrl = "http://127.0.0.1:8080/inference";
const double CaptureWatchdogTimeoutSeconds = 3.0;
const int WatchdogPollMs = 250;
const int MaxReconnectAttempts = 3;
const int ReconnectAttemptWaitMs = 1500;
const int ReconnectObservationMs = 3000;

Console.WriteLine("POC 7 - End-to-End Integration");
Console.WriteLine("Paso 10 - Transcripcion en vivo sin grabacion propia (OBS graba por separado)");
Console.WriteLine();

using var httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };

var capture = CreateLoopbackCapture();
var captureWaveFormat = capture.WaveFormat;
var sampleRate = captureWaveFormat.SampleRate;
var channels = captureWaveFormat.Channels;
var bitsPerSample = captureWaveFormat.BitsPerSample;
var bytesPerFrame = (bitsPerSample / 8) * channels;
var ringBufferCapacityFrames = (long)(sampleRate * RingBufferDurationSeconds);
var ringBuffer = new byte[checked((int)(ringBufferCapacityFrames * bytesPerFrame))];

long totalFramesCaptured = 0;
long totalBytesCaptured = 0;
long droppedFramesFromRingBuffer = 0;
var stateLock = new object();
var captureStopped = false;
Exception? captureException = null;
var captureStopRequested = false;
var captureStopReason = CaptureStopReason.Normal;
var watchdogSilentLossDetected = false;
var reconnectInProgress = false;
var reconnectAttempts = 0;
var reconnectSucceeded = 0;
long lastDataAvailableTick = 0;
EventHandler<WaveInEventArgs>? currentDataAvailableHandler = null;
EventHandler<StoppedEventArgs>? currentRecordingStoppedHandler = null;
long nextWindowStartFrame = 0;

var queue = new Queue<InferenceJob>();
var queueLock = new object();
var queueSignal = new SemaphoreSlim(0);
var producedJobs = 0;
var processedJobs = 0;
var droppedJobs = 0;
var maxQueueDepth = 0;
var processedJobIndexes = new List<int>();
var droppedJobIndexes = new List<int>();
var successfulWindows = new List<SuccessfulWindow>();
var timingSamples = new List<TimingSample>();
var queueDepthSeries = new List<QueueDepthSample>();
DateTime captureStartUtc = default;

var repoRoot = Directory.GetParent(AppContext.BaseDirectory)!.Parent!.Parent!.Parent!.Parent!.Parent!.FullName;
var rawJsonDirectory = Path.Combine(repoRoot, "AudioCapturePOC", "EndToEndPOC", "bin", "Debug", "net10.0", "raw-json");
Directory.CreateDirectory(rawJsonDirectory);
var auditAudioDirectory = Path.Combine(repoRoot, "AudioCapturePOC", "EndToEndPOC", "bin", "Debug", "net10.0", "audit-audio");
Directory.CreateDirectory(auditAudioDirectory);

Console.WriteLine($"Formato: {captureWaveFormat}");
Console.WriteLine($"Ring buffer: {RingBufferDurationSeconds:F1}s");
Console.WriteLine($"Ventana: {WindowDurationSeconds:F1}s | Solapamiento: {OverlapDurationSeconds:F1}s | Paso: {StepSeconds:F1}s");
Console.WriteLine($"Cola: capacidad {QueueCapacity} | Overflow: DropOldest");
Console.WriteLine($"Whisper server: {WhisperServerUrl}");
Console.WriteLine();

void WriteToRingBuffer(byte[] source, int bytesRecorded)
{
    lock (stateLock)
    {
        var incomingFrames = bytesRecorded / bytesPerFrame;
        if (incomingFrames == 0) return;

        var currentFrame = totalFramesCaptured;
        var ringStartFrame = Math.Max(0, currentFrame - ringBufferCapacityFrames);
        if (currentFrame + incomingFrames - ringStartFrame > ringBufferCapacityFrames)
        {
            droppedFramesFromRingBuffer += currentFrame + incomingFrames - ringStartFrame - ringBufferCapacityFrames;
        }

        var sourceOffset = 0;
        var remainingBytes = bytesRecorded;
        while (remainingBytes > 0)
        {
            var absoluteFrame = totalFramesCaptured;
            var ringFrame = absoluteFrame % ringBufferCapacityFrames;
            var ringOffset = checked((int)(ringFrame * bytesPerFrame));
            var bytesUntilRingEnd = ringBuffer.Length - ringOffset;
            var bytesToCopy = (int)Math.Min(remainingBytes, bytesUntilRingEnd);

            Buffer.BlockCopy(source, sourceOffset, ringBuffer, ringOffset, bytesToCopy);
            sourceOffset += bytesToCopy;
            remainingBytes -= bytesToCopy;
            totalBytesCaptured += bytesToCopy;
            totalFramesCaptured += bytesToCopy / bytesPerFrame;
        }
    }
}

bool TryExtractWindow(long startFrame, long endFrame, out byte[] audio)
{
    lock (stateLock)
    {
        audio = Array.Empty<byte>();
        if (endFrame > totalFramesCaptured) return false;

        var oldestAvailableFrame = Math.Max(0, totalFramesCaptured - ringBufferCapacityFrames);
        if (startFrame < oldestAvailableFrame) return false;

        var frameCount = endFrame - startFrame;
        if (frameCount <= 0) return false;

        var byteCount = checked((int)(frameCount * bytesPerFrame));
        audio = new byte[byteCount];
        for (long frame = 0; frame < frameCount; frame++)
        {
            var sourceRingFrame = (startFrame + frame) % ringBufferCapacityFrames;
            var sourceOffset = checked((int)(sourceRingFrame * bytesPerFrame));
            var destinationOffset = checked((int)(frame * bytesPerFrame));
            Buffer.BlockCopy(ringBuffer, sourceOffset, audio, destinationOffset, bytesPerFrame);
        }
        return true;
    }
}

bool TryEnqueue(InferenceJob job)
{
    InferenceJob? dropped = null;
    int depth;
    lock (queueLock)
    {
        producedJobs++;
        if (queue.Count >= QueueCapacity)
        {
            dropped = queue.Dequeue();
            droppedJobs++;
            droppedJobIndexes.Add(dropped.WindowIndex);
        }

        var queueEnterUtc = DateTime.UtcNow;
        queue.Enqueue(job with { QueueEnterUtc = queueEnterUtc });
        depth = queue.Count;
        maxQueueDepth = Math.Max(maxQueueDepth, depth);
        queueDepthSeries.Add(new QueueDepthSample(job.WindowIndex, depth, queueEnterUtc));
    }

    if (dropped != null)
        Console.WriteLine($"COLA DESCARTA #{dropped.WindowIndex:D2} -> entra #{job.WindowIndex:D2} | cola={depth}");
    else
        Console.WriteLine($"COLA PRODUCE #{job.WindowIndex:D2} | cola={depth}");

    queueSignal.Release();
    return true;
}

async Task<byte[]> BuildWavAsync(byte[] audio)
{
    await using var stream = new MemoryStream();
    using (var writer = new WaveFileWriter(stream, captureWaveFormat))
    {
        writer.Write(audio, 0, audio.Length);
        writer.Flush();
    }
    return stream.ToArray();
}

async Task<string> RunPowerShellAsync(string command)
{
    var encodedCommand = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
    var startInfo = new ProcessStartInfo
    {
        FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"),
        WorkingDirectory = repoRoot,
        Arguments = $"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encodedCommand}",
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
    };

    using var process = new Process { StartInfo = startInfo };
    process.Start();
    var stdoutTask = process.StandardOutput.ReadToEndAsync();
    var stderrTask = process.StandardError.ReadToEndAsync();
    await Task.WhenAll(stdoutTask, stderrTask);
    await process.WaitForExitAsync();

    var stdout = (await stdoutTask).Trim();
    var stderr = await stderrTask;
    if (process.ExitCode != 0)
        throw new InvalidOperationException($"PowerShell falló (exit code {process.ExitCode}): {stderr}");
    if (string.IsNullOrWhiteSpace(stdout))
        throw new InvalidOperationException("PowerShell no produjo salida JSON.");
    return stdout;
}

async Task<string> ConvertWithPowerShellAsync(string jsonPath)
{
    var command = $@"
. .\src\Import\Convert-WhisperServer.ps1
$result = Convert-WhisperServer -Path '{jsonPath}'
$result | ConvertTo-Json -Depth 10
";
    return await RunPowerShellAsync(command);
}

async Task<InferenceResult> RunInferenceAsync(InferenceJob job, DateTime inferenceStartUtc)
{
    var stopwatch = Stopwatch.StartNew();
    var wavBytes = await BuildWavAsync(job.Audio);
    var rawJsonPath = Path.Combine(rawJsonDirectory, $"window-{job.WindowIndex:D2}-verbose.json");

    using var form = new MultipartFormDataContent();
    using var fileContent = new ByteArrayContent(wavBytes);
    fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("audio/wav");
    form.Add(fileContent, "file", $"window-{job.WindowIndex:D2}.wav");
    form.Add(new StringContent("0.0"), "temperature");
    form.Add(new StringContent("verbose_json"), "response_format");

    using var response = await httpClient.PostAsync(WhisperServerUrl, form);
    var responseText = await response.Content.ReadAsStringAsync();
    var httpResponseUtc = DateTime.UtcNow;
    stopwatch.Stop();

    await File.WriteAllTextAsync(rawJsonPath, responseText, new UTF8Encoding(false));

    if (!response.IsSuccessStatusCode)
        return new InferenceResult(false, (int)response.StatusCode, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, 0, 0, rawJsonPath, null, $"HTTP {(int)response.StatusCode}", inferenceStartUtc, httpResponseUtc, default);

    using var document = JsonDocument.Parse(responseText);
    var root = document.RootElement;
    var segmentCount = root.TryGetProperty("segments", out var segments) ? segments.GetArrayLength() : 0;
    var wordCount = 0;
    if (root.TryGetProperty("segments", out segments))
    {
        foreach (var segment in segments.EnumerateArray())
            if (segment.TryGetProperty("words", out var words)) wordCount += words.GetArrayLength();
    }

    var convertedJson = await ConvertWithPowerShellAsync(rawJsonPath);
    var convertedWindow = JsonSerializer.Deserialize<WhisperWindow>(convertedJson, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    if (convertedWindow is null || convertedWindow.Tokens.Count == 0)
        return new InferenceResult(false, 200, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, segmentCount, wordCount, rawJsonPath, null, "Convert-WhisperServer produjo una ventana vacía o inválida.", inferenceStartUtc, httpResponseUtc, default);

    var normalizedReadyUtc = DateTime.UtcNow;

    Console.WriteLine($"INFERENCE OK #{job.WindowIndex:D2} | HTTP 200 | {stopwatch.Elapsed.TotalMilliseconds:F1} ms | segments={segmentCount} | serverWords={wordCount} | convertedTokens={convertedWindow.Tokens.Count}");
    Console.WriteLine($"CONVERT PARSED #{job.WindowIndex:D2} | Start={convertedWindow.Start:F3}s | End={convertedWindow.End:F3}s | tokens={convertedWindow.Tokens.Count}");

    return new InferenceResult(true, 200, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, segmentCount, wordCount, rawJsonPath, convertedJson, null, inferenceStartUtc, httpResponseUtc, normalizedReadyUtc);
}

WasapiLoopbackCapture CreateLoopbackCapture()
{
    return new WasapiLoopbackCapture();
}

void SignalCaptureEnd()
{
    queueSignal.Release();
}

void AttachCaptureHandlers(WasapiLoopbackCapture c)
{
    currentDataAvailableHandler = (_, e) =>
    {
        Interlocked.Exchange(ref lastDataAvailableTick, Environment.TickCount64);
        WriteToRingBuffer(e.Buffer, e.BytesRecorded);
    };
    currentRecordingStoppedHandler = (_, e) =>
    {
        lock (stateLock)
        {
            captureStopped = true;
            captureException = e.Exception;
            captureStopReason = captureStopRequested
                ? CaptureStopReason.Normal
                : CaptureStopReason.DeviceOrAudioSubsystemFailure;
        }
        SignalCaptureEnd();
        if (e.Exception != null)
            Console.WriteLine($"CAPTURE ERROR: {e.Exception}");
        else if (captureStopReason == CaptureStopReason.DeviceOrAudioSubsystemFailure)
            Console.WriteLine("CAPTURA DETENIDA INESPERADAMENTE: la captura WASAPI terminó sin haber sido solicitada por el programa.");
        else
            Console.WriteLine("Captura detenida.");
    };
    c.DataAvailable += currentDataAvailableHandler;
    c.RecordingStopped += currentRecordingStoppedHandler;
}

void StopAndDetachCurrentCapture()
{
    try
    {
        if (currentDataAvailableHandler != null) capture.DataAvailable -= currentDataAvailableHandler;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"WATCHDOG detach DataAvailable: {ex.Message}");
    }
    try
    {
        if (currentRecordingStoppedHandler != null) capture.RecordingStopped -= currentRecordingStoppedHandler;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"WATCHDOG detach RecordingStopped: {ex.Message}");
    }
    try
    {
        capture.StopRecording();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"WATCHDOG StopRecording: {ex.Message}");
    }
    try
    {
        capture.Dispose();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"WATCHDOG dispose: {ex.Message}");
    }
    currentDataAvailableHandler = null;
    currentRecordingStoppedHandler = null;
}

async Task TryRecoverCaptureAsync()
{
    lock (stateLock) reconnectInProgress = true;
    try
    {
        for (var attempt = 1; attempt <= MaxReconnectAttempts; attempt++)
        {
            bool stopped;
            bool stopRequested;
            lock (stateLock)
            {
                stopped = captureStopped;
                stopRequested = captureStopRequested;
            }
            if (stopped) return;
            if (stopRequested) return;

            Interlocked.Increment(ref reconnectAttempts);
            Console.WriteLine($"WATCHDOG RECONECTAR intento {attempt}/{MaxReconnectAttempts} | sin DataAvailable durante > {CaptureWatchdogTimeoutSeconds:F0} s");

            StopAndDetachCurrentCapture();

            WasapiLoopbackCapture? candidate = null;
            try
            {
                candidate = CreateLoopbackCapture();
                AttachCaptureHandlers(candidate);
                candidate.StartRecording();
                capture = candidate;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"WATCHDOG el intento {attempt} falló al crear/arrancar: {ex.Message}");
                lock (stateLock)
                {
                    captureException ??= ex;
                }
                try { if (candidate != null) candidate.Dispose(); } catch { }
                if (attempt < MaxReconnectAttempts)
                {
                    await Task.Delay(ReconnectAttemptWaitMs);
                    continue;
                }
                break;
            }

            var attemptStartTick = Environment.TickCount64;
            var recovered = false;
            var handoffToNormalStop = false;
            for (var observedMs = 0; observedMs < ReconnectObservationMs; observedMs += WatchdogPollMs)
            {
                await Task.Delay(WatchdogPollMs);
                lock (stateLock)
                {
                    stopped = captureStopped;
                    stopRequested = captureStopRequested;
                }
                if (stopped) break;
                if (stopRequested)
                {
                    handoffToNormalStop = true;
                    break;
                }
                if (Interlocked.Read(ref lastDataAvailableTick) > attemptStartTick)
                {
                    recovered = true;
                    break;
                }
            }

            if (recovered)
            {
                Interlocked.Increment(ref reconnectSucceeded);
                Console.WriteLine("WATCHDOG RECONEXIÓN OK: flujo reanudado con una nueva instancia WasapiLoopbackCapture.");
                return;
            }

            if (handoffToNormalStop)
            {
                Console.WriteLine("WATCHDOG abandona la reconexión: el programa solicitó la parada normal.");
                return;
            }

            Console.WriteLine($"WATCHDOG el intento {attempt} no produjo datos en {ReconnectObservationMs} ms.");
            try { candidate.DataAvailable -= currentDataAvailableHandler; } catch { }
            try { candidate.RecordingStopped -= currentRecordingStoppedHandler; } catch { }
            try { candidate.StopRecording(); } catch { }
            try { candidate.Dispose(); } catch { }
            lock (stateLock)
            {
                if (captureException == null)
                    captureException = new InvalidOperationException($"La instancia recreada (intento {attempt}) no produjo DataAvailable.");
            }
            if (attempt < MaxReconnectAttempts)
                await Task.Delay(ReconnectAttemptWaitMs);
        }

        lock (stateLock)
        {
            captureStopped = true;
            captureStopReason = CaptureStopReason.DeviceOrAudioSubsystemFailure;
            captureException ??= new InvalidOperationException("No se pudo recuperar la captura WASAPI tras la pérdida silenciosa.");
        }
        SignalCaptureEnd();
        Console.WriteLine("WATCHDOG FALLO FINAL: no se pudo recuperar la captura; el resultado será FAIL de continuidad.");
        StopAndDetachCurrentCapture();
    }
    finally
    {
        lock (stateLock) reconnectInProgress = false;
    }
}

AttachCaptureHandlers(capture);

captureStartUtc = DateTime.UtcNow;
Interlocked.Exchange(ref lastDataAvailableTick, Environment.TickCount64);
capture.StartRecording();
Console.WriteLine("Capturando... presiona ENTER para detener.");

var consumerTask = Task.Run(async () =>
{
    while (true)
    {
        InferenceJob? job = null;
        lock (queueLock)
        {
            if (queue.Count > 0) job = queue.Dequeue();
        }

        if (job != null)
        {
            try
            {
                var inferenceStartUtc = DateTime.UtcNow;
                Console.WriteLine($"INFERENCIA #{job.WindowIndex:D2} | {job.StartSeconds:F1}s -> {job.EndSeconds:F1}s");
                var result = await RunInferenceAsync(job, inferenceStartUtc);
                lock (queueLock)
                {
                    processedJobs++;
                    processedJobIndexes.Add(job.WindowIndex);
                }
                if (result.Success)
                {
                    var queueDelay = (inferenceStartUtc - job.QueueEnterUtc).TotalMilliseconds;
                    var inferenceRtt = (result.HttpResponseUtc - inferenceStartUtc).TotalMilliseconds;
                    var normalization = (result.NormalizedReadyUtc - result.HttpResponseUtc).TotalMilliseconds;
                    var captureToText = (result.NormalizedReadyUtc - job.WindowReadyUtc).TotalMilliseconds;
                    var audioEndUtc = captureStartUtc + TimeSpan.FromSeconds(job.EndSeconds);
                    var windowAge = (result.NormalizedReadyUtc - audioEndUtc).TotalMilliseconds;

                    lock (queueLock)
                    {
                        var entryDepth = queueDepthSeries.FirstOrDefault(x => x.WindowIndex == job.WindowIndex)?.Depth ?? 0;
                        successfulWindows.Add(new SuccessfulWindow(job.WindowIndex, job.StartSeconds, job.EndSeconds, result.RawJsonPath!, result.ConvertedJson!));
                        timingSamples.Add(new TimingSample(job.WindowIndex, job.StartSeconds, job.EndSeconds, entryDepth, job.WindowReadyUtc, job.QueueEnterUtc, inferenceStartUtc, result.HttpResponseUtc, result.NormalizedReadyUtc, queueDelay, inferenceRtt, normalization, captureToText, windowAge));
                    }

                    Console.WriteLine($"METRICAS #{job.WindowIndex:D2} | queueDelay={queueDelay:F1} | inferenceRTT={inferenceRtt:F1} | normalization={normalization:F1} | captureToText={captureToText:F1} | windowAge={windowAge:F1} (ms)");
                }
                else
                {
                    Console.WriteLine($"INFERENCE FAIL #{job.WindowIndex:D2} | {result.Error}");
                }
            }
            catch (Exception ex)
            {
                lock (queueLock)
                {
                    processedJobs++;
                    processedJobIndexes.Add(job.WindowIndex);
                }
                Console.WriteLine($"INFERENCE EXCEPTION #{job.WindowIndex:D2} | {ex.Message}");
            }
            continue;
        }

        bool stopped;
        lock (stateLock) stopped = captureStopped;
        bool finished;
        lock (queueLock) finished = stopped && queue.Count == 0;
        if (finished) break;
        await queueSignal.WaitAsync();
    }
});

var schedulerTask = Task.Run(async () =>
{
    var windowIndex = 0;
    var windowFrames = (long)(WindowDurationSeconds * sampleRate);
    var stepFrames = (long)(StepSeconds * sampleRate);

    while (true)
    {
        long capturedFrames;
        bool stopped;
        lock (stateLock)
        {
            capturedFrames = totalFramesCaptured;
            stopped = captureStopped;
        }

        var windowEndFrame = nextWindowStartFrame + windowFrames;
        if (windowEndFrame <= capturedFrames && TryExtractWindow(nextWindowStartFrame, windowEndFrame, out var audio))
        {
            var startSeconds = nextWindowStartFrame / (double)sampleRate;
            var endSeconds = windowEndFrame / (double)sampleRate;
            var windowReadyUtc = DateTime.UtcNow;
            var windowWav = await BuildWavAsync(audio);
            var windowPath = Path.Combine(auditAudioDirectory, $"window-{windowIndex:D2}.wav");
            await File.WriteAllBytesAsync(windowPath, windowWav);
            Console.WriteLine($"VENTANA #{windowIndex}: {startSeconds:F3}s -> {endSeconds:F3}s | {audio.Length} bytes");
            TryEnqueue(new InferenceJob(windowIndex, startSeconds, endSeconds, audio, windowReadyUtc, default));
            windowIndex++;
            nextWindowStartFrame += stepFrames;
            continue;
        }

        if (stopped) break;
        await Task.Delay(100);
    }
});

var watchdogTask = Task.Run(async () =>
{
    while (true)
    {
        await Task.Delay(WatchdogPollMs);
        bool stopped;
        bool stopRequested;
        bool recovering;
        lock (stateLock)
        {
            stopped = captureStopped;
            stopRequested = captureStopRequested;
            recovering = reconnectInProgress;
        }
        if (stopped) break;
        if (stopRequested) continue;
        if (recovering) continue;

        if (Environment.TickCount64 - Interlocked.Read(ref lastDataAvailableTick) < CaptureWatchdogTimeoutSeconds * 1000) continue;

        lock (stateLock)
        {
            watchdogSilentLossDetected = true;
            captureStopReason = CaptureStopReason.DeviceOrAudioSubsystemFailure;
        }
        Console.WriteLine("WATCHDOG: sin DataAvailable durante el tiempo límite; posible pérdida silenciosa de la captura WASAPI.");
        await TryRecoverCaptureAsync();
    }
});

await Task.Run(() => Console.ReadLine());
Console.WriteLine("ANTES DE STOP");
while (true)
{
    lock (stateLock)
    {
        captureStopRequested = true;
        if (!reconnectInProgress) break;
    }
    await Task.Delay(50);
}
try
{
    capture.StopRecording();
}
catch (Exception ex)
{
    Console.WriteLine($"STOP EXCEPTION: {ex.Message}");
}
Console.WriteLine("DESPUÉS DE STOP");
await schedulerTask;
await consumerTask;
await watchdogTask;

int remainingJobs;
lock (queueLock) remainingJobs = queue.Count;

Console.WriteLine();
Console.WriteLine("=== RESULTADO CAPTURA ===");
long capturedFramesSnapshot;
long capturedBytesSnapshot;
lock (stateLock)
{
    capturedFramesSnapshot = totalFramesCaptured;
    capturedBytesSnapshot = totalBytesCaptured;
    Console.WriteLine($"Frames capturados: {totalFramesCaptured}");
    Console.WriteLine($"Bytes capturados: {totalBytesCaptured}");
    Console.WriteLine($"Duración calculada: {totalFramesCaptured / (double)sampleRate:F3}s");
    Console.WriteLine($"Frames descartados del ring buffer: {droppedFramesFromRingBuffer}");
}

Console.WriteLine();
Console.WriteLine("=== RESULTADO COLA ===");
Console.WriteLine($"Jobs producidos: {producedJobs}");
Console.WriteLine($"Jobs procesados: {processedJobs}");
Console.WriteLine($"Jobs descartados: {droppedJobs}");
Console.WriteLine($"Jobs pendientes: {remainingJobs}");
Console.WriteLine($"Profundidad máxima: {maxQueueDepth}");

var accountingOk = producedJobs == processedJobs + droppedJobs + remainingJobs;
var capacityOk = maxQueueDepth <= QueueCapacity;
Console.WriteLine($"Contabilidad: {producedJobs} = {processedJobs} + {droppedJobs} + {remainingJobs} | {(accountingOk ? "OK" : "ERROR")}");
Console.WriteLine($"Capacidad máxima: {maxQueueDepth} <= {QueueCapacity} | {(capacityOk ? "OK" : "ERROR")}");

Console.WriteLine();
Console.WriteLine("=== CONVERT -> BUILD -> RECONSTRUCT ===");

if (successfulWindows.Count == 0)
{
    Console.WriteLine("No hay ventanas exitosas para reconstrucción.");
}
else
{
    var ordered = successfulWindows.OrderBy(x => x.WindowIndex).ToArray();
    var pathsLiteral = string.Join(",", ordered.Select(x => "'" + x.RawJsonPath.Replace("'", "''") + "'"));
    var offsetsLiteral = string.Join(",", ordered.Select(x => x.StartSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)));

    var reconstructionCommand = $@"
. .\src\Import\Convert-WhisperServer.ps1
. .\src\Words\Build-WhisperWords.ps1
. .\src\Alignment\Find-WordOverlap.ps1
. .\src\Reconstruction\Reconstruct-WhisperWindows.ps1
$paths = @({pathsLiteral})
$offsets = @({offsetsLiteral})
$windows = @()
$buildCounts = @()
for ($i = 0; $i -lt $paths.Count; $i++) {{
    $converted = Convert-WhisperServer -Path $paths[$i]
    $globalTokens = @($converted.Tokens | ForEach-Object {{
        [PSCustomObject]@{{
            Text = $_.Text
            From = [double]$_.From + [double]$offsets[$i]
            To   = [double]$_.To   + [double]$offsets[$i]
        }}
    }})
    $windows += [PSCustomObject]@{{
        Start = [double]$converted.Start + [double]$offsets[$i]
        End   = [double]$converted.End   + [double]$offsets[$i]
        Tokens = $globalTokens
    }}
    $buildCounts += @(@(Build-WhisperWords $globalTokens -WindowIndex $i).Count)
}}
$reconstructed = @(Reconstruct-WhisperWindows $windows 6> $null)
[PSCustomObject]@{{
    WindowCount = $windows.Count
    BuildWordCounts = @($buildCounts)
    ReconstructedWordCount = $reconstructed.Count
    ReconstructedWords = @($reconstructed | ForEach-Object {{ [PSCustomObject]@{{ Text=$_.Text; From=$_.From; To=$_.To; Id=$_.Id }} }})
}} | ConvertTo-Json -Depth 10
";

    var reconstructionJson = await RunPowerShellAsync(reconstructionCommand);
    var reconstruction = JsonSerializer.Deserialize<ReconstructionSummary>(reconstructionJson, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    if (reconstruction == null) throw new InvalidOperationException("No se pudo interpretar el resultado de reconstrucción.");

    Console.WriteLine($"Windows convertidas: {reconstruction.WindowCount}");
    Console.WriteLine($"Build words por ventana: {string.Join(", ", reconstruction.BuildWordCounts ?? Array.Empty<int>())}");
    Console.WriteLine($"Palabras reconstruidas: {reconstruction.ReconstructedWordCount}");

    var words = reconstruction.ReconstructedWords ?? Array.Empty<ReconstructedWord>();
    var monotonic = true;
    for (var i = 1; i < words.Length; i++)
        if (words[i].From < words[i - 1].From) monotonic = false;
    var duplicateIds = words.GroupBy(x => x.Id ?? "").Count(g => g.Key.Length > 0 && g.Count() > 1);
    Console.WriteLine($"Orden temporal: {(monotonic ? "OK" : "ERROR")}");
    Console.WriteLine($"IDs duplicados: {duplicateIds}");
    Console.WriteLine($"TRANSICIONES evaluadas: {Math.Max(0, reconstruction.WindowCount - 1)}");
}

Console.WriteLine();
Console.WriteLine("=== TIMING ===");

Console.WriteLine($"Ventanas con timing completo: {timingSamples.Count}");
Console.WriteLine($"Ventanas fallidas: {processedJobs - successfulWindows.Count}");

static double Percentile(double[] sorted, double p)
{
    if (sorted.Length == 1) return sorted[0];
    var rank = p * (sorted.Length - 1);
    var lo = (int)Math.Floor(rank);
    var hi = (int)Math.Ceiling(rank);
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (rank - lo) * (sorted[hi] - sorted[lo]);
}

void PrintMetricRow(string name, double[] values)
{
    if (values.Length == 0)
    {
        Console.WriteLine($"{name}: count=0");
        return;
    }

    Array.Sort(values);
    Console.WriteLine($"{name}: count={values.Length} min={values[0]:F1} p50={Percentile(values, 0.5):F1} p95={Percentile(values, 0.95):F1} max={values[^1]:F1} (ms)");
}

PrintMetricRow("queueDelay", timingSamples.Select(x => x.QueueDelayMs).ToArray());
PrintMetricRow("inferenceRTT", timingSamples.Select(x => x.InferenceRttMs).ToArray());
PrintMetricRow("normalization", timingSamples.Select(x => x.NormalizationMs).ToArray());
PrintMetricRow("captureToText", timingSamples.Select(x => x.CaptureToTextMs).ToArray());
PrintMetricRow("windowAge", timingSamples.Select(x => x.WindowAgeMs).ToArray());

Console.WriteLine();
Console.WriteLine("=== METRICAS POR VENTANA ===");

foreach (var s in timingSamples)
{
    Console.WriteLine($"#{s.WindowIndex:D2} | {s.StartSeconds:F3}-{s.EndSeconds:F3}s | depth={s.QueueDepth} | queueDelay={s.QueueDelayMs:F1} | inferenceRTT={s.InferenceRttMs:F1} | normalization={s.NormalizationMs:F1} | captureToText={s.CaptureToTextMs:F1} | windowAge={s.WindowAgeMs:F1} (ms)");
}

Console.WriteLine();
Console.WriteLine("=== COLA (SERIE) ===");

Console.WriteLine($"producedJobs={producedJobs} processedJobs={processedJobs} droppedJobs={droppedJobs} maxQueueDepth={maxQueueDepth} remainingJobs={remainingJobs}");

if (queueDepthSeries.Count > 0)
{
    var firstDepth = queueDepthSeries[0].Depth;
    var lastDepth = queueDepthSeries[^1].Depth;
    Console.WriteLine($"primer depth={firstDepth} | último depth={lastDepth} | máximo depth={maxQueueDepth}");
    Console.WriteLine($"serie: {string.Join(", ", queueDepthSeries.Select(x => $"{x.WindowIndex}:{x.Depth}"))}");

    var n = Math.Min(3, queueDepthSeries.Count);
    if (n > 0)
    {
        var firstAvg = queueDepthSeries.Take(n).Average(x => (double)x.Depth);
        var lastAvg = queueDepthSeries.Skip(queueDepthSeries.Count - n).Average(x => (double)x.Depth);
        Console.WriteLine($"promedio primeros {n}={firstAvg:F2} | promedio últimos {n}={lastAvg:F2}");
    }
}

Console.WriteLine();

var observedDurationSeconds = capturedFramesSnapshot / (double)sampleRate;
var expectedWindows = observedDurationSeconds >= WindowDurationSeconds
    ? (int)Math.Floor((observedDurationSeconds - WindowDurationSeconds) / StepSeconds) + 1
    : 0;
var captureContinuityOk = captureStopReason == CaptureStopReason.Normal && producedJobs == expectedWindows;
var queueOk = accountingOk && capacityOk;
var inferenceOk = successfulWindows.Count == producedJobs - droppedJobs;
Console.WriteLine($"POC 7 Paso 10 {(captureContinuityOk && queueOk && inferenceOk ? "PASS" : "FAIL")}.");

Console.WriteLine();
Console.WriteLine("=== RESULTADO CAPTURA WASAPI ===");
Console.WriteLine($"Stop reason: {captureStopReason}");
Console.WriteLine($"Capture exception: {(captureException != null ? captureException.ToString() : "null")}");
Console.WriteLine($"Watchdog pérdida silenciosa detectada: {(watchdogSilentLossDetected ? "Sí" : "No")}");
Console.WriteLine($"Reconexiones intentadas: {reconnectAttempts}");
Console.WriteLine($"Reconexiones exitosas: {reconnectSucceeded}");
Console.WriteLine($"Captura final activa: {(captureStopped ? "detenida" : "en curso")}");

record InferenceJob(int WindowIndex, double StartSeconds, double EndSeconds, byte[] Audio, DateTime WindowReadyUtc, DateTime QueueEnterUtc);
record InferenceResult(bool Success, int StatusCode, double DurationMs, int ResponseBytes, int SegmentCount, int WordCount, string? RawJsonPath, string? ConvertedJson, string? Error, DateTime InferenceStartUtc, DateTime HttpResponseUtc, DateTime NormalizedReadyUtc);
record SuccessfulWindow(int WindowIndex, double StartSeconds, double EndSeconds, string RawJsonPath, string ConvertedJson);
record WhisperWindow(double Start, double End, List<WhisperToken> Tokens);
record WhisperToken(string Text, double From, double To);
record ReconstructionSummary(int WindowCount, int[]? BuildWordCounts, int ReconstructedWordCount, ReconstructedWord[]? ReconstructedWords);
record ReconstructedWord(string? Text, double From, double To, string? Id);
record TimingSample(int WindowIndex, double StartSeconds, double EndSeconds, int QueueDepth, DateTime WindowReadyUtc, DateTime QueueEnterUtc, DateTime InferenceStartUtc, DateTime HttpResponseUtc, DateTime NormalizedReadyUtc, double QueueDelayMs, double InferenceRttMs, double NormalizationMs, double CaptureToTextMs, double WindowAgeMs);
record QueueDepthSample(int WindowIndex, int Depth, DateTime Utc);

enum CaptureStopReason
{
    Normal,
    DeviceOrAudioSubsystemFailure
}
