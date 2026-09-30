import AppKit
import Combine
import SproutCore
import SproutTerminal
import SproutUI
import SwiftUI

@main
struct SproutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The UI lives in a free-floating window owned by AppDelegate.
        Settings { EmptyView() }
    }
}

/// Owns the menu bar leaf and the free-floating panel window it toggles.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let frameName = "SproutPanel"

    private let store = WorktreeStore(cli: SproutCLI(shell: LoginShell()))
    private let terminals = TerminalSessions { ShellTerminal(directory: $0) }
    private var projectsWatch: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Sprout")
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        statusItem = item

        // Close the terminals of worktrees that no longer exist (deleted, cleared, removed elsewhere).
        projectsWatch = store.$projects.dropFirst().sink { [weak self] projects in
            MainActor.assumeIsolated {
                self?.terminals.prune(keeping: Set(projects.flatMap { $0.worktrees.map(\.path) }))
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let busy = terminals.busyTabs()
        if !busy.isEmpty {
            let alert = NSAlert()
            alert.messageText = busy.count == 1
                ? "1 terminal is still running"
                : "\(busy.count) terminals are still running"
            alert.informativeText = busy.map(\.label).joined(separator: "\n") + "\n\nQuitting Sprout stops them."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        terminals.terminateAll()
        return .terminateNow
    }

    /// `open -a Sprout` (or Spotlight) while running shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    private func showWindow() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleWindow() {
        let window = self.window ?? makeWindow()
        self.window = window
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PanelView.minimumSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0x0B / 255, green: 0x0F / 255, blue: 0x14 / 255, alpha: 1)
        window.contentMinSize = PanelView.minimumSize

        let hosting = NSHostingView(
            rootView: PanelView().environmentObject(store).environmentObject(terminals))
        hosting.sizingOptions = []
        window.contentView = hosting

        if !window.setFrameUsingName(Self.frameName) {
            window.setFrame(Self.defaultFrame(), display: false)
        }
        window.setFrameAutosaveName(Self.frameName)
        return window
    }

    /// First-open placement: half the width and the full usable height of the
    /// screen under the mouse, centred horizontally.
    private static func defaultFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return NSRect(origin: .zero, size: PanelView.minimumSize)
        }
        let width = max(PanelView.minimumSize.width, (visible.width / 2).rounded())
        let height = max(PanelView.minimumSize.height, visible.height - 24)
        return NSRect(x: visible.midX - width / 2, y: visible.minY + 12, width: width, height: height)
    }
}
