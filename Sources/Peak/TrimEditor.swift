import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PeakCore

@MainActor
final class TrimModel: ObservableObject, Identifiable {
    let id = UUID()
    let file: URL
    let tools: URL
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Peak-trim-" + UUID().uuidString, isDirectory: true)
    @Published var info: MediaInfo?
    @Published var thumbnails: [NSImage] = []
    @Published var preview: NSImage?
    @Published var playhead = 0.0
    @Published var start = 0.0
    @Published var end = 0.0
    @Published var status = "Reading video…"
    @Published var error: String?
    @Published var exporting = false
    @Published var fraction = 0.0
    @Published var completed: URL?
    private var loaded = false
    private var closed = false
    private var loader = ProcessRunner()
    private var previewRunner: ProcessRunner?
    private var previewTask: Task<Void, Never>?
    private var exportRunner: ProcessRunner?
    private var generation = UUID()
    init(file: URL, tools: URL) { self.file = file; self.tools = tools }

    func load() {
        guard !loaded else { return }; loaded = true
        Task {
            do {
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                let text = try await loader.run(executable: tools.appendingPathComponent("ffprobe"), arguments: MediaInfo.probeArguments(file))
                let media = try MediaInfo.parse(text)
                guard !closed else { return }
                info = media; end = media.duration; seek(0)
                status = "Building timeline thumbnails…"
                for index in 0..<12 {
                    let imageFile = scratch.appendingPathComponent("thumb-\(index).jpg")
                    _ = try await loader.run(executable: tools.appendingPathComponent("ffmpeg"), arguments: TrimPlan.frameArguments(input: file, time: media.duration * Double(index) / 12, info: media, output: imageFile, width: 160))
                    guard !closed else { return }
                    if let image = NSImage(contentsOf: imageFile) { thumbnails.append(image) }
                }
                if !exporting { status = "Drag the handles to trim. Click the timeline to inspect a frame." }
            } catch is CancellationError {} catch { if !closed { self.error = error.localizedDescription } }
        }
    }
    func seek(_ time: Double) {
        guard let info, time.isFinite, !exporting, !closed else { return }
        playhead = min(info.snapped(time), max(0, info.duration - info.frameDuration))
        let at = playhead; let token = UUID(); generation = token
        previewTask?.cancel(); previewRunner?.cancel()
        previewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
                let job = ProcessRunner(); previewRunner = job
                let imageFile = scratch.appendingPathComponent("frame-\(token).jpg")
                defer { try? FileManager.default.removeItem(at: imageFile) }
                _ = try await job.run(executable: tools.appendingPathComponent("ffmpeg"), arguments: TrimPlan.frameArguments(input: file, time: at, info: info, output: imageFile, width: 960))
                if generation == token && !closed { preview = NSImage(data: try Data(contentsOf: imageFile)) }
            } catch is CancellationError {} catch { if generation == token && !closed { self.error = error.localizedDescription } }
        }
    }
    func setStart(_ value: Double) {
        guard let info, value.isFinite else { return }
        start = min(info.snapped(value), max(0, end - min(info.frameDuration, info.duration)))
        completed = nil; seek(start)
    }
    func setEnd(_ value: Double) {
        guard let info, value.isFinite else { return }
        end = min(info.duration, max(start + min(info.frameDuration, info.duration), info.snapped(value)))
        completed = nil; seek(max(start, end - info.frameDuration))
    }
    func export() {
        guard let info, !exporting else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]
        panel.directoryURL = file.deletingLastPathComponent()
        panel.nameFieldStringValue = file.deletingPathExtension().lastPathComponent + " [trim " + UUID().uuidString.prefix(6) + "].mp4"
        panel.prompt = "Save clip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else { error = "Choose a new filename to preserve existing media."; return }
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".Peak-export-" + UUID().uuidString + ".mp4")
        exporting = true; error = nil; completed = nil; fraction = 0; status = "Exporting selected range…"
        previewTask?.cancel(); previewRunner?.cancel()
        let job = ProcessRunner(); exportRunner = job
        Task { [self] in
            defer { exporting = false; exportRunner = nil; try? FileManager.default.removeItem(at: partial) }
            do {
                let plan = try TrimPlan(input: file, start: start, end: end, info: info)
                _ = try await job.run(executable: tools.appendingPathComponent("ffmpeg"), arguments: plan.arguments(output: partial)) { [weak self] line in
                    if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                        Task { @MainActor in self?.fraction = min(1, max(0, us / 1_000_000 / plan.duration)) }
                    }
                }
                try FileManager.default.moveItem(at: partial, to: destination)
                completed = destination; fraction = 1; status = "Trimmed clip saved. Your original is unchanged."
            } catch is CancellationError { status = "Export cancelled" }
            catch { self.error = error.localizedDescription; status = "Couldn’t export the clip" }
        }
    }
    func cancelExport() { exportRunner?.cancel() }
    func close() {
        closed = true; generation = UUID(); previewTask?.cancel(); previewRunner?.cancel(); loader.cancel(); exportRunner?.cancel()
        // Readers may still be unwinding; remove scratch files after their process cancellation.
        let folder = scratch
        Task.detached { try? await Task.sleep(nanoseconds: 2_000_000_000); try? FileManager.default.removeItem(at: folder) }
    }
}

