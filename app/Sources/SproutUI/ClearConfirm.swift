import SproutCore
import SproutTerminal
import SwiftUI

/// Confirmation pane for deleting every worktree of a project.
struct ClearConfirm: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    let project: Project

    @State private var force = false
    @State private var dropData = true

    private var locked: Bool { store.isBusy || store.operation == .succeeded }
    private var dirtyCount: Int { project.worktrees.filter(\.isDirty).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("clear all ").foregroundStyle(Theme.red)
                + Text("\(project.worktrees.count)").foregroundStyle(Theme.bright)
                + Text(" worktrees in ").foregroundStyle(Theme.red)
                + Text(project.name).foregroundStyle(Theme.bright)
                + Text(" ?").foregroundStyle(Theme.red))
                .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(project.worktrees) { worktree in
                        HStack(spacing: 8) {
                            Text("●").foregroundStyle(worktree.isDirty ? Theme.amber : Theme.green)
                            Text(worktree.branch).foregroundStyle(Theme.text).lineLimit(1)
                            if worktree.isDirty {
                                Text("\(worktree.changes) uncommitted").foregroundStyle(Theme.amber)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)

            if dirtyCount > 0 {
                Text(force
                     ? "⚠ \(dirtyCount) with uncommitted changes — changes will be lost"
                     : "⚠ \(dirtyCount) with uncommitted changes will be skipped")
                    .foregroundStyle(force ? Theme.red : Theme.amber)
            }
            CheckRow(on: $force, label: "discard uncommitted changes",
                     note: "--force · otherwise dirty ones are skipped", tint: Theme.red)
                .disabled(locked)
            CheckRow(on: $dropData, label: "drop mysql dbs & clear redis keys",
                     note: "off = --keep-db", tint: Theme.green)
                .disabled(locked)
            Text("branches are kept").foregroundStyle(Theme.muted).font(Theme.mono(11))
            if !store.log.isEmpty {
                LogView().padding(.top, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ActionChip(key: "⌘⏎", label: "clear all", tint: Theme.red, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(locked)
                    .opacity(locked ? 0.4 : 1)
                ActionChip(key: "esc", label: store.operation == .succeeded ? "done" : "back") { store.backToList() }
                    // While the terminal has focus, esc belongs to the shell.
                    .keyboardShortcut(terminals.terminalHasFocus ? nil : .cancelAction)
                    .disabled(store.isBusy)
            }
            .font(Theme.mono(11))
        }
    }

    private func submit() {
        guard !locked else { return }
        Task { await store.clear(project, force: force, dropData: dropData) }
    }
}
