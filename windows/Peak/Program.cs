using System.Diagnostics;
using System.Text.Json;

namespace Peak;
internal static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--self-test")) {
            try { SelfTest.Run().GetAwaiter().GetResult(); return 0; }
            catch (Exception e) { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "self-test-error.txt"), e.ToString()); return 1; }
        }
        try {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            if (args.Length == 2 && args[0] == "--trim-ui-smoke-test") { using var trimTest = new TrimWindow(args[1], true); Application.Run(trimTest); return File.Exists(Path.Combine(AppContext.BaseDirectory, "trim-ui-test-passed.txt")) ? 0 : 1; }
            using var window = new MainWindow();
            if (args.Contains("--ui-smoke-test")) {
                window.Shown += (_, _) => {
                    var timer = new System.Windows.Forms.Timer { Interval = 500 };
                    timer.Tick += (_, _) => {
                        timer.Stop(); timer.Dispose();
                        if (!window.Visible || window.ClientSize.Width < 700) throw new Exception("Window did not become visible");
                        using var bitmap = new Bitmap(window.Width, window.Height);
                        window.DrawToBitmap(bitmap, new Rectangle(Point.Empty, window.Size));
                        bitmap.Save(Path.Combine(AppContext.BaseDirectory, "ui-preview.png"));
                        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "ui-test-passed.txt"), "Main form shown and rendered successfully.");
                        window.Close();
                    };
                    timer.Start();
                };
            }
            Application.Run(window);
            return 0;
        } catch (Exception e) {
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "startup-error.txt"), e.ToString());
            return 1;
        }
    }
}
internal sealed class MainWindow : Form
{
    readonly Color mint = Color.FromArgb(133, 240, 196);
    readonly TextBox link = new() { PlaceholderText = "Paste a YouTube video URL", AccessibleName = "YouTube video URL" };
    readonly ComboBox format = new(), quality = new(), resolution = new();
    readonly Label explanation = new(), folderLabel = new(), info = new(), status = new();
    readonly Button download = new(), preview = new(), cancel = new(), folder = new(), reveal = new(), trim = new(), openTrim = new();
    readonly ProgressBar progress = new();
    readonly TextBox details = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical };
    readonly string tools = Path.Combine(AppContext.BaseDirectory, "Tools");
    readonly string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Peak", "settings.json");
    string destination = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Peak");
    string? completed; CancellationTokenSource? cancellation; bool closing;
    public MainWindow()
    {
        Text = "Peak"; BackColor = Color.FromArgb(14, 19, 26); ForeColor = Color.WhiteSmoke;
        Font = new Font("Segoe UI", 10); AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(820, 890); MinimumSize = new Size(760, 760); StartPosition = FormStartPosition.CenterScreen;
        try { if (File.Exists(settings)) destination = JsonSerializer.Deserialize<string>(File.ReadAllText(settings)) ?? destination; } catch (Exception) {}
        var page = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(32), ColumnCount = 1, AutoScroll = true };
        page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); Controls.Add(page);
        void Add(Control c, int height) { c.Dock = DockStyle.Fill; c.Margin = new Padding(0, 0, 0, 12); page.RowStyles.Add(new RowStyle(SizeType.Absolute, height)); page.Controls.Add(c, 0, page.RowCount++); }
        Label Label(string text, float size, Color? color = null) => new() { Text = text, ForeColor = color ?? ForeColor, Font = new Font(Font.FontFamily, size, size >= 20 ? FontStyle.Bold : FontStyle.Regular), AutoEllipsis = true };
        Add(Label("▲  Peak                                      LOCAL BY DESIGN", 18, mint), 46);
        Add(Label("Keep every detail.", 30), 61);
        Add(Label("YouTube to MP4, WAV or MP3. Your media, saved on your PC.", 11, Color.Silver), 38);
        Add(Label("01   VIDEO LINK", 9, mint), 28);
        Add(link, 44);
        preview.Text = "Preview video"; preview.Click += async (_, _) => await Start(true); Add(preview, 44);
        info.Text = "Videos, Shorts, and finished livestreams."; Add(info, 54);
        Add(Label("02   FORMAT & DESTINATION", 9, mint), 28);
        var selectors = new TableLayoutPanel { ColumnCount = 3, RowCount = 1 };
        for (int i = 0; i < 3; i++) selectors.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.33f));
        format.Items.AddRange(["MP4 · Video", "WAV · Audio", "MP3 · Audio"]); format.AccessibleName = "Output format";
        quality.Items.AddRange(["Maximum quality", "Wide compatibility"]); quality.AccessibleName = "Video quality";
        resolution.Items.AddRange(["Best available · no limit", "Up to 4K · 2160p", "Up to 1440p", "Up to 1080p", "Up to 720p"]); resolution.AccessibleName = "Resolution limit";
        foreach (var box in new[] { format, quality, resolution }) { box.DropDownStyle = ComboBoxStyle.DropDownList; box.SelectedIndex = 0; box.Dock = DockStyle.Fill; selectors.Controls.Add(box); box.SelectedIndexChanged += (_, _) => UpdateFormat(); }
        Add(selectors, 44); Add(explanation, 74);
        var folders = new TableLayoutPanel { ColumnCount = 2 };
        folders.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); folders.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        folderLabel.AutoEllipsis = true; folderLabel.Dock = DockStyle.Fill; folderLabel.Text = destination;
        folder.Text = "Change…"; folder.Dock = DockStyle.Fill;
        folder.Click += (_, _) => { using var dialog = new FolderBrowserDialog { InitialDirectory = destination, Description = "Save downloads here", UseDescriptionForTitle = true }; if (dialog.ShowDialog(this) == DialogResult.OK) { destination = dialog.SelectedPath; folderLabel.Text = destination; try { Directory.CreateDirectory(Path.GetDirectoryName(settings)!); File.WriteAllText(settings, JsonSerializer.Serialize(destination)); } catch (Exception e) { status.Text = "Folder selected; preference could not be saved: " + e.Message; } } };
        folders.Controls.Add(folderLabel); folders.Controls.Add(folder); Add(folders, 44);
        var buttons = new TableLayoutPanel { ColumnCount = 4 };
        buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95)); buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150)); buttons.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        download.Click += async (_, _) => await Start(false); download.BackColor = mint; download.ForeColor = BackColor;
        cancel.Text = "Cancel"; cancel.Enabled = false; cancel.Click += (_, _) => { status.Text = "Cancelling…"; cancellation?.Cancel(); };
        reveal.Text = "Show in Explorer"; reveal.Enabled = trim.Enabled = false; reveal.Click += (_, _) => { if (completed is not null) { var p = new ProcessStartInfo("explorer.exe") { UseShellExecute = true }; p.ArgumentList.Add("/select,"); p.ArgumentList.Add(completed); Process.Start(p); } };
        trim.Text = "Trim video"; trim.Enabled = false; trim.Click += (_, _) => { if (completed is not null) { using var editor = new TrimWindow(completed); editor.ShowDialog(this); } };
        foreach (var button in new[] { download, cancel, reveal, trim }) { button.Dock = DockStyle.Fill; buttons.Controls.Add(button); }
        Add(buttons, 52); Add(progress, 23); status.Text = "Ready when you are"; Add(status, 48);
        var toggle = new Button { Text = "Show / hide details" }; toggle.Click += (_, _) => { details.Visible = !details.Visible; page.RowStyles[page.GetRow(details)].Height = details.Visible ? 150 : 0; }; Add(toggle, 40);
        Add(details, 0); details.Visible = false;
        openTrim.Text = "Open video to trim…"; openTrim.Click += (_, _) => { using var dialog = new OpenFileDialog { Filter = "Video files|*.mp4;*.mov;*.mkv;*.webm;*.avi;*.m4v|All files|*.*", Title = "Open in trim editor" }; if (dialog.ShowDialog(this) == DialogResult.OK) { using var editor = new TrimWindow(dialog.FileName); editor.ShowDialog(this); } }; Add(openTrim, 40);
        Add(Label("PEAK 1.2   ·   Download media you own or have permission to save.", 9, Color.Silver), 34);
        foreach (var button in new[] { preview, folder, download, cancel, reveal, trim, openTrim, toggle }) { button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderColor = Color.FromArgb(65, 78, 90); button.Cursor = Cursors.Hand; }
        link.TextChanged += (_, _) => { info.Text = ""; completed = null; reveal.Enabled = trim.Enabled = false; };
        UpdateFormat();
        FormClosing += (_, e) => { if (cancellation is null) return; e.Cancel = true; if (MessageBox.Show(this, "Cancel the current download and quit?", "Peak", MessageBoxButtons.YesNo) == DialogResult.Yes) { closing = true; cancellation.Cancel(); } };
    }
    OutputFormat SelectedFormat => (OutputFormat)format.SelectedIndex;
    void UpdateFormat()
    {
        bool video = SelectedFormat == OutputFormat.MP4;
        quality.Enabled = resolution.Enabled = video && cancellation is null;
        explanation.Text = SelectedFormat switch {
            OutputFormat.WAV => "Best available audio decoded to uncompressed 24-bit PCM. Larger files; preserves the source sample rate. YouTube audio is already compressed, so WAV cannot restore lost detail.",
            OutputFormat.MP3 => "Best available audio converted to 320 kbps MP3. Compact and widely compatible; conversion is lossy.",
            _ => quality.SelectedIndex == 0 ? "Best available video + audio. No re-encoding. May use AV1, VP9 or Opus; use a player that supports those codecs." : "H.264 video + AAC audio for broad playback support. YouTube may only offer these formats up to 1080p."
        };
        download.Text = "Download " + SelectedFormat; info.Text = ""; completed = null; reveal.Enabled = trim.Enabled = false;
    }
    async Task Start(bool previewOnly)
    {
        if (cancellation is not null) return;
        var plan = new DownloadPlan(link.Text, destination, SelectedFormat, quality.SelectedIndex == 1, new[] { 0, 2160, 1440, 1080, 720 }[resolution.SelectedIndex]);
        try { _ = plan.Url; foreach (var name in new[] { "yt-dlp", "ffmpeg", "ffprobe", "deno" }) if (!File.Exists(Path.Combine(tools, name + ".exe"))) throw new IOException("Bundled " + name + " is missing. Reinstall Peak."); if (!previewOnly) Directory.CreateDirectory(destination); }
        catch (Exception e) { status.Text = e.Message; return; }
        cancellation = new(); var token = cancellation.Token;
        foreach (var control in new Control[] { link, format, quality, resolution, folder, download, preview, reveal, trim, openTrim }) control.Enabled = false;
        cancel.Enabled = true; completed = null; details.Clear(); progress.Style = ProgressBarStyle.Marquee;
        status.Text = "Finding the best available streams…";
        try {
            var metadata = await Runner.Run(Path.Combine(tools, "yt-dlp.exe"), plan.Arguments(tools, true), token);
            var json = metadata.Split('\n').LastOrDefault(l => l.StartsWith('{')) ?? throw new IOException("No downloadable media found. Live and upcoming streams are not supported.");
            using var doc = JsonDocument.Parse(json); var root = doc.RootElement;
            if (root.TryGetProperty("is_live", out var live) && live.ValueKind == JsonValueKind.True) throw new IOException("Try again after the livestream finishes.");
            info.Text = root.GetProperty("title").GetString() + "\n" + (root.TryGetProperty("uploader", out var uploader) ? uploader.GetString() : "");
            if (previewOnly) status.Text = "Preview ready";
            else {
                status.Text = "Downloading original streams…";
                var output = await Runner.Run(Path.Combine(tools, "yt-dlp.exe"), plan.Arguments(tools, false), token, line => {
                    if (IsDisposed) return;
                    BeginInvoke(() => {
                        if (token.IsCancellationRequested || cancellation is null) return;
                        if (line.StartsWith("PEAK_PROGRESS:")) {
                            var fields = line[14..].Split('|');
                            if (fields.Length == 3 && double.TryParse(fields[0].Trim().TrimEnd('%'), System.Globalization.CultureInfo.InvariantCulture, out var percent) && double.IsFinite(percent)) {
                                progress.Style = ProgressBarStyle.Continuous; progress.Value = (int)Math.Clamp(percent, 0, 100); status.Text = $"Downloading · {fields[1].Trim()} · {fields[2].Trim()} left";
                            }
                        } else { details.AppendText(line + Environment.NewLine); if (details.TextLength > 24000) details.Text = details.Text[^24000..]; if (line.Contains("[ExtractAudio]") || line.Contains("[Merger]") || line.Contains("[VideoRemuxer]") || line.Contains("[Metadata]")) { progress.Style = ProgressBarStyle.Marquee; status.Text = "Finishing your " + plan.Output + "…"; } }
                    });
                });
                completed = Runner.FinalFile(output, plan.Output); status.Text = "Saved your " + plan.Output;
            }
        } catch (OperationCanceledException) { status.Text = "Cancelled — retry to resume partial downloads"; }
        catch (Exception e) { status.Text = "Couldn’t finish: " + e.Message; details.AppendText(e + Environment.NewLine); }
        finally {
            cancellation.Dispose(); cancellation = null; cancel.Enabled = false; progress.Style = ProgressBarStyle.Continuous; progress.Value = completed is null ? 0 : 100;
            foreach (var c in new Control[] { link, format, folder, download, preview, openTrim }) c.Enabled = true;
            quality.Enabled = resolution.Enabled = SelectedFormat == OutputFormat.MP4; reveal.Enabled = completed is not null; trim.Enabled = completed is not null && SelectedFormat == OutputFormat.MP4;
            if (closing) Close();
        }
    }
}
