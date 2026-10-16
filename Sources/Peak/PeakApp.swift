import SwiftUI
import AppKit
import PeakCore

@MainActor
final class DownloadModel: ObservableObject {
    @Published var link = ""
    @Published var mode = QualityMode.original
    @Published var resolution = 0
    @Published var output = OutputFormat.mp4
    @Published var directory: URL
    @Published var info: VideoInfo?
    @Published var progress: DownloadProgress?
    @Published var status = "Ready when you are"
    @Published var busy = false
    @Published var inspecting = false
    @Published var error: String?
    @Published var completed: URL?
    @Published var log = ""
    @Published var showDetails = false
    private var runner: ProcessRunner?
    private var operationID = UUID()

    init() {
        if let path = UserDefaults.standard.string(forKey: "downloadDirectory") {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Peak", isDirectory: true)
        }
    }

    var tools: URL { Bundle.main.resourceURL!.appendingPathComponent("Tools", isDirectory: true) }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save here"
        panel.directoryURL = directory
        if panel.runModal() == .OK, let url = panel.url {
            directory = url
            UserDefaults.standard.set(url.path, forKey: "downloadDirectory")
        }
    }

    func clearPreview() { info = nil; completed = nil; error = nil; progress = nil; status = "Ready when you are" }

    func start(previewOnly: Bool) {
        guard !busy else { return }
        let plan: DownloadPlan
        do {
            plan = try DownloadPlan(url: link, directory: directory, mode: mode, height: resolution == 0 ? nil : resolution, output: output)
            for tool in ["yt-dlp", "ffmpeg", "ffprobe", "deno"] {
                guard FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent(tool).path) else { throw PeakError.missingTool(tool) }
            }
            if !previewOnly {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard FileManager.default.isWritableFile(atPath: directory.path) else { throw PeakError.failed("Choose a folder you can write to.") }
            }
        } catch { self.error = error.localizedDescription; return }
        busy = true; inspecting = true; error = nil; completed = nil; progress = nil; info = nil; log = ""
        status = "Finding the best available streams…"
        let id = UUID()
        operationID = id
        let job = ProcessRunner()
        runner = job
        let tools = self.tools
        Task { [self] in
            do {
                let metadata = try await job.run(executable: tools.appendingPathComponent("yt-dlp"), arguments: plan.inspectArguments(tools: tools))
                info = try VideoInfo.parse(metadata)
                inspecting = false
                if previewOnly {
                    status = "Preview ready"
                } else {
                    status = "Downloading original streams…"
                    let output = try await job.run(executable: tools.appendingPathComponent("yt-dlp"), arguments: plan.downloadArguments(tools: tools)) { [weak self] line in
                        Task { @MainActor in
                            guard let self, self.operationID == id, self.busy else { return }
                            self.receive(line)
                        }
                    }
                    guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("PEAK_FILE:") }),
                          let data = String(line.dropFirst("PEAK_FILE:".count)).data(using: .utf8),
                          let path = try? JSONDecoder().decode(String.self, from: data),
                          path.lowercased().hasSuffix("." + plan.output.fileExtension), FileManager.default.fileExists(atPath: path) else {
                        throw PeakError.failed("The tool finished but did not report the expected output file. Open details to review its output.")
                    }
                    completed = URL(fileURLWithPath: path)
                    status = "Saved your \(plan.output.rawValue)"
                }
            } catch is CancellationError {
                status = "Cancelled — retry to resume partial downloads"
            } catch {
                self.error = error.localizedDescription
                log += error.localizedDescription + "\n"
                status = "Couldn’t finish"
            }
            busy = false; inspecting = false; runner = nil
        }
    }

    private func receive(_ line: String) {
        if let update = DownloadProgress.parse(line) {
            progress = update
            status = "Downloading · \(update.speed.trimmingCharacters(in: .whitespaces)) · \(update.eta.trimmingCharacters(in: .whitespaces)) left"
        } else if line.contains("[Merger]") || line.contains("[VideoRemuxer]") || line.contains("[Metadata]") || line.contains("[ExtractAudio]") {
            progress = nil
            status = "Finishing your \(output.rawValue)…"
        }
        if !line.hasPrefix("PEAK_PROGRESS:") {
            log += line + "\n"
            if log.count > 24_000 { log = String(log.suffix(24_000)) }
        }
    }

    func cancel() {
        status = "Cancelling…"
        let job = runner
        DispatchQueue.global(qos: .userInitiated).async { job?.cancel() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: DownloadModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let model, model.busy else { return .terminateNow }
            let alert = NSAlert()
            alert.messageText = "Cancel the current download and quit?"
            alert.informativeText = "Partial downloads stay in your save folder and can resume when you retry."
            alert.addButton(withTitle: "Keep downloading")
            alert.addButton(withTitle: "Cancel and quit")
            if alert.runModal() == .alertSecondButtonReturn {
                model.cancel()
                Task { @MainActor in
                    while model.busy { try? await Task.sleep(nanoseconds: 100_000_000) }
                    NSApplication.shared.reply(toApplicationShouldTerminate: true)
                }
                return .terminateLater
            }
            return .terminateCancel
        }
    }
}

