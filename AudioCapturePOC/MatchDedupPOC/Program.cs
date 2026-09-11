using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using NAudio.Wave;

const int CaptureDurationSeconds = 14;
const double WindowDurationSeconds = 10.0;
const double OverlapDurationSeconds = 8.0;
const double StepSeconds = WindowDurationSeconds - OverlapDurationSeconds;
const string WhisperServerUrl = "http://127.0.0.1:8080/inference";

Console.WriteLine("POC 7 - Paso 6 - MATCH / DEDUP controlado");
Console.WriteLine();
Console.WriteLine("Objetivo: demostrar un MATCH real entre ventanas con habla repetida en el solapamiento.");
Console.WriteLine();
Console.WriteLine("INSTRUCCIONES DE AUDIO");
Console.WriteLine("1. Cuando aparezca GO, habla durante varios segundos.");
Console.WriteLine("2. Repite continuamente esta frase durante la captura:");
Console.WriteLine("   Esta es una prueba controlada de coincidencia de palabras para la reconstruccion.");
Console.WriteLine("3. Procura que la frase ocurra entre aproximadamente los segundos 3 y 9.");
Console.WriteLine("4. No cambies de frase durante ese intervalo.");
Console.WriteLine();
Console.WriteLine("Geometria experimental: ventana 10 s | solapamiento 8 s | paso 2 s");
Console.WriteLine("Esta geometria es SOLO para probar MATCH; no cambia la geometria de produccion de Paso 5.");
Console.WriteLine();

using var capture = new WasapiLoopbackCapture();
using var httpClient = new HttpClient { Timeout = TimeSpan.FromMinutes(2) };
using var pcm = new MemoryStream();

var format = capture.WaveFormat;
var sampleRate = format.SampleRate;
var channels = format.Channels;
var bytesPerFrame = (format.BitsPerSample / 8) * channels;

capture.DataAvailable += (_, e) => pcm.Write(e.Buffer, 0, e.BytesRecorded);

var captureStopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
capture.RecordingStopped += (_, e) =>
{
    if (e.Exception != null) captureStopped.TrySetException(e.Exception);
    else captureStopped.TrySetResult();
};

Console.WriteLine("Preparando captura...");
await Task.Delay(1000);
Console.WriteLine("3...");
await Task.Delay(1000);
Console.WriteLine("2...");
await Task.Delay(1000);
Console.WriteLine("1...");
await Task.Delay(1000);
Console.WriteLine("GO");

capture.StartRecording();
await Task.Delay(TimeSpan.FromSeconds(CaptureDurationSeconds));
capture.StopRecording();
await captureStopped.Task;

var pcmBytes = pcm.ToArray();
var totalFrames = pcmBytes.Length / bytesPerFrame;
var actualDuration = totalFrames / (double)sampleRate;

Console.WriteLine();
Console.WriteLine("=== CAPTURA ===");
Console.WriteLine($"Formato: {format}");
Console.WriteLine($"Bytes PCM: {pcmBytes.Length}");
Console.WriteLine($"Frames: {totalFrames}");
Console.WriteLine($"Duracion: {actualDuration:F3}s");

var repoRoot = Directory.GetParent(AppContext.BaseDirectory)!.Parent!.Parent!.Parent!.Parent!.Parent!.FullName;
var outputDirectory = Path.Combine(repoRoot, "AudioCapturePOC", "MatchDedupPOC", "bin", "Debug", "net10.0", "raw-json");
Directory.CreateDirectory(outputDirectory);

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
        throw new InvalidOperationException($"PowerShell fallo (exit code {process.ExitCode}): {stderr}");
    return stdout;
}

async Task<byte[]> BuildWavAsync(byte[] audio)
{
    await using var stream = new MemoryStream();
    using (var writer = new WaveFileWriter(stream, format))
    {
        writer.Write(audio, 0, audio.Length);
        writer.Flush();
    }
    return stream.ToArray();
}

async Task<string> ConvertJsonAsync(string path)
{
    var command = $@"
. .\src\Import\Convert-WhisperServer.ps1
$result = Convert-WhisperServer -Path '{path.Replace("'", "''")}'
$result | ConvertTo-Json -Depth 10
";
    return await RunPowerShellAsync(command);
}

