using System.Diagnostics;
using System.Text;
using System.Text.Json;
using NAudio.Wave;

const int TestDurationSeconds = 15;
const double WindowDurationSeconds = 5.0;
const double OverlapDurationSeconds = 1.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const double RingBufferDurationSeconds = 20.0;
const int QueueCapacity = 3;
const string WhisperServerUrl = "http://127.0.0.1:8080/inference";

Console.WriteLine("POC 7 - End-to-End Integration");
Console.WriteLine("Paso 5 - whisper-server -> Convert -> Build -> Reconstruct");
Console.WriteLine();

using var capture = new WasapiLoopbackCapture();
using var httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };

var sampleRate = capture.WaveFormat.SampleRate;
var channels = capture.WaveFormat.Channels;
var bitsPerSample = capture.WaveFormat.BitsPerSample;
var bytesPerFrame = (bitsPerSample / 8) * channels;
var ringBufferCapacityFrames = (long)(sampleRate * RingBufferDurationSeconds);
var ringBuffer = new byte[checked((int)(ringBufferCapacityFrames * bytesPerFrame))];

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
var processedJobIndexes = new List<int>();
var droppedJobIndexes = new List<int>();
var successfulWindows = new List<SuccessfulWindow>();

var repoRoot = Directory.GetParent(AppContext.BaseDirectory)!.Parent!.Parent!.Parent!.Parent!.Parent!.FullName;
var rawJsonDirectory = Path.Combine(repoRoot, "AudioCapturePOC", "EndToEndPOC", "bin", "Debug", "net10.0", "raw-json");
Directory.CreateDirectory(rawJsonDirectory);

Console.WriteLine($"Formato: {capture.WaveFormat}");
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
        queue.Enqueue(job);
        depth = queue.Count;
        maxQueueDepth = Math.Max(maxQueueDepth, depth);
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
    using (var writer = new WaveFileWriter(stream, capture.WaveFormat))
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

async Task<InferenceResult> RunInferenceAsync(InferenceJob job)
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
    stopwatch.Stop();

    await File.WriteAllTextAsync(rawJsonPath, responseText, new UTF8Encoding(false));

    if (!response.IsSuccessStatusCode)
        return new InferenceResult(false, (int)response.StatusCode, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, 0, 0, rawJsonPath, null, $"HTTP {(int)response.StatusCode}");

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
        return new InferenceResult(false, 200, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, segmentCount, wordCount, rawJsonPath, null, "Convert-WhisperServer produjo una ventana vacía o inválida.");

    Console.WriteLine($"INFERENCE OK #{job.WindowIndex:D2} | HTTP 200 | {stopwatch.Elapsed.TotalMilliseconds:F1} ms | segments={segmentCount} | serverWords={wordCount} | convertedTokens={convertedWindow.Tokens.Count}");
    Console.WriteLine($"CONVERT PARSED #{job.WindowIndex:D2} | Start={convertedWindow.Start:F3}s | End={convertedWindow.End:F3}s | tokens={convertedWindow.Tokens.Count}");

    return new InferenceResult(true, 200, stopwatch.Elapsed.TotalMilliseconds, responseText.Length, segmentCount, wordCount, rawJsonPath, convertedJson, null);
}

capture.DataAvailable += (_, e) => WriteToRingBuffer(e.Buffer, e.BytesRecorded);
capture.RecordingStopped += (_, e) =>
{
    lock (stateLock) captureStopped = true;
    queueSignal.Release();
    Console.WriteLine(e.Exception != null ? $"CAPTURE ERROR: {e.Exception}" : "Captura detenida.");
};

capture.StartRecording();
Console.WriteLine($"Capturando durante {TestDurationSeconds} segundos...");

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
                Console.WriteLine($"INFERENCIA #{job.WindowIndex:D2} | {job.StartSeconds:F1}s -> {job.EndSeconds:F1}s");
                var result = await RunInferenceAsync(job);
                lock (queueLock)
                {
                    processedJobs++;
                    processedJobIndexes.Add(job.WindowIndex);
                }
                if (result.Success)
                {
                    lock (queueLock)
                    {
                        successfulWindows.Add(new SuccessfulWindow(job.WindowIndex, job.StartSeconds, job.EndSeconds, result.RawJsonPath!, result.ConvertedJson!));
                    }
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
            Console.WriteLine($"VENTANA #{windowIndex}: {startSeconds:F3}s -> {endSeconds:F3}s | {audio.Length} bytes");
            TryEnqueue(new InferenceJob(windowIndex, startSeconds, endSeconds, audio));
            windowIndex++;
            nextWindowStartFrame += stepFrames;
            continue;
        }

        if (stopped) break;
        await Task.Delay(100);
    }
});

await Task.Delay(TimeSpan.FromSeconds(TestDurationSeconds));
Console.WriteLine("ANTES DE STOP");
capture.StopRecording();
Console.WriteLine("DESPUÉS DE STOP");
await schedulerTask;
await consumerTask;

int remainingJobs;
lock (queueLock) remainingJobs = queue.Count;

Console.WriteLine();
Console.WriteLine("=== RESULTADO CAPTURA ===");
lock (stateLock)
{
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
    $buildCounts += @((Build-WhisperWords $globalTokens -WindowIndex $i).Count)
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

var captureOk = droppedFramesFromRingBuffer == 0;
var queueOk = accountingOk && capacityOk;
var inferenceOk = successfulWindows.Count == producedJobs - droppedJobs;
Console.WriteLine();
Console.WriteLine($"POC 7 Paso 5 {(captureOk && queueOk && inferenceOk ? "PASS" : "FAIL")}.");

record InferenceJob(int WindowIndex, double StartSeconds, double EndSeconds, byte[] Audio);
record InferenceResult(bool Success, int StatusCode, double DurationMs, int ResponseBytes, int SegmentCount, int WordCount, string? RawJsonPath, string? ConvertedJson, string? Error);
record SuccessfulWindow(int WindowIndex, double StartSeconds, double EndSeconds, string RawJsonPath, string ConvertedJson);
record WhisperWindow(double Start, double End, List<WhisperToken> Tokens);
record WhisperToken(string Text, double From, double To);
record ReconstructionSummary(int WindowCount, int[]? BuildWordCounts, int ReconstructedWordCount, ReconstructedWord[]? ReconstructedWords);
record ReconstructedWord(string? Text, double From, double To, string? Id);
