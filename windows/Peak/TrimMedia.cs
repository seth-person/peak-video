using System.Globalization;
using System.Text.Json;
namespace Peak;
internal sealed record MediaInfo(double Duration, int Width, int Height, double Fps, bool Hdr, string Transfer, string Primaries, string Matrix)
{
    public double Frame => 1 / Fps;
    public static MediaInfo Parse(string json)
    {
        using var doc = JsonDocument.Parse(json); var root = doc.RootElement;
        var video = root.GetProperty("streams").EnumerateArray().FirstOrDefault(s => s.GetProperty("codec_type").GetString() == "video");
        if (video.ValueKind == JsonValueKind.Undefined) throw new IOException("Choose a file containing a video track.");
        string? Value(JsonElement e, string key) => e.TryGetProperty(key, out var p) ? p.GetString() : null;
        var duration = double.Parse(Value(video, "duration") ?? Value(root.GetProperty("format"), "duration") ?? "0", CultureInfo.InvariantCulture);
        if (!double.IsFinite(duration) || duration <= 0) throw new IOException("This video has no usable duration.");
        var parts = (Value(video, "avg_frame_rate") ?? "30/1").Split('/'); double fps = 30;
        if (parts.Length == 2 && double.TryParse(parts[0], CultureInfo.InvariantCulture, out var n) && double.TryParse(parts[1], CultureInfo.InvariantCulture, out var d) && d > 0 && n > 0) fps = Math.Min(n / d, 1000);
        var transfer = Value(video, "color_transfer") ?? "";
        return new(duration, video.GetProperty("width").GetInt32(), video.GetProperty("height").GetInt32(), fps, transfer is "smpte2084" or "arib-std-b67", transfer, Value(video, "color_primaries") ?? "bt2020", Value(video, "color_space") ?? "bt2020nc");
    }
}
internal sealed record TrimPlan(string Input, double Start, double End, MediaInfo Info)
{
    public double Duration => End - Start;
    public static string Number(double value) => value.ToString("F6", CultureInfo.InvariantCulture);
    public static string Timecode(double value) => TimeSpan.FromSeconds(Math.Max(0, value)).ToString(@"hh\:mm\:ss\.fff");
    public string[] Arguments(string output)
    {
        if (!double.IsFinite(Start) || !double.IsFinite(End) || Start < 0 || End > Info.Duration + 0.000001 || Duration < Math.Min(Info.Frame, Info.Duration) - 0.000001) throw new ArgumentException("Choose a range within the video, at least one frame long.");
        var args = new List<string> { "-v", "error", "-nostdin", "-ss", Number(Start), "-i", Input, "-t", Number(Duration), "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "0", "-map_chapters", "-1", "-c:v", Info.Hdr ? "libx265" : "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", Info.Hdr ? "yuv420p10le" : "yuv420p", "-c:a", "aac", "-b:a", "320k", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats" };
        if (Info.Hdr) args.AddRange(["-tag:v", "hvc1", "-x265-params", "log-level=error", "-color_primaries", Info.Primaries, "-color_trc", Info.Transfer, "-colorspace", Info.Matrix]);
        args.AddRange(["-n", output]); return args.ToArray();
    }
    public static string[] FrameArguments(string input, double time, MediaInfo info, string output, int width) => ["-v", "error", "-nostdin", "-ss", Number(Math.Clamp(time, 0, Math.Max(0, info.Duration - info.Frame))), "-i", input, "-map", "0:v:0", "-frames:v", "1", "-vf", $"scale={width}:-2:force_original_aspect_ratio=decrease", "-q:v", "2", "-update", "1", "-n", output];
    public static async Task<MediaInfo> Probe(string tools, string input, CancellationToken token) => MediaInfo.Parse(await Runner.Run(Path.Combine(tools, "ffprobe.exe"), ["-v", "error", "-show_streams", "-show_format", "-of", "json", input], token));
}
