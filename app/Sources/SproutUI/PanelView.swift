import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

public struct PanelView: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    @AppStorage("sprout.terminalCollapsed") private var terminalCollapsed = false
    @State private var windowBox = WindowBox()
    @State private var keyMonitor = KeyMonitor()
    @State private var paletteFromTerminal = false

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
        .background { terminalShortcuts }
        .overlay { if store.showingKeys { KeyCheatSheet() } }
        .overlay { if store.palette != nil { CommandPalette(actions: paletteActions, onClose: closePalette, onRun: runPaletteAction) } }
        .onAppear { keyMonitor.install(handleListKey) }
        .onDisappear { keyMonitor.remove() }
        .task { await store.refresh() }
        .background(WindowAccessor(box: windowBox))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Alerts and other windows becoming key aren't ours to react to.
            if let window = windowBox.window, note.object as? NSWindow !== window { return }
            Task { await store.refresh() }
        }
        .onChange(of: terminals.focusLostCount) { _, _ in
            // The focused terminal closed or its shell exited: AppKit would leave
            // the window itself as first responder, so hand focus on.
            if let path = terminalPath, !terminalCollapsed, terminals.activeTab(for: path) != nil {
                focusTerminal(in: path)
            } else {
                focusList()
            }
        }
        .onChange(of: terminalCollapsed) { _, collapsed in
            // Collapsing removes a focused terminal from the window; hand keys to the list.
            guard collapsed else { return }
            DispatchQueue.main.async {
                if let window = windowBox.window, window.firstResponder === window { focusList() }
            }
        }
    }

    /// Hands the keyboard back to the list: takes first responder away from any
    /// terminal so `handleListKey` sees the keys again.
    private func focusList() {
        if let window = windowBox.window, let host = window.contentView {
            window.makeFirstResponder(host)
        }
    }

    private var paletteActions: [PaletteAction] {
        let all = paletteCatalog(store: store, terminals: terminals) { terminalCollapsed = false }
        return PaletteMatcher.order(all, query: store.palette ?? "", title: { $0.title })
    }

    private func openPalette(_ query: String) {
        guard store.palette == nil else { return }
        paletteFromTerminal = terminals.terminalHasFocus
        store.palette = query
    }

    /// Closes the palette and puts the keyboard back where it was.
    private func closePalette() {
        store.palette = nil
        restorePaletteFocus()
    }

    private func restorePaletteFocus() {
        if paletteFromTerminal, let path = terminalPath {
            focusTerminal(in: path)
        } else {
            focusList()
        }
    }

    /// Runs an action, then restores focus only if we're still on the list;
    /// a form the action opened keeps the keyboard.
    private func runPaletteAction(_ action: PaletteAction) {
        store.palette = nil
        action.run()
        if store.mode == .list { restorePaletteFocus() }
    }

    /// ↑ ↓ ⏎ esc while the palette is open; other keys go to its search field.
    private func handlePaletteKey(_ event: NSEvent) -> Bool {
        let actions = paletteActions
        switch event.keyCode {
        case 53:  // esc
            closePalette()
        case 125:  // ↓
            store.paletteSelection = min(store.paletteSelection + 1, max(actions.count - 1, 0))
        case 126:  // ↑
            store.paletteSelection = max(store.paletteSelection - 1, 0)
        case 36, 76:  // ⏎
            guard actions.indices.contains(store.paletteSelection) else { return true }
            let action = actions[store.paletteSelection]
            guard action.unavailable == nil else { return true }
            runPaletteAction(action)
        default:
            return false
        }
        return true
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
        case .activity:
            ActivityView()
        }
    }

    /// Window-level shortcuts: they fire even while the terminal has focus.
    private var terminalShortcuts: some View {
        ZStack {
            Button("", action: toggleTerminalFocus).keyboardShortcut("`", modifiers: .control)
            Button("", action: newTerminalTab).keyboardShortcut("t", modifiers: .command)
            // SwiftUI matches shifted shortcuts by the shifted character: ⌘⇧W is "W", ⌘⇧[ is "{".
            Button("", action: closeTerminalTab).keyboardShortcut("W", modifiers: [.command, .shift])
            Button("") { switchTab(by: -1) }.keyboardShortcut("{", modifiers: [.command, .shift])
            Button("") { switchTab(by: 1) }.keyboardShortcut("}", modifiers: [.command, .shift])
            ForEach(1..<10) { number in
                Button("") { jumpToTab(number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Button("") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: .command)
            Button("", action: { openPalette("") }).keyboardShortcut("P", modifiers: [.command, .shift])
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
            focusList()
            return
        }
        terminalCollapsed = false
        terminals.ensureTab(in: path)
        focusTerminal(in: path)
    }

    private func switchTab(by offset: Int) {
        guard let path = terminalPath else { return }
        terminals.activateNeighbour(of: path, by: offset)
        focusTerminal(in: path)
    }

    private func jumpToTab(_ index: Int) {
        guard let path = terminalPath, terminals.tabs(for: path).indices.contains(index) else { return }
        terminals.activateTab(at: index, in: path)
        focusTerminal(in: path)
    }

    private func newTerminalTab() {
        guard let path = terminalPath else { return }
        terminalCollapsed = false
        terminals.openTab(in: path)
        focusTerminal(in: path)
    }

    private func closeTerminalTab() {
        guard let path = terminalPath, let tab = terminals.activeTab(for: path),
              confirmClosingTab(tab) else { return }
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

    /// List shortcuts, read straight from AppKit key events. (SwiftUI's
    /// focus-based `onKeyPress` also saw keys meant for the terminal and
    /// re-took first responder from it.) Returns true when the key was used.
    private func handleListKey(_ event: NSEvent) -> Bool {
        guard let window = windowBox.window, event.window === window else { return false }
        if store.palette != nil { return handlePaletteKey(event) }
        guard !terminals.terminalHasFocus else { return false }   // keys belong to the shell

        // Away from the list: the activity log, or a form whose operation is
        // running in the background (its inputs are locked). Moving around or
        // esc returns to the list; the operation keeps going.
        if store.mode != .list {
            guard store.mode == .activity || store.isBusy else { return false }   // an editable form
            let navigation: Set<UInt16> = [123, 124, 125, 126]
            if event.keyCode == 53 {
                store.backToList()
                return true
            }
            guard navigation.contains(event.keyCode) else { return false }
            store.backToList()
        }
        guard !(window.firstResponder is NSText) else { return false }   // a text field is being edited
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        let shift = modifiers.contains(.shift)
        let worktree = store.selectedWorktree

        if store.showingKeys, event.keyCode == 53 || event.characters == "?" {
            store.showingKeys = false
            return true
        }

        switch event.keyCode {
        case 123:  // ←
            store.moveProject(by: -1)
            return true
        case 124:  // →
            store.moveProject(by: 1)
            return true
        case 126:  // ↑
            shift ? store.moveProject(by: -1) : store.moveWorktree(by: -1)
            return true
        case 125:  // ↓
            shift ? store.moveProject(by: 1) : store.moveWorktree(by: 1)
            return true
        case 36, 76:  // return, enter
            if let worktree { Openers.vscode(worktree.path) }
            return true
        case 51:  // backspace
            store.beginDelete()
            return true
        case 53:  // esc
            window.orderOut(nil)
            return true
        default:
            break
        }

        switch event.characters {
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
        case "?":
            store.showingKeys = true
        case "l":
            store.showActivity()
        case "s":
            openPalette("serve ")
        case "q":
            openPalette("queue ")
        case "d":
            openPalette("db ")
        default:
            return false
        }
        return true
    }
}

/// Owns a local key-down monitor for the panel.
final class KeyMonitor {
    private var token: Any?

    @MainActor
    func install(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handler(event) } ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// The panel's window, captured once the view is in it.
final class WindowBox {
    weak var window: NSWindow?
}

private struct WindowAccessor: NSViewRepresentable {
    let box: WindowBox

    func makeNSView(context: Context) -> NSView {
        WindowTrackingView(box: box)
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// Records its window whenever it joins one — not once on a timer, which could
/// run before the view is in the window and leave the box empty for good.
private final class WindowTrackingView: NSView {
    private let box: WindowBox

    init(box: WindowBox) {
        self.box = box
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { box.window = window }
    }
}
