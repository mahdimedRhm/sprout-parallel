import Foundation
import SproutCore

/// Shell double: answers each command via `respond`, emitting its stdout and
/// stderr lines through `onLine`, and records every command it was given.
final class FakeShell: Shell {
    private let respond: (String) -> ShellResult
    private(set) var commands: [String] = []
    var delayNanos: UInt64 = 0

    init(_ respond: @escaping (String) -> ShellResult) {
        self.respond = respond
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        commands.append(command)
        if delayNanos > 0 { try? await Task.sleep(nanoseconds: delayNanos) }
        let result = respond(command)
        for line in (result.stdout + "\n" + result.stderr).split(separator: "\n") {
            onLine(String(line))
        }
        return result
    }
}

/// Thread-safe line accumulator for streaming callbacks.
final class LinesBox {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock(); storage.append(line); lock.unlock()
    }

    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
