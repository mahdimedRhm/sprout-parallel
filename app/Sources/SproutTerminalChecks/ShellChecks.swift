import CheckKit
import Foundation
import SproutTerminal

/// Polls `condition` (letting the main queue run the shell's I/O) until it's
/// true or `seconds` pass.
@MainActor
func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}

@MainActor
func shellChecks() async {
    let env = ShellTerminal.environment(base: ["PATH": "/bin", "TERM": "dumb"])
    check(env.contains("TERM=xterm-256color"), "environment sets TERM")
    check(env.contains("COLORTERM=truecolor"), "environment sets COLORTERM")
    check(env.contains("LANG=en_US.UTF-8"), "environment defaults LANG")
    check(env.contains("PATH=/bin"), "environment keeps the rest")
    check(ShellTerminal.environment(base: ["LANG": "fr_FR.UTF-8"]).contains("LANG=fr_FR.UTF-8"),
          "environment keeps an existing LANG")
    checkEqual(TerminalTheme.ansi.count, 16, "theme has 16 ANSI colours")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprout-term-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    check(ShellTerminal(directory: dir.appendingPathComponent("missing").path) == nil, "no shell for a missing folder")

    guard let terminal = ShellTerminal(directory: dir.path) else {
        check(false, "shell starts in an existing folder")
        return
    }
    var exited = false
    terminal.onExit = { exited = true }

    let marker = dir.appendingPathComponent("pwd.txt")
    terminal.terminalView.send(txt: "pwd -P > '\(marker.path)'\n")
    // Foundation drops the /private prefix that `pwd -P` keeps, so normalise both sides the same way.
    let realDir = dir.resolvingSymlinksInPath().path
    let startedInFolder = await waitUntil(10) {
        guard let printed = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        let path = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == realDir
    }
    check(startedInFolder, "shell starts in the worktree folder")
    check(!terminal.isBusy, "idle shell is not busy")

    terminal.terminalView.send(txt: "sleep 3\n")
    check(await waitUntil(3) { terminal.isBusy }, "busy while a command runs")
    checkEqual(terminal.title, "sleep", "title is the running command")
    check(await waitUntil(6) { !terminal.isBusy }, "idle again when it finishes")

    terminal.terminalView.send(txt: "exit\n")
    check(await waitUntil(5) { exited }, "exit fires onExit")

    guard let other = ShellTerminal(directory: dir.path) else {
        check(false, "second shell starts")
        return
    }
    var otherExited = false
    other.onExit = { otherExited = true }
    let pid = other.terminalView.process.shellPid
    other.terminate()
    _ = await waitUntil(1.5) { otherExited }
    check(!otherExited, "terminate() doesn't report an exit")
    check(!other.isBusy, "a terminated shell is not busy")
    // A zombie still answers kill(pid, 0) == 0; only a reaped process gives ESRCH.
    check(await waitUntil(5) { kill(pid, 0) == -1 && errno == ESRCH }, "terminate() reaps the shell (no zombie)")
}
