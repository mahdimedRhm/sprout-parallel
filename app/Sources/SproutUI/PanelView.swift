import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

public struct PanelView: View {
    @EnvironmentObject private var store: WorktreeStore
    @FocusState private var focused: Bool
    @EnvironmentObject private var terminals: TerminalSessions
    @AppStorage("sprout.terminalCollapsed") private var terminalCollapsed = false
    @State private var windowBox = WindowBox()

    public static let minimumSize = CGSize(width: 620, height: 400)

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Hairline()
            if store.scriptMissing {
                ScriptMissingView()
            } else {
                HStack(spacing: 0) {
                    ProjectSidebar().frame(width: 170)
                    Hairline(vertical: true)
                    SplitPane {
                        content
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } bottom: {
                        TerminalPane(focusTerminal: { focusTerminal(in: $0) })
                    }
                }
            }
            if let error = store.error {
                ErrorBanner(message: error)
            }
            Hairline()
            FooterBar()
        }
        .frame(
            minWidth: Self.minimumSize.width, maxWidth: .infinity,
            minHeight: Self.minimumSize.height, maxHeight: .infinity)
        .background(Theme.bg)
        .font(Theme.mono())
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(action: handleKey)
        .background { terminalShortcuts }
        .onChange(of: store.mode) { _, mode in
            focused = mode == .list
        }
        .task {
            focused = true
            await store.refresh()
        }
        .background(WindowAccessor(box: windowBox))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Alerts and other windows becoming key aren't ours to react to.
            if let window = windowBox.window, note.object as? NSWindow !== window { return }
            // Coming back to the panel must not steal focus from the terminal.
            if !terminals.terminalHasFocus {
                focused = store.mode == .list
            }
            Task { await store.refresh() }
        }
        .onChange(of: terminals.focusLostCount) { _, _ in
            // The focused terminal closed or its shell exited: AppKit would leave
            // the window itself as first responder, so hand focus on.
            if let path = terminalPath, !terminalCollapsed, terminals.activeTab(for: path) != nil {
                focusTerminal(in: path)
            } else {
                focused = true
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.mode {
        case .list:
            WorktreeListView()
        case .create:
            if let project = store.selectedProject {
                CreateForm(project: project)
            }
        case .delete(let worktree):
            DeleteConfirm(worktree: worktree)
        case .clear(let project):
            ClearConfirm(project: project)
        }
    }

    /// Window-level shortcuts: they fire even while the terminal has focus.
    private var terminalShortcuts: some View {
        ZStack {
            Button("", action: toggleTerminalFocus).keyboardShortcut("`", modifiers: .control)
            Button("", action: newTerminalTab).keyboardShortcut("t", modifiers: .command)
            Button("", action: closeTerminalTab).keyboardShortcut("w", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var terminalPath: String? { store.selectedWorktree?.path }

    private func toggleTerminalFocus() {
        guard let path = terminalPath else { return }
        if let view = terminals.activeTab(for: path)?.view,
           let responder = view.window?.firstResponder as? NSView,
           responder === view || responder.isDescendant(of: view) {
            view.window?.makeFirstResponder(nil)
            focused = true
            return
        }
        terminalCollapsed = false
        terminals.ensureTab(in: path)
        focusTerminal(in: path)
    }

    private func newTerminalTab() {
        guard let path = terminalPath else { return }
        terminalCollapsed = false
        terminals.openTab(in: path)
        focusTerminal(in: path)
    }

    private func closeTerminalTab() {
        guard let path = terminalPath, let tab = terminals.activeTab(for: path) else { return }
        if tab.isBusy {
            let alert = NSAlert()
            alert.messageText = "Close “\(tab.title)”?"
            alert.informativeText = "It's still running. Closing the tab stops it."
            alert.addButton(withTitle: "Close Tab")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        terminals.closeTab(tab.id, in: path)
    }

    private func focusTerminal(in path: String, attempt: Int = 0) {
        // The view is attached to the window on a later layout pass (fresh tab, or
        // expanding from collapsed), so retry for up to ~0.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) {
            guard let view = terminals.activeTab(for: path)?.view else { return }
            if let window = view.window, window.makeFirstResponder(view) { return }
            if attempt < 10 { focusTerminal(in: path, attempt: attempt + 1) }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard store.mode == .list else { return .ignored }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let shift = press.modifiers.contains(.shift)
        let worktree = store.selectedWorktree

        switch press.key {
        case .upArrow:
            shift ? store.moveProject(by: -1) : store.moveWorktree(by: -1)
            return .handled
        case .downArrow:
            shift ? store.moveProject(by: 1) : store.moveWorktree(by: 1)
            return .handled
        case .return:
            if let worktree { Openers.vscode(worktree.path) }
            return .handled
        case .delete:
            store.beginDelete()
            return .handled
        case .escape:
            NSApp.keyWindow?.orderOut(nil)
            return .handled
        default:
            break
        }

        switch press.characters {
        case "t":
            if let worktree { Openers.warp(worktree.path) }
        case "f":
            if let worktree { Openers.finder(worktree.path) }
        case "o":
            if let url = worktree?.herdUrl { Openers.browser(url) }
        case "O":
            if let url = worktree?.serveUrl { Openers.browser(url) }
        case "n":
            store.beginCreate()
        case "X":
            store.beginClear()
        case "r":
            Task { await store.refresh() }
        default:
            return .ignored
        }
        return .handled
    }
}

/// The panel's window, captured once the view is in it.
final class WindowBox {
    weak var window: NSWindow?
}

private struct WindowAccessor: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in box.window = view?.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if box.window == nil { box.window = view.window }
    }
}