async Task<(string RawPath, string ConvertedJson, int ServerWords, int Tokens)> InferAsync(int index, double startSeconds, byte[] audio)
{
    var wav = await BuildWavAsync(audio);
    var wavPath = Path.Combine(outputDirectory, $"window-{index:D2}.wav");
    var rawPath = Path.Combine(outputDirectory, $"window-{index:D2}-verbose.json");
    await File.WriteAllBytesAsync(wavPath, wav);

    using var form = new MultipartFormDataContent();
    using var fileContent = new ByteArrayContent(wav);
    fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("audio/wav");
    form.Add(fileContent, "file", Path.GetFileName(wavPath));
    form.Add(new StringContent("0.0"), "temperature");
    form.Add(new StringContent("verbose_json"), "response_format");

    using var response = await httpClient.PostAsync(WhisperServerUrl, form);
    var responseText = await response.Content.ReadAsStringAsync();
    await File.WriteAllTextAsync(rawPath, responseText, new UTF8Encoding(false));

    if (!response.IsSuccessStatusCode)
        throw new InvalidOperationException($"HTTP {(int)response.StatusCode} para ventana #{index:D2}: {responseText}");

    using var document = JsonDocument.Parse(responseText);
    var root = document.RootElement;
    var serverWords = 0;
    var segments = 0;
    if (root.TryGetProperty("segments", out var segmentArray))
    {
        segments = segmentArray.GetArrayLength();
        foreach (var segment in segmentArray.EnumerateArray())
            if (segment.TryGetProperty("words", out var words)) serverWords += words.GetArrayLength();
    }

    var convertedJson = await ConvertJsonAsync(rawPath);
    var converted = JsonSerializer.Deserialize<WhisperWindow>(convertedJson, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    if (converted is null || converted.Tokens.Count == 0)
        throw new InvalidOperationException($"Convert produjo una ventana vacia para #{index:D2}.");

    Console.WriteLine($"VENTANA #{index:D2} | global {startSeconds:F1}s -> {startSeconds + WindowDurationSeconds:F1}s | segments={segments} | serverWords={serverWords} | tokens={converted.Tokens.Count}");
    return (rawPath, convertedJson, serverWords, converted.Tokens.Count);
}

var windowFrames = (long)(WindowDurationSeconds * sampleRate);
var stepFrames = (long)(StepSeconds * sampleRate);
var windowCount = 0;
var successful = new List<SuccessfulWindow>();

for (long startFrame = 0; startFrame + windowFrames <= totalFrames; startFrame += stepFrames)
{
    var frameCount = windowFrames;
    var audio = new byte[checked((int)(frameCount * bytesPerFrame))];
    var sourceOffset = checked((int)(startFrame * bytesPerFrame));
    Buffer.BlockCopy(pcmBytes, sourceOffset, audio, 0, audio.Length);

    var startSeconds = startFrame / (double)sampleRate;
    var result = await InferAsync(windowCount, startSeconds, audio);
    successful.Add(new SuccessfulWindow(windowCount, startSeconds, startSeconds + WindowDurationSeconds, result.RawPath));
    windowCount++;
}

Console.WriteLine();
Console.WriteLine("=== RECONSTRUCCION CONTROLADA ===");
Console.WriteLine($"Ventanas exitosas: {successful.Count}");

var pathsLiteral = string.Join(",", successful.Select(x => "'" + x.RawPath.Replace("'", "''") + "'"));
var offsetsLiteral = string.Join(",", successful.Select(x => x.StartSeconds.ToString(CultureInfo.InvariantCulture)));

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
    $tokens = @(
        $converted.Tokens | ForEach-Object {{
            [PSCustomObject]@{{
                Text = $_.Text
                From = [double]$_.From + [double]$offsets[$i]
                To   = [double]$_.To   + [double]$offsets[$i]
            }}
        }}
    )
    $windows += [PSCustomObject]@{{
        Start = [double]$converted.Start + [double]$offsets[$i]
        End   = [double]$converted.End   + [double]$offsets[$i]
        Tokens = $tokens
    }}
    $buildCounts += @((Build-WhisperWords $tokens -WindowIndex $i).Count)
}}
$result = @(Reconstruct-WhisperWindows $windows) 6>&1
$ids = @($result | Where-Object {{ $_.PSObject.Properties.Name -contains 'Id' }} | ForEach-Object {{ $_.Id }})
$wordObjects = @($result | Where-Object {{ $_.PSObject.Properties.Name -contains 'Id' }})
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
$orderViolations = 0
for ($i = 1; $i -lt $wordObjects.Count; $i++) {{
    if ([double]$wordObjects[$i].From -lt [double]$wordObjects[$i - 1].From) {{ $orderViolations++ }}
}}
[PSCustomObject]@{{
    Windows = $windows.Count
    BuildCounts = ($buildCounts -join ',')
    ReconstructedWords = $wordObjects.Count
    DuplicateIds = $duplicates.Count
    OrderViolations = $orderViolations
}} | ConvertTo-Json -Compress
";

var reconstructionOutput = await RunPowerShellAsync(reconstructionCommand);
Console.WriteLine(reconstructionOutput);

Console.WriteLine();
Console.WriteLine("=== CRITERIO ===");
Console.WriteLine("La salida de Reconstruct-WhisperWindows se incluye aqui para inspeccionar explicitamente MATCH frente a SIN MATCH.");
Console.WriteLine("Este POC solo sera PASS si la salida contiene al menos un MATCH real y las invariantes finales son correctas.");

record WhisperToken(string Text, double From, double To);
record WhisperWindow(double Start, double End, List<WhisperToken> Tokens);
record SuccessfulWindow(int WindowIndex, double StartSeconds, double EndSeconds, string RawPath);
