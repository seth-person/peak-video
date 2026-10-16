import Foundation

public struct MediaInfo: Sendable {
    public let duration: Double
    public let width: Int
    public let height: Int
    public let fps: Double
    public let hdr: Bool
    public let transfer: String
    public let primaries: String
    public let matrix: String
    public var frameDuration: Double { 1 / fps }
    public static func parse(_ json: String) throws -> MediaInfo {
        guard let data = json.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]],
              let video = streams.first(where: { $0["codec_type"] as? String == "video" }),
              let width = video["width"] as? Int, let height = video["height"] as? Int, width > 0, height > 0 else {
            throw PeakError.failed("Choose a file containing a video track.")
        }
        let format = root["format"] as? [String: Any]
        let duration = Double(video["duration"] as? String ?? format?["duration"] as? String ?? "") ?? 0
        guard duration.isFinite, duration > 0 else { throw PeakError.failed("This video has no usable duration.") }
        let rate = (video["avg_frame_rate"] as? String ?? "30/1").split(separator: "/").compactMap { Double($0) }
        let calculated = rate.count == 2 && rate[1] > 0 ? rate[0] / rate[1] : 30
        let fps = calculated.isFinite && calculated > 0 ? min(calculated, 1000) : 30
        let transfer = video["color_transfer"] as? String ?? ""
        return MediaInfo(duration: duration, width: width, height: height, fps: fps, hdr: ["smpte2084", "arib-std-b67"].contains(transfer), transfer: transfer, primaries: video["color_primaries"] as? String ?? "bt2020", matrix: video["color_space"] as? String ?? "bt2020nc")
    }
    public func snapped(_ time: Double) -> Double { time >= duration ? duration : min(duration, max(0, (time * fps).rounded() / fps)) }
    public static func probeArguments(_ input: URL) -> [String] { ["-v", "error", "-show_streams", "-show_format", "-of", "json", input.path] }
}

public struct TrimPlan: Sendable {
    public let input: URL
    public let start: Double
    public let end: Double
    public let info: MediaInfo
    public var duration: Double { end - start }
    public init(input: URL, start: Double, end: Double, info: MediaInfo) throws {
        guard input.isFileURL, start.isFinite, end.isFinite, start >= 0, end <= info.duration + 0.000001,
              end - start >= min(info.frameDuration, info.duration) - 0.000001 else {
            throw PeakError.failed("Choose a start and end within the video, at least one frame apart.")
        }
        self.input = input; self.start = min(info.snapped(start), max(0, info.duration - min(info.frameDuration, info.duration))); self.end = min(info.duration, max(self.start + min(info.frameDuration, info.duration), info.snapped(end))); self.info = info
    }
    public static func number(_ value: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value) }
    public static func timecode(_ value: Double) -> String {
        let ms = Int((max(0, value) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
    public static func frameArguments(input: URL, time: Double, info: MediaInfo, output: URL, width: Int) -> [String] {
        let filter = "scale=\(width):-2:force_original_aspect_ratio=decrease"
        return ["-v", "error", "-nostdin", "-ss", number(min(max(0, time), max(0, info.duration - info.frameDuration))), "-i", input.path,
                "-map", "0:v:0", "-frames:v", "1", "-vf", filter, "-q:v", "2", "-update", "1", "-n", output.path]
    }
    public func arguments(output: URL) -> [String] {
        var args = ["-v", "error", "-nostdin", "-ss", Self.number(start), "-i", input.path, "-t", Self.number(duration),
                    "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "0", "-map_chapters", "-1",
                    "-c:v", info.hdr ? "libx265" : "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", info.hdr ? "yuv420p10le" : "yuv420p",
                    "-c:a", "aac", "-b:a", "320k", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats"]
        if info.hdr { args += ["-tag:v", "hvc1", "-x265-params", "log-level=error", "-color_primaries", info.primaries, "-color_trc", info.transfer, "-colorspace", info.matrix] }
        return args + ["-n", output.path]
    }
}
