using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Peak;

internal enum OutputFormat { MP4, WAV, MP3 }
internal sealed record DownloadPlan(string Input, string Directory, OutputFormat Output, bool Compatible, int Height)
{
    public string Url => Normalize(Input);
    public static string Normalize(string input)
    {
        if (!Uri.TryCreate(input.Trim(), UriKind.Absolute, out var uri) ||
            (uri.Scheme != "https" && uri.Scheme != "http") || !uri.IsDefaultPort || uri.UserInfo != "" ||
            !new[] { "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be" }.Contains(uri.Host.ToLowerInvariant()))
            throw new ArgumentException("Paste a YouTube video link (youtube.com or youtu.be).");
        var parts = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        string? id = null;
        if (uri.Host.EndsWith("youtu.be")) id = parts.FirstOrDefault();
        else if (uri.AbsolutePath == "/watch")
            id = uri.Query.TrimStart('?').Split('&').Select(p => p.Split('=', 2)).FirstOrDefault(p => p.Length == 2 && p[0] == "v")?.ElementAt(1);
        else if (parts.Length == 2 && new[] { "shorts", "live", "embed" }.Contains(parts[0])) id = parts[1];
        if (id is null || !Regex.IsMatch(id, "^[a-zA-Z0-9_-]{11}$")) throw new ArgumentException("Use a single video link. Playlist-only links are not supported.");
        return "https://www.youtube.com/watch?v=" + id;
    }
    public string Format {
        get {
            if (Output != OutputFormat.MP4) return "ba/b";
            var limit = Height > 0 ? $"[height<={Height}]" : "";
            return Compatible ? $"bv[vcodec^=avc1]{limit}+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a]{limit}" : $"bv{limit}+ba/b{limit}";
        }
    }
    public string[] Arguments(string tools, bool preview)
    {
        var args = new List<string> {
            "--ignore-config", "--no-playlist", "--no-colors", "--newline", "--no-remote-components",
            "--no-js-runtimes", "--js-runtimes", "deno:" + Path.Combine(tools, "deno.exe"),
            "--ffmpeg-location", tools, "--socket-timeout", "20", "--retries", "5", "--fragment-retries", "5",
            "--match-filter", "!is_live & !is_upcoming", "-f", Format, "-S",
            Output == OutputFormat.MP4 ? "res,fps,hdr:12,vcodec,channels,acodec,br,size" : "channels,acodec,abr,asr,size"
        };
        if (preview) args.AddRange(["--skip-download", "--dump-single-json"]);
        else {
            if (Output == OutputFormat.MP4) args.AddRange(["--merge-output-format", "mp4", "--remux-video", "mp4", "--embed-chapters"]);
            else {
                args.AddRange(["--extract-audio", "--audio-format", Output.ToString().ToLowerInvariant()]);
                if (Output == OutputFormat.MP3) args.AddRange(["--audio-quality", "320K"]);
                else args.AddRange(["--postprocessor-args", "ExtractAudio+ffmpeg_o:-c:a pcm_s24le"]);
            }
            var preset = Output == OutputFormat.MP4 ? (Compatible ? "h264" : "source") + "-" + (Height > 0 ? Height.ToString() : "best") : Output == OutputFormat.WAV ? "wav-24bit" : "mp3-320k";
            args.AddRange(["--no-simulate", "--no-quiet", "--no-overwrites", "--continue", "--windows-filenames", "--concurrent-fragments", "4", "--embed-metadata",
                "--progress", "--progress-delta", "0.25", "--progress-template", "download:PEAK_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                "--print", "after_move:PEAK_FILE:%(filepath)j", "-P", Directory, "-o", $"%(title).130B [%(id)s] [{preset}].%(ext)s"]);
        }
        args.AddRange(["--", Url]);
        return args.ToArray();
    }
}

internal static class Runner
{
    public static async Task<string> Run(string executable, IEnumerable<string> args, CancellationToken token, Action<string>? onLine = null)
    {
        token.ThrowIfCancellationRequested();
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        foreach (var arg in args) start.ArgumentList.Add(arg);
        start.Environment["PATH"] = Path.GetDirectoryName(executable) + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH");
        using var process = new Process { StartInfo = start };
        process.Start();
        using var cancellation = token.Register(() => { try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) {} catch (System.ComponentModel.Win32Exception) {} });
        var output = new StringBuilder(); var gate = new object();
        async Task Read(StreamReader reader) {
            while (await reader.ReadLineAsync() is { } line) {
                lock (gate) { output.AppendLine(line); if (output.Length > 4_000_000) output.Remove(0, output.Length - 4_000_000); }
                onLine?.Invoke(line);
            }
        }
        await Task.WhenAll(Read(process.StandardOutput), Read(process.StandardError), process.WaitForExitAsync());
        token.ThrowIfCancellationRequested();
        var text = output.ToString();
        if (process.ExitCode != 0) throw new IOException(text.Split('\n').LastOrDefault(l => l.StartsWith("ERROR:")) ?? $"Tool exited with code {process.ExitCode}.\n" + text[^Math.Min(text.Length, 2000)..]);
        return text;
    }
    public static string FinalFile(string output, OutputFormat format)
    {
        var marker = output.Split('\n').LastOrDefault(l => l.StartsWith("PEAK_FILE:"));
        var file = marker is null ? null : JsonSerializer.Deserialize<string>(marker[10..].Trim());
        if (file is null || !file.EndsWith("." + format.ToString(), StringComparison.OrdinalIgnoreCase) || !File.Exists(file)) throw new IOException("The tool did not report the expected output file. Open details to review its output.");
        return file;
    }
}
