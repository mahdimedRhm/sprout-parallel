import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

/// One command-palette entry. `unavailable` holds the reason it can't run now.
struct PaletteAction: Identifiable {
    let title: String
    var unavailable: String?
    let run: () -> Void
    var id: String { title }
}

/// Every action for the selected worktree, in catalog order, with availability.
@MainActor
func paletteCatalog(store: WorktreeStore, terminals: TerminalSessions, showTerminal: @escaping () -> Void) -> [PaletteAction] {
    let worktree = store.selectedWorktree
    let path = worktree?.path
    let noWorktree = worktree == nil ? "no worktree selected" : nil
    let busy = store.isBusy ? "busy: \(store.activity?.runningTitle ?? "an operation is running")" : nil

    func service(_ service: Service, command: @escaping (String) -> String) -> [PaletteAction] {
        let running = path.map { terminals.isServiceRunning(service, in: $0) } ?? false
        let name = service.rawValue
        return [
            PaletteAction(title: "\(name): start", unavailable: noWorktree ?? (running ? "already running" : nil)) {
                guard let path else { return }
                terminals.startService(service, command: command(path), in: path)
                showTerminal()
            },
            PaletteAction(title: "\(name): restart", unavailable: noWorktree ?? (running ? nil : "not running")) {
                guard let path else { return }
                Task { await terminals.restartService(service, command: command(path), in: path) }
                showTerminal()
            },
            PaletteAction(title: "\(name): stop", unavailable: noWorktree ?? (running ? nil : "not running")) {
                guard let path else { return }
                Task { await terminals.stopService(service, in: path) }
            },
        ]
    }

    func database(_ action: DatabaseAction, title: String, confirm: (String, String)?) -> PaletteAction {
        PaletteAction(title: title, unavailable: noWorktree ?? busy) {
            guard let worktree else { return }
            if let confirm, !confirmAction(confirm.0, confirm.1) { return }
            Task { await store.database(action, worktree: worktree) }
        }
    }

    let branch = worktree?.branch ?? ""
    return service(.serve) { _ in ServiceCommand.serve }
        + service(.queue) { ServiceCommand.queue(worktreePath: $0) }
        + [
            database(.create, title: "db: create from main", confirm: nil),
            database(.refresh, title: "db: refresh from main",
                     confirm: ("Refresh the database of \(branch)?",
                               "It's replaced with a fresh copy of the main project's database.")),
            database(.drop, title: "db: drop",
                     confirm: ("Drop the database of \(branch)?", "Its data is lost.")),
            PaletteAction(title: "db: migrate:fresh --seed", unavailable: noWorktree) {
                guard let path,
                      confirmAction("Rebuild the database of \(branch) from migrations?", "All its data is lost."),
                      let tab = terminals.openTab(in: path) else { return }
                tab.send("php artisan migrate:fresh --seed\n")
                showTerminal()
            },
            PaletteAction(title: "open: VS Code", unavailable: noWorktree) { if let path { Openers.vscode(path) } },
            PaletteAction(title: "open: Warp", unavailable: noWorktree) { if let path { Openers.warp(path) } },
            PaletteAction(title: "open: Finder", unavailable: noWorktree) { if let path { Openers.finder(path) } },
            PaletteAction(title: "open: Herd URL", unavailable: noWorktree ?? (worktree?.herdUrl == nil ? "no Herd site" : nil)) {
                if let url = worktree?.herdUrl { Openers.browser(url) }
            },
            PaletteAction(title: "open: serve URL", unavailable: noWorktree ?? (worktree?.serveUrl == nil ? "no serve port" : nil)) {
                if let url = worktree?.serveUrl { Openers.browser(url) }
            },
            PaletteAction(title: "worktree: new", unavailable: store.selectedProject == nil ? "no project selected" : busy) {
                store.beginCreate()
            },
            PaletteAction(title: "worktree: delete", unavailable: noWorktree ?? busy) { store.beginDelete() },
            PaletteAction(title: "worktree: clear all in project",
                          unavailable: (store.selectedProject?.worktrees.isEmpty ?? true) ? "no worktrees" : busy) {
                store.beginClear()
            },
            PaletteAction(title: "refresh") { Task { await store.refresh() } },
        ]
}

@MainActor
private func confirmAction(_ message: String, _ detail: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

/// The ⌘⇧P overlay. Keys (↑ ↓ ⏎ esc) are handled by PanelView's key monitor.
struct CommandPalette: View {
    @EnvironmentObject private var store: WorktreeStore
    let actions: [PaletteAction]
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { store.palette = nil }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("❯").foregroundStyle(Theme.green)
                    TextField("", text: Binding(get: { store.palette ?? "" }, set: { if store.palette != nil { store.palette = $0 } }),
                              prompt: Text("run an action…").foregroundStyle(Theme.muted))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.bright)
                        .tint(Theme.green)
                        .focused($fieldFocused)
                }
                .padding(10)
                Hairline()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                row(action, selected: index == store.paletteSelection)
                                    .id(index)
                                    .onTapGesture {
                                        store.paletteSelection = index
                                        guard action.unavailable == nil else { return }
                                        store.palette = nil
                                        action.run()
                                    }
                            }
                            if actions.isEmpty {
                                Text("no matching action").foregroundStyle(Theme.muted).padding(10)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: store.paletteSelection) { _, index in proxy.scrollTo(index) }
                }
            }
            .frame(width: 480)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bar))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .padding(.top, 60)
        }
        .onAppear { fieldFocused = true }
    }

    private func row(_ action: PaletteAction, selected: Bool) -> some View {
        HStack {
            Text(action.title).foregroundStyle(action.unavailable == nil ? Theme.bright : Theme.muted)
            Spacer()
            if let reason = action.unavailable {
                Text(reason).foregroundStyle(Theme.muted).font(Theme.mono(11))
            } else if selected {
                KeyHint(key: "⏎", label: "run", tint: Theme.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Theme.selection : Color.clear)
        .contentShape(Rectangle())
    }
}
