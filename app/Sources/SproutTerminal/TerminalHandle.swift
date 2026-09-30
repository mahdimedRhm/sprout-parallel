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
    func terminate()
}
