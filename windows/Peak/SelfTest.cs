using System.Text.Json;
namespace Peak;
internal static class SelfTest
{
    public static async Task Run()
    {
        void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
        foreach (var bad in new[] { "file:///C:/test", "https://youtube.com.evil.test/watch?v=jNQXAC9IVRw", "https://youtube.com@evil.test/watch?v=jNQXAC9IVRw", "--exec=evil", "https://youtube.com/playlist?list=test" }) {
            bool rejected = false; try { DownloadPlan.Normalize(bad); } catch (ArgumentException) { rejected = true; } Check(rejected, "Invalid URL accepted");
        }
        Check(DownloadPlan.Normalize("https://youtu.be/jNQXAC9IVRw?list=x") == "https://www.youtube.com/watch?v=jNQXAC9IVRw", "Canonical URL");
        var tools = Path.Combine(AppContext.BaseDirectory, "Tools");
        var temp = Path.Combine(Path.GetTempPath(), "Peak tests " + Guid.NewGuid()); Directory.CreateDirectory(temp);
        try {
            foreach (var format in Enum.GetValues<OutputFormat>()) {
                var plan = new DownloadPlan("https://youtu.be/jNQXAC9IVRw", temp, format, false, 0);
                var args = plan.Arguments(tools, false);
                Check(args[^1] == plan.Url && args[^2] == "--", "Safe argument boundary");
                Check(plan.Format == (format == OutputFormat.MP4 ? "bv+ba/b" : "ba/b"), "Best source selection");
                if (format != OutputFormat.MP4) Check(!args.Contains("--remux-video") && args.Contains("--extract-audio"), "Audio conversion flags");
            }
            foreach (var name in new[] { "yt-dlp", "deno", "ffmpeg", "ffprobe" }) await Runner.Run(Path.Combine(tools, name + ".exe"), [name.StartsWith("ff") ? "-version" : "--version"], CancellationToken.None);
            var ffmpeg = Path.Combine(tools, "ffmpeg.exe"); var ffprobe = Path.Combine(tools, "ffprobe.exe");
            var source = Path.Combine(temp, "source.opus");
            await Runner.Run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:a", "libopus", source], CancellationToken.None);
            foreach (var format in new[] { OutputFormat.WAV, OutputFormat.MP3 }) {
                var file = Path.Combine(temp, "converted." + format.ToString().ToLowerInvariant());
                var args = new List<string> { "-v", "error", "-i", source };
                args.AddRange(format == OutputFormat.WAV ? new[] { "-c:a", "pcm_s24le" } : new[] { "-c:a", "libmp3lame", "-b:a", "320k" }); args.Add(file);
                await Runner.Run(ffmpeg, args, CancellationToken.None);
                var probe = await Runner.Run(ffprobe, ["-v", "error", "-show_streams", "-of", "json", file], CancellationToken.None);
                using var doc = JsonDocument.Parse(probe); var streams = doc.RootElement.GetProperty("streams");
                Check(streams.GetArrayLength() == 1, "Audio only");
                Check(streams[0].GetProperty("codec_name").GetString() == (format == OutputFormat.WAV ? "pcm_s24le" : "mp3"), "Audio codec");
                Check(streams[0].GetProperty("sample_rate").GetString() == "48000", "Source sample rate preserved");
                if (format == OutputFormat.MP3) Check(streams[0].GetProperty("bit_rate").GetString() == "320000", "MP3 bitrate");
                Check(Runner.FinalFile("PEAK_FILE:" + JsonSerializer.Serialize(file), format) == file, "Output marker with spaces");
            }
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            bool stopped = false; try { await Runner.Run(ffmpeg, ["-version"], cancelled.Token); } catch (OperationCanceledException) { stopped = true; } Check(stopped, "Pre-cancellation");
            using var active = new CancellationTokenSource(TimeSpan.FromMilliseconds(400));
            stopped = false; try { await Runner.Run(ffmpeg, ["-v", "error", "-re", "-f", "lavfi", "-i", "sine=duration=30", "-f", "null", "-"], active.Token); } catch (OperationCanceledException) { stopped = true; } Check(stopped, "Active cancellation");
            // Create and render the actual form on the STA UI thread in the separate UI smoke test.
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-passed.txt"), "URL validation, format selection, all bundled tools, WAV/MP3 conversion, output paths and cancellation passed.");
        } finally { Directory.Delete(temp, true); }
    }
}
