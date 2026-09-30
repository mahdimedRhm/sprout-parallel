import AppKit

/// One shell session as `TerminalSessions` sees it. `ShellTerminal` is the real
/// one; checks use fakes.
@MainActor
public protocol TerminalHandle: AnyObject {
    var id: UUID { get }
    /// What the tab shows: the running command, else the shell's title, else the shell name.
    var title: String { get }
    /// A command other than the shell itself is in the foreground.
    var isBusy: Bool { get }
    /// The view to host; nil for fakes.
    var view: NSView? { get }
    /// Called once if the shell exits on its own (not after `terminate()`).
    var onExit: (() -> Void)? { get set }
    /// Called with true/false as the terminal view becomes/resigns first responder.
    var onFocusChange: ((Bool) -> Void)? { get set }
    func terminate()
    /// Types text into the shell as if the user did (e.g. "ls\n", or "\u{3}" for ⌃C).
    func send(_ text: String)
}