@main
struct PeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = DownloadModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { delegate.model = model }
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 820, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Open download folder") { NSWorkspace.shared.open(model.directory) }
            }
        }
    }
}

private let mint = Color(red: 0.52, green: 0.94, blue: 0.77)
private let canvasColor = Color(red: 0.055, green: 0.075, blue: 0.10)

struct ContentView: View {
    @ObservedObject var model: DownloadModel
        var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader
                hero
                linkCard
                settingsCard
                downloadControls
                footer
            }.padding(32).frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }
        .background(canvasColor).frame(minWidth: 740, minHeight: 740)
        .onChange(of: model.link) { _, _ in model.clearPreview() }
        .onChange(of: model.mode) { _, _ in model.clearPreview() }
        .onChange(of: model.output) { _, _ in model.clearPreview() }
        .onChange(of: model.resolution) { _, _ in model.clearPreview() }
    }

    private var brandHeader: some View {
                HStack(alignment: .top) {
                    HStack(spacing: 12) {
                        Image(systemName: "mountain.2.fill").font(.system(size: 30)).foregroundStyle(mint)
                        Text("Peak").font(.system(size: 29, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Text("LOCAL BY DESIGN").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2).foregroundStyle(mint).padding(.top, 12)
                }

    }

    private var hero: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep every detail.").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("YouTube to MP4, WAV or MP3. Your media, saved on your Mac.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }

    }

    private var linkCard: some View {
                VStack(alignment: .leading, spacing: 14) {
                    eyebrow("01", "VIDEO LINK")
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(mint)
                        TextField("Paste a YouTube video URL", text: $model.link)
                            .textFieldStyle(.plain).font(.system(size: 15))
                            .onSubmit { model.start(previewOnly: true) }
                            .accessibilityLabel("YouTube video URL")
                        Button("Paste") { model.link = NSPasteboard.general.string(forType: .string) ?? "" }
                            .buttonStyle(.borderless).foregroundStyle(mint)
                    }
                    .padding(16).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
                    .disabled(model.busy)
                    HStack {
                        Text("Videos, Shorts, and finished livestreams.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Preview video", systemImage: "sparkle.magnifyingglass") { model.start(previewOnly: true) }
                            .buttonStyle(.borderless).foregroundStyle(mint).disabled(model.busy || model.link.isEmpty)
                    }
                    if let info = model.info {
                        HStack(spacing: 14) {
                            Image(systemName: "play.rectangle.fill").font(.system(size: 30)).foregroundStyle(mint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: info.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                Text([info.uploader, info.summary].compactMap { $0 }.joined(separator: "  ·  "))
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.top, 6)
                    }
                }.card()

    }

    private var settingsCard: some View {
                VStack(alignment: .leading, spacing: 16) {
                    eyebrow("02", "FORMAT & DESTINATION")
                    Picker("Output format", selection: $model.output) {
                        Text("MP4 · Video").tag(OutputFormat.mp4)
                        Text("WAV · Audio").tag(OutputFormat.wav)
                        Text("MP3 · Audio").tag(OutputFormat.mp3)
                    }.pickerStyle(.segmented)
                    if model.output == .mp4 {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(QualityMode.allCases) { mode in
                            Button { model.mode = mode } label: {
                                QualityCard(mode: mode, selected: model.mode == mode)
                            }.buttonStyle(.plain).accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                        }
                    }
                    HStack {
                        Text("Resolution limit").foregroundStyle(.secondary)
                        Spacer()
                        Picker("Resolution limit", selection: $model.resolution) {
                            Text("Best available · no limit").tag(0)
                            Text("Up to 4K · 2160p").tag(2160)
                            Text("Up to 1440p").tag(1440)
                            Text("Up to 1080p").tag(1080)
                            Text("Up to 720p").tag(720)
                        }.labelsHidden().frame(width: 230)
                    }.font(.system(size: 13))
                    } else {
                        Text(model.output.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    }
                    Divider().opacity(0.4)
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(mint)
                        Text(model.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.middle).help(model.directory.path)
                        Spacer()
                        Button("Change…") { model.chooseFolder() }.buttonStyle(.borderless).foregroundStyle(mint)
                    }
                }.card().disabled(model.busy)

    }

    private var downloadControls: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Button { model.start(previewOnly: false) } label: {
                            Label("Download \(model.output.rawValue)", systemImage: "arrow.down.to.line")
                                .font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        .buttonStyle(.plain).background(model.busy || model.link.isEmpty ? mint.opacity(0.25) : mint, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(canvasColor).disabled(model.busy || model.link.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        if model.busy { Button("Cancel") { model.cancel() }.buttonStyle(.bordered).controlSize(.large) }
                        if let file = model.completed {
                            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                                .buttonStyle(.bordered).controlSize(.large)
                        }
                    }
                    if model.busy {
                        if let progress = model.progress {
                            ProgressView(value: progress.fraction).tint(mint)
                            Text("Current stream: \(Int(progress.fraction * 100))% · \(model.output == .mp4 ? "video and audio download separately" : "audio only")")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        } else { ProgressView().controlSize(.small) }
                    }
                    HStack {
                        Image(systemName: model.completed != nil ? "checkmark.circle.fill" : "circle.dotted").foregroundStyle(mint)
                        Text(verbatim: model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.showDetails ? "Hide details" : "Details") { model.showDetails.toggle() }.buttonStyle(.borderless).font(.system(size: 12))
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error).font(.system(size: 12)).textSelection(.enabled)
                            Text("If YouTube asks you to sign in or blocks a request, try again later. Peak 1.1 does not import browser cookies.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.showDetails {
                        ScrollView {
                            Text(model.log.isEmpty ? "Download diagnostics will appear here." : model.log)
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.frame(height: 150).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

    }

    private var footer: some View {
                HStack {
                    Text("PEAK 1.1").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5)
                    Spacer()
                    Text("Download videos you own or have permission to save.").font(.system(size: 10))
                }.foregroundStyle(.secondary)
    }

    private func eyebrow(_ number: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(number).foregroundStyle(mint)
            Text(label).foregroundStyle(.secondary).tracking(1.6)
        }.font(.system(size: 10, weight: .semibold, design: .monospaced))
    }
}

private extension View {
    func card() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.075)))
    }
}

private struct QualityCard: View {
    let mode: QualityMode
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: mode == .original ? "waveform.path" : "display")
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }.foregroundStyle(selected ? mint : Color.secondary)
            Text(verbatim: mode.rawValue).font(.system(size: 14, weight: .semibold))
            Text(verbatim: mode.detail).font(.system(size: 12)).foregroundStyle(Color.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 113, alignment: .top)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? mint.opacity(0.07) : Color.black.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? mint.opacity(0.7) : Color.white.opacity(0.1)))
    }
}