struct TrimEditor: View {
    @ObservedObject var model: TrimModel
    @Environment(\.dismiss) private var dismiss
    private let accent = Color(red: 0.52, green: 0.94, blue: 0.77)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your moment.").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(model.file.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Close") { dismiss() }.disabled(model.exporting)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.black)
                if let image = model.preview { Image(nsImage: image).resizable().scaledToFit().padding(2) }
                else { ProgressView("Loading frame…") }
            }.frame(height: 300).accessibilityLabel("Video frame preview at " + TrimPlan.timecode(model.playhead))
            if let info = model.info {
                HStack {
                    Button("Previous frame", systemImage: "backward.frame") { model.seek(model.playhead - info.frameDuration) }.labelStyle(.iconOnly)
                    Button("Next frame", systemImage: "forward.frame") { model.seek(model.playhead + info.frameDuration) }.labelStyle(.iconOnly)
                    Text(TrimPlan.timecode(model.playhead)).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Set start here") { model.setStart(model.playhead) }
                    Button("Set end here") { model.setEnd(model.playhead + info.frameDuration) }
                }.disabled(model.exporting)
                timeline(info)
                HStack {
                    timeField("Start (seconds)", value: Binding(get: { model.start }, set: { model.setStart($0) }))
                    timeField("End (seconds)", value: Binding(get: { model.end }, set: { model.setEnd($0) }))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("SELECTION").font(.caption2).foregroundStyle(.secondary)
                        Text(TrimPlan.timecode(model.end - model.start)).font(.system(.body, design: .monospaced))
                    }
                }.disabled(model.exporting)
                Text(info.hdr ? "HDR exports use 10-bit HEVC/AAC with the source color tags. Preview colors are approximate. Your original stays unchanged." : "Precise trim exports high-quality H.264/AAC at the source resolution. Your original stays unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save trimmed MP4", systemImage: "scissors") { model.export() }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(model.exporting)
                    if model.exporting { Button("Cancel export") { model.cancelExport() } }
                    if let file = model.completed { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
                    Spacer()
                }
            }
            if model.exporting { ProgressView(value: model.fraction).tint(accent) }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(24).frame(width: 850).frame(minHeight: 690)
            .background(Color(red: 0.055, green: 0.075, blue: 0.10)).preferredColorScheme(.dark)
            .onAppear { model.load() }.onDisappear { model.close() }.interactiveDismissDisabled(model.exporting)
    }
    private func timeField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(3)))
                .textFieldStyle(.roundedBorder).frame(width: 140).accessibilityLabel(label)
        }
    }
    private func timeline(_ info: MediaInfo) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let left = width * model.start / info.duration
            let right = width * model.end / info.duration
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { i in
                        ZStack {
                            Color.white.opacity(0.05)
                            if i < model.thumbnails.count { Image(nsImage: model.thumbnails[i]).resizable().scaledToFill() }
                        }.frame(width: width / 12, height: 72).clipped()
                    }
                }
                Color.black.opacity(0.62).frame(width: left, height: 72)
                Color.black.opacity(0.62).frame(width: max(0, width - right), height: 72).offset(x: right)
                Rectangle().stroke(accent, lineWidth: 2).frame(width: max(1, right - left), height: 72).offset(x: left)
                Rectangle().fill(.white).frame(width: 2, height: 82).offset(x: min(width - 2, width * model.playhead / info.duration))
                handle("Trim start", x: left, width: width, info: info, start: true)
                handle("Trim end", x: right, width: width, info: info, start: false)
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in model.seek(value.location.x / width * info.duration) })
                .disabled(model.exporting)
        }.frame(height: 82).coordinateSpace(name: "trimTimeline").accessibilityLabel("Thumbnail timeline. Use start and end fields for precise times.")
    }
    private func handle(_ label: String, x: Double, width: Double, info: MediaInfo, start: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 12, height: 82)
            .overlay(Text("⋮").foregroundStyle(.black)).offset(x: min(max(0, x - 6), width - 12))
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTimeline")).onChanged { value in
                // Translate from the handle's initial location to avoid cumulative drag drift.
                let time = (value.location.x / width) * info.duration
                if start { model.setStart(time) } else { model.setEnd(time) }
            }).accessibilityLabel(label)
    }
}
