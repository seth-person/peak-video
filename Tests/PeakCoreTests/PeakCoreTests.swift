import Foundation
import PeakCore

final class PeakCoreTests {
    let directory = URL(fileURLWithPath: "/tmp/Peak test $(touch SHOULD_NOT_EXIST)")
    let tools = URL(fileURLWithPath: "/Applications/Peak.app/Contents/Resources/Tools")

    func testNormalizesSingleVideoAndDropsPlaylistAndTracking() throws {
        let expected = "https://www.youtube.com/watch?v=BaW_jenozKc"
        for input in [" https://youtu.be/BaW_jenozKc?t=12 ", "https://www.youtube.com/watch?v=BaW_jenozKc&list=abc", "https://m.youtube.com/shorts/BaW_jenozKc", "https://youtube.com/live/BaW_jenozKc"] {
            expectEqual(try DownloadPlan.normalizedURL(input), expected)
        }
    }

    func testRejectsLocalFilesImpersonationAndArgumentInjection() {
        for input in ["file:///etc/passwd", "--exec=touch /tmp/pwned", "https://youtube.com.evil.test/watch?v=BaW_jenozKc", "https://youtube.com@evil.test/watch?v=BaW_jenozKc", "https://youtube.com/playlist?list=abc", "https://youtube.com/watch?v=bad", "https://youtube.com:8080/watch?v=BaW_jenozKc"] {
            expectThrows(try DownloadPlan.normalizedURL(input), input)
        }
    }

    func testMaximumQualityHasNoCodecOrResolutionCap() throws {
        let plan = try DownloadPlan(url: "https://youtu.be/BaW_jenozKc", directory: directory, mode: .original, height: nil)
        expectEqual(plan.format, "bv+ba/b")
        let args = plan.downloadArguments(tools: tools)
        expectTrue(args.contains("--ignore-config"))
        expectTrue(args.contains("--no-playlist"))
        expectFalse(args.contains("--recode-video"))
        expectEqual(args[args.firstIndex(of: "--merge-output-format")! + 1], "mp4")
        expectEqual(args[args.firstIndex(of: "-P")! + 1], directory.path)
        expectEqual(Array(args.suffix(2)), ["--", plan.url])
    }

    func testCompatibilityNeverFallsBackToIncompatibleCodec() throws {
        let plan = try DownloadPlan(url: "https://youtu.be/BaW_jenozKc", directory: directory, mode: .compatible, height: 1080)
        expectEqual(plan.format, "bv[vcodec^=avc1][height<=1080]+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a][height<=1080]")
    }

    func testAudioUsesBestAudioAndCorrectConversion() throws {
        for output in [OutputFormat.wav, .mp3] {
            let plan = try DownloadPlan(url: "https://youtu.be/BaW_jenozKc", directory: directory, mode: .compatible, height: 720, output: output)
            expectEqual(plan.format, "ba/b")
            let args = plan.downloadArguments(tools: tools)
            expectFalse(args.contains("--remux-video"))
            expectTrue(args.contains("--extract-audio"))
            expectTrue(args.contains(output.fileExtension))
            expectTrue(args.contains(output == .wav ? "ExtractAudio+ffmpeg_o:-c:a pcm_s24le" : "320K"))
        }
    }

    func testProgressRejectsUnknownAndMalformedValues() {
        expectNil(DownloadProgress.parse("PEAK_PROGRESS:Unknown|NA|NA"))
        expectNil(DownloadProgress.parse("PEAK_PROGRESS:nan|NA|NA"))
        expectNil(DownloadProgress.parse("[download] 5%"))
        let p = DownloadProgress.parse("PEAK_PROGRESS: 42.5%| 4MiB/s|00:12")
        expectEqual(p?.fraction, 0.425)
        expectEqual(p?.eta, "00:12")
    }

    func testParsesMetadataWithWarningsAndRejectsLive() throws {
        let info = try VideoInfo.parse("WARNING: sample\n{\"title\":\"Test\",\"height\":2160,\"fps\":60,\"duration\":62}\n")
        expectEqual(info.title, "Test")
        expectTrue(info.summary.contains("2160p"))
        expectThrows(try VideoInfo.parse("{\"title\":\"Live\",\"is_live\":true}"))
        expectThrows(try VideoInfo.parse(""))
    }

