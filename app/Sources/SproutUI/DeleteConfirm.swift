import SproutCore
import SproutTerminal
import SwiftUI

struct DeleteConfirm: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    let worktree: Worktree

    @State private var force = false
    @State private var dropData = true

    private var locked: Bool { store.isBusy || store.operation == .succeeded }
    private var canDelete: Bool { (!worktree.isDirty || force) && !locked }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("delete ").foregroundStyle(Theme.red)
                + Text(worktree.branch).foregroundStyle(Theme.bright)
                + Text(" ?").foregroundStyle(Theme.red))
                .padding(.bottom, 4)
            if worktree.isDirty {
                Text("⚠ \(worktree.changes) uncommitted change\(worktree.changes == 1 ? "" : "s") — will be lost")
                    .foregroundStyle(Theme.amber)
            }
            CheckRow(on: $force, label: "discard uncommitted changes",
                     note: worktree.isDirty ? "--force · required" : "--force", tint: Theme.red)
                .disabled(locked)
            CheckRow(on: $dropData, label: "drop mysql db & clear redis keys",
                     note: "off = --keep-db", tint: Theme.green)
                .disabled(locked)
            Text("branch \(worktree.branch) is kept").foregroundStyle(Theme.muted).font(Theme.mono(11))
            if !store.log.isEmpty {
                LogView().padding(.top, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ActionChip(key: "⌘⏎", label: "delete", tint: Theme.red, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canDelete)
                    .opacity(canDelete ? 1 : 0.4)
                ActionChip(key: "esc", label: store.operation == .succeeded ? "done" : "back") { store.backToList() }
                    // While the terminal has focus, esc belongs to the shell.
                    .keyboardShortcut(terminals.terminalHasFocus ? nil : .cancelAction)
                    .disabled(store.isBusy)
            }
            .font(Theme.mono(11))
        }
    }

    private func submit() {
        guard canDelete else { return }
        Task { await store.delete(worktree, force: force, dropData: dropData) }
    }
}

struct CheckRow: View {
    @Binding var on: Bool
    let label: String
    let note: String
    let tint: Color

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 6) {
                Text(on ? "[x]" : "[ ]").foregroundStyle(on ? tint : Theme.muted)
                Text(label).foregroundStyle(Theme.text)
                Text(note).foregroundStyle(Theme.muted).font(Theme.mono(11))
            }
        }
        .buttonStyle(.plain)
    }
}
