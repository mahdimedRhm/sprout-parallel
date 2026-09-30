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

    /// Simulates the terminal view gaining or losing first responder.
    func setFocused(_ focused: Bool) { onFocusChange?(focused) }

    /// Simulates the shell exiting on its own (e.g. the user typed `exit`).
    func exitShell() { onExit?() }
}
