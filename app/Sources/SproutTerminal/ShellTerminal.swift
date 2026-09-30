import AppKit
import Darwin
import SwiftTerm

/// Zero-size subview of the terminal view that reports when the terminal (or a
/// descendant) becomes or stops being its window's first responder. SwiftTerm's
/// responder methods aren't open for overriding, so it watches the window instead.
final class FocusProbe: NSView {
    var onChange: ((Bool) -> Void)?
    private var observation: NSKeyValueObservation?
    private var focused = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else {
            report(false)
            return
        }
        observation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            self?.update(window)
        }
    }

    private func update(_ window: NSWindow) {
        guard let target = superview else { return }
        var inside = false
        if let responder = window.firstResponder as? NSView {
            inside = responder === target || responder.isDescendant(of: target)
        }
        report(inside)
    }

    private func report(_ value: Bool) {
        guard value != focused else { return }
        focused = value
        onChange?(value)
    }
}

/// A real login shell running in a folder inside a SwiftTerm view.
@MainActor
public final class ShellTerminal: NSObject, TerminalHandle {
    public let id = UUID()
    public let terminalView: LocalProcessTerminalView
    private let focusProbe = FocusProbe()
    public var onExit: (() -> Void)?
    public var onFocusChange: ((Bool) -> Void)? {
        get { focusProbe.onChange }
        set { focusProbe.onChange = newValue }
    }
    public var view: NSView? { terminalView }

    private let shellName: String
    private var shellTitle: String?
    private var ended = false

    /// Returns nil when `directory` isn't an existing folder or the shell can't start.
    public init?(directory: String, shell: String = "/bin/zsh") {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        shellName = (shell as NSString).lastPathComponent
        terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        terminalView.addSubview(focusProbe)
        super.init()
        terminalView.processDelegate = self
        TerminalTheme.apply(to: terminalView)
        terminalView.startProcess(
            executable: shell, args: ["-l"], environment: Self.environment(), currentDirectory: directory)
        guard terminalView.process.running else { return nil }
    }

    /// The process environment plus what a colour terminal needs.
    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var env = base
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"]?.isEmpty ?? true { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Set once the shell has come up (see `foregroundProcessName`).
    private var ready = false

    /// Name of the terminal's foreground process group leader (the shell when idle).
    /// Nil until the shell has started: straight after the fork the foreground
    /// process still carries our own name, and zsh's startup would read as busy.
    public var foregroundProcessName: String? {
        guard !ended, terminalView.process.running else { return nil }
        let group = tcgetpgrp(terminalView.process.childfd)
        guard group > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(group, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        if !ready {
            if name == ProcessInfo.processInfo.processName && name != shellName { return nil }
            ready = true
        }
        return name
    }

    public var isBusy: Bool {
        guard let name = foregroundProcessName else { return false }
        return name != shellName
    }

    public var title: String {
        if let name = foregroundProcessName, name != shellName { return name }
        if let shellTitle, !shellTitle.isEmpty { return shellTitle }
        return shellName
    }

    public func terminate() {
        guard !ended else { return }
        ended = true
        let pid = terminalView.process.shellPid
        terminalView.terminate()
        Self.reap(pid)
    }

    public func send(_ text: String) {
        guard !ended else { return }
        terminalView.send(txt: text)
    }

    /// SwiftTerm stops watching the child once terminated, so nothing waits on it:
    /// reap it here, escalating to SIGKILL if it ignores SIGTERM.
    private static func reap(_ pid: pid_t) {
        guard pid > 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            for _ in 0..<20 {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid || (result == -1 && errno != EINTR) { return }
                usleep(50_000)
            }
            kill(pid, SIGKILL)
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
    }
}

extension ShellTerminal: LocalProcessTerminalViewDelegate {
    nonisolated public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.shellTitle = title }
        }
    }

    nonisolated public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated public func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // After terminate() the tab is already gone; only report exits the shell made itself.
                guard !self.ended else { return }
                self.ended = true
                self.onExit?()
            }
        }
    }
}
