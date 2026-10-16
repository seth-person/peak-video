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
            var video = Path.Combine(temp, "timeline fixture.mp4"); var clip = Path.Combine(temp, "precise clip.mp4");
            await Runner.Run(ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:v", "libx264", "-g", "120", "-pix_fmt", "yuv420p", "-c:a", "aac", "-n", video], CancellationToken.None);
            var original = await File.ReadAllBytesAsync(video); var media = await TrimPlan.Probe(tools, video, CancellationToken.None);
            foreach (var (a, b) in new[] { (double.NaN, 2.0), (-1, 2.0), (2, 1.0), (0, 5.0), (0, 0.001) }) { bool rejected = false; try { new TrimPlan(video, a, b, media).Arguments(clip); } catch (ArgumentException) { rejected = true; } Check(rejected, "Invalid trim range accepted"); }
            var trim = new TrimPlan(video, 0.733, 2.1, media);
            await Runner.Run(ffmpeg, trim.Arguments(clip), CancellationToken.None);
            var trimmed = await TrimPlan.Probe(tools, clip, CancellationToken.None);
            Check(Math.Abs(trimmed.Duration - trim.Duration) < media.Frame / 2, "Precise trim duration");
            Check(trimmed.Width == media.Width && trimmed.Height == media.Height, "Trim resolution");
            var probeClip = await Runner.Run(ffprobe, ["-v", "error", "-show_streams", "-of", "json", clip], CancellationToken.None);
            Check(probeClip.Contains("h264") && probeClip.Contains("aac"), "Trim video and audio codecs");
            var jpeg = Path.Combine(temp, "preview.jpg");
            await Runner.Run(ffmpeg, TrimPlan.FrameArguments(video, trim.Start, media, jpeg, 960), CancellationToken.None);
            Check(new FileInfo(jpeg).Length > 1000, "Frame preview generated");
            var comparison = await Runner.Run(ffmpeg, ["-v", "info", "-ss", TrimPlan.Number(trim.EffectiveStart), "-i", video, "-i", clip, "-lavfi", "[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]psnr", "-frames:v", "1", "-f", "null", "-"], CancellationToken.None);
            var psnr = System.Text.RegularExpressions.Regex.Match(comparison, @"average:([0-9.]+)");
            Check(psnr.Success && double.Parse(psnr.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture) > 35, "Export starts on selected frame");
            var after = await File.ReadAllBytesAsync(video); Check(original.SequenceEqual(after), "Original preserved");
            var beforeClip = await File.ReadAllBytesAsync(clip); try { await Runner.Run(ffmpeg, trim.Arguments(clip), CancellationToken.None); } catch (IOException) {}
            var afterClip = await File.ReadAllBytesAsync(clip); Check(beforeClip.SequenceEqual(afterClip), "Existing clip must not be overwritten");
            using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
            bool stopped = false; try { await Runner.Run(ffmpeg, ["-version"], cancelled.Token); } catch (OperationCanceledException) { stopped = true; } Check(stopped, "Pre-cancellation");
            using var active = new CancellationTokenSource(TimeSpan.FromMilliseconds(400));
            stopped = false; try { await Runner.Run(ffmpeg, ["-v", "error", "-re", "-f", "lavfi", "-i", "sine=duration=30", "-f", "null", "-"], active.Token); } catch (OperationCanceledException) { stopped = true; } Check(stopped, "Active cancellation");
            // Create and render the actual form on the STA UI thread in the separate UI smoke test.
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-passed.txt"), "URL validation, format selection, all bundled tools, WAV/MP3 conversion, output paths, accurate video trimming, thumbnails, preservation and cancellation passed.");
        } finally { Directory.Delete(temp, true); }
    }
}
