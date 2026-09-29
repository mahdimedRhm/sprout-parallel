import AppKit
import SproutCore
import SwiftUI

public struct PanelView: View {
    @EnvironmentObject private var store: WorktreeStore
    @FocusState private var focused: Bool

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
                    content
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onChange(of: store.mode) { _, mode in
            focused = mode == .list
        }
        .task {
            focused = true
            await store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focused = store.mode == .list
            Task { await store.refresh() }
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
        case "n":
            store.beginCreate()
        case "r":
            Task { await store.refresh() }
        default:
            return .ignored
        }
        return .handled
    }
}
