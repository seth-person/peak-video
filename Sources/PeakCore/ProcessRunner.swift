import Foundation
import Darwin

/// One instance per operation. No shell is used to execute downloader arguments.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        let active = process
        lock.unlock()
        if let active, active.isRunning { Self.stopTree(active.processIdentifier) }
    }

    private static func stopTree(_ pid: Int32) {
        let lookup = Process()
        let pipe = Pipe()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        lookup.arguments = ["-P", String(pid)]
        lookup.standardOutput = pipe
        lookup.standardError = FileHandle.nullDevice
        if (try? lookup.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            lookup.waitUntilExit()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if let child = Int32(line) { stopTree(child) }
            }
        }
        kill(pid, SIGTERM)
    }

    public func run(executable: URL, arguments: [String], onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                let pipe = Pipe()
                task.executableURL = executable
                task.arguments = arguments
                task.standardOutput = pipe
                task.standardError = pipe
                task.standardInput = FileHandle.nullDevice
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = executable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
                environment["PYTHONUNBUFFERED"] = "1"
                task.environment = environment
                self.lock.lock()
                if self.cancelled {
                    self.lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try task.run()
                    self.process = task
                    self.lock.unlock()
                } catch {
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                var pending = Data()
                var output = Data()
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    output.append(data)
                    // Keep logs bounded even for very long downloads.
                    if output.count > 4_000_000 { output.removeFirst(output.count - 4_000_000) }
                    pending.append(data)
                    while let newline = pending.firstIndex(of: 10) {
                        onLine(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                }
                if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
                task.waitUntilExit()
                self.lock.lock()
                self.process = nil
                let wasCancelled = self.cancelled
                self.lock.unlock()
                let text = String(decoding: output, as: UTF8.self)
                if wasCancelled { continuation.resume(throwing: CancellationError()) }
                else if task.terminationStatus != 0 {
                    let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    let message = lines.last(where: { $0.contains("ERROR:") }) ?? lines.suffix(4).joined(separator: "\n")
                    continuation.resume(throwing: PeakError.failed(message.isEmpty ? "The download tool exited with code \(task.terminationStatus)." : message))
                } else { continuation.resume(returning: text) }
            }
        }
    }
}
