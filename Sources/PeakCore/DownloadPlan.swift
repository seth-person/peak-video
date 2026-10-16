import Foundation

public enum QualityMode: String, CaseIterable, Identifiable, Sendable {
    case original = "Maximum quality"
    case compatible = "Wide compatibility"
    public var id: String { rawValue }
    public var detail: String {
        switch self {
        case .original: return "Best available video + audio. No re-encoding. May use AV1, VP9 or Opus; use a player that supports those codecs."
        case .compatible: return "H.264 video + AAC audio for broad playback support. YouTube may only offer these formats up to 1080p."
        }
    }
}

public enum PeakError: LocalizedError {
    case invalidURL, missingTool(String), failed(String), liveVideo
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Paste a YouTube video link (youtube.com or youtu.be). Playlist-only links are not supported."
        case .missingTool(let name): return "The bundled \(name) tool is missing. Reinstall Peak."
        case .failed(let message): return message
        case .liveVideo: return "This video is live or upcoming. Try again after the stream has finished."
        }
    }
}

public struct DownloadPlan: Sendable {
    public let url: String
    public let directory: URL
    public let mode: QualityMode
    public let height: Int?
    public init(url: String, directory: URL, mode: QualityMode, height: Int?) throws {
        self.url = try Self.normalizedURL(url)
        self.directory = directory
        self.mode = mode
        self.height = height
    }

    public static func normalizedURL(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: text),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be"].contains(host),
              parts.user == nil, parts.password == nil, parts.port == nil else { throw PeakError.invalidURL }
        let segments = parts.path.split(separator: "/").map(String.init)
        let id: String?
        if host.hasSuffix("youtu.be") { id = segments.first }
        else if parts.path == "/watch" { id = parts.queryItems?.first(where: { $0.name == "v" })?.value }
        else if segments.count == 2, ["shorts", "live", "embed"].contains(segments[0]) { id = segments[1] }
        else { id = nil }
        guard let id, id.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil else { throw PeakError.invalidURL }
        parts = URLComponents(string: "https://www.youtube.com/watch")!
        parts.queryItems = [URLQueryItem(name: "v", value: id)]
        return parts.url!.absoluteString
    }

    public var format: String {
        let limit = height.map { "[height<=\($0)]" } ?? ""
        switch mode {
        case .original: return "bv\(limit)+ba/b\(limit)"
        case .compatible: return "bv[vcodec^=avc1]\(limit)+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a]\(limit)"
        }
    }

    public func commonArguments(tools: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-colors", "--newline",
         "--no-remote-components", "--no-js-runtimes", "--js-runtimes", "deno:\(tools.appendingPathComponent("deno").path)",
         "--ffmpeg-location", tools.path, "--socket-timeout", "20", "--retries", "5",
         "--fragment-retries", "5", "--match-filter", "!is_live & !is_upcoming", "-f", format,
         "-S", "res,fps,hdr:12,vcodec,channels,acodec,br,size"]
    }

    public func inspectArguments(tools: URL) -> [String] {
        commonArguments(tools: tools) + ["--skip-download", "--dump-single-json", "--", url]
    }

    public func downloadArguments(tools: URL) -> [String] {
        let preset = (mode == .original ? "source" : "h264") + "-" + (height.map(String.init) ?? "best")
        return commonArguments(tools: tools) + [
            "--no-simulate", "--no-quiet", "--no-overwrites", "--continue", "--windows-filenames",
            "--concurrent-fragments", "4", "--merge-output-format", "mp4", "--remux-video", "mp4",
            "--embed-metadata", "--embed-chapters", "--progress", "--progress-delta", "0.25",
            "--progress-template", "download:PEAK_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--print", "after_move:PEAK_FILE:%(filepath)j",
            "-P", directory.path, "-o", "%(title).130B [%(id)s] [\(preset)].%(ext)s", "--", url
        ]
    }
}

public struct VideoInfo: Decodable, Sendable {
    public let title: String
    public let uploader: String?
    public let duration: Double?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let vcodec: String?
    public let acodec: String?
    public let is_live: Bool?
    public let live_status: String?
    public let filesize: Double?
    public let filesize_approx: Double?

    public var summary: String {
        var values: [String] = []
        if let height { values.append("\(height)p") }
        if let fps { values.append("\(Int(fps)) fps") }
        if let duration { values.append(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)) }
        if let size = filesize ?? filesize_approx { values.append("≈ " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        return values.joined(separator: "  ·  ")
    }

    public static func parse(_ output: String) throws -> VideoInfo {
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("{") }), let data = line.data(using: .utf8) else {
            throw PeakError.failed("No downloadable video was found. Live and upcoming streams are not supported.")
        }
        let info = try JSONDecoder().decode(VideoInfo.self, from: data)
        if info.is_live == true || info.live_status == "is_upcoming" { throw PeakError.liveVideo }
        return info
    }
}

public struct DownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let speed: String
    public let eta: String
    public static func parse(_ line: String) -> DownloadProgress? {
        guard line.hasPrefix("PEAK_PROGRESS:") else { return nil }
        let fields = line.dropFirst("PEAK_PROGRESS:".count).components(separatedBy: "|")
        guard fields.count == 3,
              let value = Double(fields[0].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        return DownloadProgress(fraction: min(1, max(0, value / 100)), speed: fields[1], eta: fields[2])
    }
}