    func testProcessArgumentsArePassedLiterally() async throws {
        let text = "literal $(touch /tmp/peak-injection) `echo no` ; spaces"
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", text])
        expectEqual(output, text)
    }

    func testProcessFailurePropagatesAndPreCancellationWorks() async {
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
            fail("Expected failure")
        } catch { expectTrue(error.localizedDescription.contains("code")) }
        let runner = ProcessRunner()
        runner.cancel()
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
            fail("Expected cancellation")
        } catch { expectTrue(error is CancellationError) }
    }

    func testCancellationStopsAnActiveProcess() async {
        let runner = ProcessRunner()
        let start = Date()
        let operation = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        runner.cancel()
        do { _ = try await operation.value; fail("Expected cancellation") }
        catch { expectTrue(error is CancellationError) }
        expectLessThan(Date().timeIntervalSince(start), 5)
    }
}

private var failures = 0
private func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1
    print("FAIL: \(file):\(line): \(message)")
}
private func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { fail("Expected true", file: file, line: line) } }
private func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { fail("\(a) != \(b)", file: file, line: line) } }
private func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
private func expectLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { expectTrue(a < b, file: file, line: line) }
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected error: " + message, file: file, line: line) } catch {}
}
@main struct CoreChecks {
    static func main() async throws {
        let suite = PeakCoreTests()
        try suite.testNormalizesSingleVideoAndDropsPlaylistAndTracking()
        suite.testRejectsLocalFilesImpersonationAndArgumentInjection()
        try suite.testMaximumQualityHasNoCodecOrResolutionCap()
        try suite.testCompatibilityNeverFallsBackToIncompatibleCodec()
        try suite.testAudioUsesBestAudioAndCorrectConversion()
        suite.testProgressRejectsUnknownAndMalformedValues()
        try suite.testParsesMetadataWithWarningsAndRejectsLive()
        try await suite.testProcessArgumentsArePassedLiterally()
        await suite.testProcessFailurePropagatesAndPreCancellationWorks()
        await suite.testCancellationStopsAnActiveProcess()
        print("10 test groups completed; \(failures) failures")
        if failures > 0 { exit(1) }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--trim-integration" {
            try await trimIntegration(tools: URL(fileURLWithPath: CommandLine.arguments[2]), directory: URL(fileURLWithPath: CommandLine.arguments[3]))
        }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--integration" {
            try await integration(tools: URL(fileURLWithPath: CommandLine.arguments[2]), directory: URL(fileURLWithPath: CommandLine.arguments[3]))
        }
    }

    static func trimIntegration(tools: URL, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("timeline fixture.mp4")
        let clip = directory.appendingPathComponent("precise clip.mp4")
        let frame = directory.appendingPathComponent("preview.jpg")
        let ffmpeg = tools.appendingPathComponent("ffmpeg"), ffprobe = tools.appendingPathComponent("ffprobe")
        let runner = ProcessRunner()
        _ = try await runner.run(executable: ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:v", "libx264", "-g", "120", "-pix_fmt", "yuv420p", "-c:a", "aac", "-n", source.path])
        let original = try Data(contentsOf: source)
        let metadata = try await runner.run(executable: ffprobe, arguments: MediaInfo.probeArguments(source))
        let info = try MediaInfo.parse(metadata)
        expectEqual(info.width, 640); expectEqual(info.height, 360); expectEqual(info.fps, 30)
        for (start, end) in [(Double.nan, 2.0), (-1, 2), (2, 1), (0, 5), (0, 0.001)] { expectThrows(try TrimPlan(input: source, start: start, end: end, info: info)) }
        expectThrows(try MediaInfo.parse("{\"streams\":[],\"format\":{\"duration\":\"1\"}}"))
        let plan = try TrimPlan(input: source, start: 22.0 / 30, end: 2.1, info: info)
        _ = try await runner.run(executable: ffmpeg, arguments: plan.arguments(output: clip))
        let output = try await runner.run(executable: ffprobe, arguments: MediaInfo.probeArguments(clip))
        let result = try MediaInfo.parse(output)
        expectLessThan(abs(result.duration - plan.duration), info.frameDuration / 2)
        expectEqual(result.width, info.width); expectEqual(result.height, info.height)
        expectTrue(output.contains("h264") && output.contains("aac"))
        _ = try await runner.run(executable: ffmpeg, arguments: TrimPlan.frameArguments(input: source, time: plan.start, info: info, output: frame, width: 960))
        expectTrue(try Data(contentsOf: frame).count > 1000)
        // Compare the first decoded export frame to the selected source frame.
        let comparison = try await runner.run(executable: ffmpeg, arguments: ["-v", "info", "-ss", TrimPlan.number(plan.start), "-i", source.path, "-i", clip.path, "-lavfi", "[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]psnr", "-frames:v", "1", "-f", "null", "-"])
        if let range = comparison.range(of: "average:"), let value = Double(comparison[range.upperBound...].prefix(while: { !$0.isWhitespace })) { expectTrue(value > 35) } else { fail("Missing frame quality comparison") }
        expectEqual(try Data(contentsOf: source), original)
        let beforeClip = try Data(contentsOf: clip)
        _ = try? await runner.run(executable: ffmpeg, arguments: plan.arguments(output: clip))
        expectEqual(try Data(contentsOf: clip), beforeClip)
        if failures > 0 { exit(1) }
        print("Precise non-keyframe trim, duration, first-frame PSNR, audio, thumbnails, bounds and original preservation passed.")
    }

    static func integration(tools: URL, directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (mode, outputFormat) in [(QualityMode.original, OutputFormat.mp4), (.compatible, .mp4), (.original, .wav), (.original, .mp3)] {
            let plan = try DownloadPlan(url: "https://www.youtube.com/watch?v=jNQXAC9IVRw", directory: directory, mode: mode, height: nil, output: outputFormat)
            let runner = ProcessRunner()
            let metadata = try await runner.run(executable: tools.appendingPathComponent("yt-dlp"), arguments: plan.inspectArguments(tools: tools))
            let info = try VideoInfo.parse(metadata)
            print("Selected: \(mode.rawValue): \(info.title) · \(info.summary)")
            let output = try await runner.run(executable: tools.appendingPathComponent("yt-dlp"), arguments: plan.downloadArguments(tools: tools)) { line in
                if !line.hasPrefix("PEAK_PROGRESS:") { print(line) }
            }
            guard let marker = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("PEAK_FILE:") }) else {
                throw PeakError.failed("Missing final-file marker")
            }
            let data = Data(marker.dropFirst("PEAK_FILE:".count).utf8)
            let file = try JSONDecoder().decode(String.self, from: data)
            guard file.hasSuffix("." + outputFormat.fileExtension), FileManager.default.fileExists(atPath: file) else { throw PeakError.failed("Output missing") }
            let probe = try await runner.run(executable: tools.appendingPathComponent("ffprobe"), arguments: ["-v", "error", "-show_streams", "-show_format", "-of", "json", file])
            let object = try JSONSerialization.jsonObject(with: Data(probe.utf8)) as! [String: Any]
            let streams = object["streams"] as! [[String: Any]]
            let video = streams.first(where: { $0["codec_type"] as? String == "video" })
            let audio = streams.first(where: { $0["codec_type"] as? String == "audio" })
            if outputFormat != .mp4 {
                expectNil(video)
                expectEqual(audio?["codec_name"] as? String, outputFormat == .wav ? "pcm_s24le" : "mp3")
                if outputFormat == .mp3 { expectEqual(audio?["bit_rate"] as? String, "320000") }
                print("Verified audio: \(outputFormat.rawValue)")
                continue
            }
            guard video != nil, audio != nil else { throw PeakError.failed("Missing audio or video stream") }
            expectEqual(video?["height"] as? Int, info.height)
            if mode == .compatible {
                expectEqual(video?["codec_name"] as? String, "h264")
                expectEqual(audio?["codec_name"] as? String, "aac")
            }
            print("Verified MP4: \(video?["codec_name"] ?? "?") + \(audio?["codec_name"] ?? "?")")
        }
        if failures > 0 { exit(1) }
        print("MP4 quality modes, WAV and MP3 passed real YouTube integration checks.")
    }
}
