using System.Diagnostics;
namespace Peak;
internal sealed class Timeline : Control
{
    public readonly List<Image> Images = [];
    public double Duration = 1, Start, End = 1, Position;
    public event Action<double, int>? Scrub;
    int drag;
    public Timeline() { DoubleBuffered = true; Height = 88; Cursor = Cursors.Cross; AccessibleName = "Thumbnail timeline"; }
    int X(double time) => (int)Math.Clamp(time / Duration * Math.Max(1, Width - 12) + 6, 6, Math.Max(6, Width - 6));
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e); var g = e.Graphics; g.Clear(Color.FromArgb(25, 32, 42));
        for (int i = 0; i < Images.Count; i++) g.DrawImage(Images[i], new Rectangle(i * Width / 12, 6, Width / 12 + 1, Height - 12));
        using var shade = new SolidBrush(Color.FromArgb(170, 0, 0, 0));
        g.FillRectangle(shade, 0, 6, X(Start), Height - 12); g.FillRectangle(shade, X(End), 6, Width - X(End), Height - 12);
        using var accent = new Pen(Color.FromArgb(133, 240, 196), 2);
        g.DrawRectangle(accent, X(Start), 6, Math.Max(1, X(End) - X(Start)), Height - 12);
        g.DrawLine(Pens.White, X(Position), 0, X(Position), Height);
        using var handle = new SolidBrush(accent.Color);
        g.FillRectangle(handle, X(Start) - 6, 0, 12, Height); g.FillRectangle(handle, X(End) - 6, 0, 12, Height);
        g.DrawLine(Pens.Black, X(Start), 32, X(Start), 52); g.DrawLine(Pens.Black, X(End), 32, X(End), 52);
    }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Button != MouseButtons.Left) return; drag = Math.Abs(e.X - X(Start)) < 12 ? 1 : Math.Abs(e.X - X(End)) < 12 ? 2 : 3; Capture = true; MoveTo(e.X); }
    protected override void OnMouseMove(MouseEventArgs e) { base.OnMouseMove(e); if (Capture) MoveTo(e.X); }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); Capture = false; drag = 0; }
    void MoveTo(int x) => Scrub?.Invoke(Math.Clamp((x - 6.0) / Math.Max(1, Width - 12), 0, 1) * Duration, drag);
    protected override void Dispose(bool disposing) { if (disposing) foreach (var image in Images) image.Dispose(); base.Dispose(disposing); }
}
internal sealed class TrimWindow : Form
{
    readonly string file, tools = Path.Combine(AppContext.BaseDirectory, "Tools");
    readonly string scratch = Path.Combine(Path.GetTempPath(), "Peak trim " + Guid.NewGuid());
    readonly CancellationTokenSource lifetime = new();
    CancellationTokenSource? previewCancellation, exportCancellation;
    readonly PictureBox preview = new() { SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Black };
    readonly Timeline timeline = new();
    readonly NumericUpDown start = new(), end = new();
    readonly Label time = new(), duration = new(), status = new(), note = new();
    readonly Button save = new(), cancel = new(), reveal = new();
    readonly ProgressBar progress = new();
    MediaInfo? info; double playhead; bool updating, closed; string? completed;
    readonly bool smoke;
    public TrimWindow(string file, bool smoke = false)
    {
        this.file = file; this.smoke = smoke;
        Text = "Peak · Trim video"; ClientSize = new Size(900, 790); MinimumSize = new Size(800, 760);
        BackColor = Color.FromArgb(14, 19, 26); ForeColor = Color.WhiteSmoke; Font = new Font("Segoe UI", 10); AutoScaleMode = AutoScaleMode.Dpi; StartPosition = FormStartPosition.CenterParent;
        var page = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, AutoScroll = true }; page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); Controls.Add(page);
        void Add(Control c, int height) { c.Dock = DockStyle.Fill; c.Margin = new Padding(0, 0, 0, 12); page.RowStyles.Add(new RowStyle(SizeType.Absolute, height)); page.Controls.Add(c, 0, page.RowCount++); }
        Add(new Label { Text = "Find your moment.", Font = new Font(Font.FontFamily, 24, FontStyle.Bold) }, 52);
        Add(new Label { Text = Path.GetFileName(file), AutoEllipsis = true, ForeColor = Color.Silver }, 32);
        Add(preview, 310);
        var transport = new FlowLayoutPanel();
        Button Button(string text, Action action) { var b = new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat }; b.Click += (_, _) => action(); return b; }
        transport.Controls.Add(Button("◀ Frame", () => Seek(playhead - (info?.Frame ?? 0))));
        transport.Controls.Add(Button("Frame ▶", () => Seek(playhead + (info?.Frame ?? 0))));
        time.Width = 145; time.Height = 32; time.Padding = new Padding(8, 5, 0, 0); transport.Controls.Add(time);
        transport.Controls.Add(Button("Set start here", () => SetStart(playhead)));
        transport.Controls.Add(Button("Set end here", () => SetEnd(playhead + (info?.Frame ?? 0))));
        Add(transport, 46); Add(timeline, 100);
        var fields = new FlowLayoutPanel();
        foreach (var (label, field) in new[] { ("Start (seconds)", start), ("End (seconds)", end) }) {
            fields.Controls.Add(new Label { Text = label, AutoSize = true, Padding = new Padding(0, 5, 0, 0) }); field.DecimalPlaces = 3; field.Increment = 0.033m; field.Width = 110; field.AccessibleName = label; fields.Controls.Add(field);
        }
        duration.AutoSize = true; duration.Padding = new Padding(10, 5, 0, 0); fields.Controls.Add(duration); Add(fields, 44);
        Add(note, 46);
        var actions = new FlowLayoutPanel(); save.Text = "Save trimmed MP4"; save.AutoSize = true; save.BackColor = Color.FromArgb(133, 240, 196); save.ForeColor = BackColor; save.Enabled = false;
        cancel.Text = "Cancel export"; cancel.AutoSize = true; cancel.Enabled = false;
        reveal.Text = "Show in Explorer"; reveal.AutoSize = true; reveal.Enabled = false;
        actions.Controls.AddRange([save, cancel, reveal]); Add(actions, 46); Add(progress, 20); status.Text = "Reading video…"; status.AutoEllipsis = true; Add(status, 45);
        start.ValueChanged += (_, _) => { if (!updating) SetStart((double)start.Value); };
        end.ValueChanged += (_, _) => { if (!updating) SetEnd((double)end.Value); };
        timeline.Scrub += (at, handle) => { if (handle == 1) SetStart(at); else if (handle == 2) SetEnd(at); else Seek(at); };
        save.Click += async (_, _) => await Export(); cancel.Click += (_, _) => exportCancellation?.Cancel();
        reveal.Click += (_, _) => { if (completed is not null) { var p = new ProcessStartInfo("explorer.exe") { UseShellExecute = true }; p.ArgumentList.Add("/select,"); p.ArgumentList.Add(completed); Process.Start(p); } };
        Shown += async (_, _) => await LoadMedia();
        FormClosing += (_, e) => { if (exportCancellation is not null) { e.Cancel = true; MessageBox.Show(this, "Cancel the export before closing the editor.", "Peak"); return; } closed = true; lifetime.Cancel(); previewCancellation?.Cancel(); };
        FormClosed += (_, _) => { preview.Image?.Dispose(); _ = Task.Run(async () => { await Task.Delay(2000); try { Directory.Delete(scratch, true); } catch (IOException) {} }); };
    }
    async Task LoadMedia()
    {
        try {
            Directory.CreateDirectory(scratch); info = await TrimPlan.Probe(tools, file, lifetime.Token);
            updating = true; start.Maximum = end.Maximum = (decimal)info.Duration; end.Value = (decimal)info.Duration; start.Increment = end.Increment = (decimal)info.Frame; updating = false;
            timeline.Duration = timeline.End = info.Duration; save.Enabled = true; RefreshRange();
            note.Text = info.Hdr ? "HDR exports use 10-bit HEVC/AAC with source color tags. Preview colors are approximate. Your original stays unchanged." : "Precise trim exports high-quality H.264/AAC at source resolution. Your original stays unchanged.";
            time.Text = TrimPlan.Timecode(0); await LoadFrame(0); status.Text = "Building timeline thumbnails…";
            for (int i = 0; i < 12; i++) {
                var output = Path.Combine(scratch, $"thumb-{i}.jpg");
                await Runner.Run(Path.Combine(tools, "ffmpeg.exe"), TrimPlan.FrameArguments(file, i * info.Duration / 12, info, output, 160), lifetime.Token);
                if (closed) return; using var image = Image.FromFile(output); timeline.Images.Add(new Bitmap(image)); timeline.Invalidate();
            }
            if (exportCancellation is null) status.Text = "Drag the handles to trim. Click the timeline to inspect a frame.";
            if (smoke) {
                if (time.ClientSize.Height - time.Padding.Vertical < time.Font.Height) throw new Exception("Playhead time label is clipped");
                using var bitmap = new Bitmap(Width, Height); DrawToBitmap(bitmap, new Rectangle(Point.Empty, Size)); bitmap.Save(Path.Combine(AppContext.BaseDirectory, "trim-ui-preview.png"));
                File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "trim-ui-test-passed.txt"), "Timeline thumbnails and frame preview rendered."); Close();
            }
        } catch (OperationCanceledException) {} catch (Exception e) { status.Text = e.Message; if (smoke) { File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "trim-ui-error.txt"), e.ToString()); Close(); } }
    }
    void RefreshRange() { timeline.Start = (double)start.Value; timeline.End = (double)end.Value; timeline.Invalidate(); duration.Text = "Selection " + TrimPlan.Timecode(timeline.End - timeline.Start); }
    void SetStart(double value) { if (info is null || exportCancellation is not null) return; updating = true; start.Value = (decimal)Math.Clamp(info.Snapped(value), 0, Math.Max(0, (double)end.Value - Math.Min(info.Frame, info.Duration))); updating = false; RefreshRange(); Seek((double)start.Value); }
    void SetEnd(double value) { if (info is null || exportCancellation is not null) return; updating = true; end.Value = (decimal)Math.Clamp(info.Snapped(value), Math.Min(info.Duration, (double)start.Value + Math.Min(info.Frame, info.Duration)), info.Duration); updating = false; RefreshRange(); Seek(Math.Max((double)start.Value, (double)end.Value - info.Frame)); }
    void Seek(double value)
    {
        if (info is null || exportCancellation is not null || closed) return;
        playhead = Math.Clamp(info.Snapped(value), 0, Math.Max(0, info.Duration - info.Frame)); time.Text = TrimPlan.Timecode(playhead); timeline.Position = playhead; timeline.Invalidate(); _ = LoadFrame(playhead);
    }
    async Task LoadFrame(double at)
    {
        if (info is null) return;
        previewCancellation?.Cancel(); previewCancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        var current = previewCancellation; var output = Path.Combine(scratch, Guid.NewGuid() + ".jpg");
        try {
            await Task.Delay(100, current.Token);
            await Runner.Run(Path.Combine(tools, "ffmpeg.exe"), TrimPlan.FrameArguments(file, at, info, output, 960), current.Token);
            if (closed || current != previewCancellation) return;
            using var image = Image.FromFile(output); var old = preview.Image; preview.Image = new Bitmap(image); old?.Dispose();
        } catch (OperationCanceledException) {} catch (Exception e) { if (!closed) status.Text = e.Message; }
        finally { try { File.Delete(output); } catch (IOException) {} current.Dispose(); if (previewCancellation == current) previewCancellation = null; }
    }
    async Task Export()
    {
        if (info is null || exportCancellation is not null) return;
        using var dialog = new SaveFileDialog { Filter = "MP4 video|*.mp4", InitialDirectory = Path.GetDirectoryName(file), FileName = Path.GetFileNameWithoutExtension(file) + " [trim " + Guid.NewGuid().ToString()[..6] + "].mp4", AddExtension = true };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        if (File.Exists(dialog.FileName)) { status.Text = "Choose a new filename to preserve existing media."; return; }
        var partial = Path.Combine(Path.GetDirectoryName(dialog.FileName)!, ".Peak-export-" + Guid.NewGuid() + ".mp4");
        var plan = new TrimPlan(file, (double)start.Value, (double)end.Value, info);
        completed = null; exportCancellation = new(); var token = exportCancellation.Token; previewCancellation?.Cancel();
        save.Enabled = start.Enabled = end.Enabled = timeline.Enabled = reveal.Enabled = false; cancel.Enabled = true; progress.Value = 0; status.Text = "Exporting selected range…";
        try {
            await Runner.Run(Path.Combine(tools, "ffmpeg.exe"), plan.Arguments(partial), token, line => {
                if (line.StartsWith("out_time_us=") && double.TryParse(line[12..], System.Globalization.CultureInfo.InvariantCulture, out var us)) BeginInvoke(() => { if (!token.IsCancellationRequested && exportCancellation is not null) progress.Value = (int)Math.Clamp(us / 1_000_000 / plan.Duration * 100, 0, 100); });
            });
            File.Move(partial, dialog.FileName); completed = dialog.FileName; status.Text = "Trimmed clip saved. Your original is unchanged."; progress.Value = 100;
        } catch (OperationCanceledException) { status.Text = "Export cancelled"; }
        catch (Exception e) { status.Text = "Couldn’t export: " + e.Message; }
        finally { try { File.Delete(partial); } catch (IOException) {} exportCancellation.Dispose(); exportCancellation = null; save.Enabled = start.Enabled = end.Enabled = timeline.Enabled = true; cancel.Enabled = false; reveal.Enabled = completed is not null; }
    }
}
