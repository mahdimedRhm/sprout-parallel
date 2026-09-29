import SproutCore
import SwiftUI

struct CreateForm: View {
    @EnvironmentObject private var store: WorktreeStore
    let project: Project

    @State private var branch = ""
    @State private var base = "main"
    @State private var runSetup = true
    @FocusState private var branchFocused: Bool

    private var problem: String? { SproutCLI.validateBranch(branch) }
    private var locked: Bool { store.isBusy || store.operation == .succeeded }
    private var canSubmit: Bool { problem == nil && !locked }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("new worktree · ").foregroundStyle(Theme.muted) + Text(project.name).foregroundStyle(Theme.bright))
                .padding(.bottom, 4)

            KV("branch") {
                TextField("", text: $branch, prompt: Text("feature/…").foregroundStyle(Theme.muted))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.bright)
                    .tint(Theme.green)
                    .focused($branchFocused)
                    .disabled(locked)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.green).frame(height: 1) }
                    .onSubmit(submit)
            }
            KV("from") {
                Picker("", selection: $base) {
                    ForEach(project.branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(locked)
            }
            KV("setup") {
                Button { runSetup.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(runSetup ? "[x]" : "[ ]").foregroundStyle(runSetup ? Theme.green : Theme.muted)
                        Text(".env mysql redis composer npm").foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(locked)
            }
            KV("path") {
                (Text("~/…/\(project.name)-worktrees/").foregroundStyle(Theme.muted)
                    + Text(SproutCLI.folderName(for: branch)).foregroundStyle(Theme.bright))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if !branch.isEmpty, let problem {
                Text("✗ \(problem)").foregroundStyle(Theme.red).font(Theme.mono(11))
            }
            if !store.log.isEmpty {
                LogView().padding(.top, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ActionChip(key: "⌘⏎", label: "create", tint: Theme.green, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
                ActionChip(key: "esc", label: store.operation == .succeeded ? "done" : "back") { store.backToList() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isBusy)
            }
            .font(Theme.mono(11))
        }
        .onAppear {
            base = project.branches.contains("main") ? "main" : (project.branches.first ?? "main")
            branchFocused = true
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await store.create(branch: branch, base: base, runSetup: runSetup) }
    }
}
