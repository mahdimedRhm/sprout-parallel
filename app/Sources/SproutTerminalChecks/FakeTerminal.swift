import AppKit
import SproutTerminal

/// In-memory stand-in for a shell.
@MainActor
final class FakeTerminal: TerminalHandle {
    let id = UUID()
    var title = "zsh"
    var isBusy = false
    var view: NSView? { nil }
    var onExit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    private(set) var terminated = false

    func terminate() { terminated = true }

    private(set) var sent: [String] = []
    /// When true, ⌃C doesn't stop the running command.
    var ignoresInterrupt = false

    /// Records input; a line starts a command, ⌃C stops it (unless ignored).
    func send(_ text: String) {
        sent.append(text)
        if text == "\u{3}" {
            if !ignoresInterrupt { isBusy = false }
        } else if text.hasSuffix("\n") {
            isBusy = true
        }
    }

    /// Simulates the terminal view gaining or losing first responder.
    func setFocused(_ focused: Bool) { onFocusChange?(focused) }

    /// Simulates the shell exiting on its own (e.g. the user typed `exit`).
    func exitShell() { onExit?() }
}
