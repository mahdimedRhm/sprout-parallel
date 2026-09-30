import Foundation

public struct ShellResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol Shell: AnyObject {
    /// Runs `command` and returns once it exits. `onLine` receives each line of
    /// stdout and stderr as it arrives, on a background thread.
    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult
}

/// Quotes `s` for a POSIX shell, leaving plainly safe strings untouched so
/// commands shown to the user stay readable.
public func shellQuote(_ s: String) -> String {
    let safe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@%+=:,-")
    if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
        return s
    }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Runs commands through a login shell (`zsh -lic`) so GUI launches get the
/// user's PATH, including anything set in ~/.zshrc (Homebrew, ~/.local/bin, …).
public final class LoginShell: Shell {
    private let shellPath: String

    public init(shellPath: String = "/bin/zsh") {
        self.shellPath = shellPath
    }

    public func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shellPath)
            process.arguments = ["-lic", command]
            process.standardInput = FileHandle.nullDevice
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ShellResult(exitCode: 127, stderr: error.localizedDescription))
                return
            }

            let out = LineCollector(onLine: onLine)
            let err = LineCollector(onLine: onLine)
            let group = DispatchGroup()

            for (pipe, collector) in [(outPipe, out), (errPipe, err)] {
                group.enter()
                DispatchQueue.global().async {
                    let handle = pipe.fileHandleForReading
                    while true {
                        let data = handle.availableData
                        if data.isEmpty { break }
                        collector.append(data)
                    }
                    group.leave()
                }
            }

            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }

            group.notify(queue: .global()) {
                continuation.resume(returning: ShellResult(
                    exitCode: process.terminationStatus,
                    stdout: out.finish(),
                    stderr: err.finish()))
            }
        }
    }
}

/// Splits a byte stream into lines, reporting each complete line as it arrives.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var text = ""
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        emitCompleteLines()
    }

    /// Flushes a trailing partial line and returns everything collected.
    func finish() -> String {
        lock.lock(); defer { lock.unlock() }
        emitCompleteLines()
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            text += line
            onLine(line)
        }
        return text
    }

    private func emitCompleteLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            text += line + "\n"
            onLine(line)
        }
    }
}
