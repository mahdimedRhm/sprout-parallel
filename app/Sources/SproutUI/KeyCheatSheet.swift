import SproutCore
import SwiftUI

/// Every Sprout shortcut, shown over the panel with `?`.
struct KeyCheatSheet: View {
    @EnvironmentObject private var store: WorktreeStore

    private struct Section: Identifiable {
        let title: String
        let keys: [(key: String, label: String)]
        var id: String { title }
    }

    private let left = [
        Section(title: "WORKTREES", keys: [
            ("← →", "previous / next project"),
            ("↑ ↓", "previous / next worktree"),
            ("⏎", "open in VS Code"),
            ("t", "open in Warp"),
            ("f", "reveal in Finder"),
            ("o", "open the Herd URL"),
            ("⇧O", "open the serve URL"),
            ("n", "new worktree"),
            ("⌫", "delete worktree"),
            ("⇧X", "clear all worktrees of the project"),
            ("r  ⌘R", "refresh"),
            ("l", "log of the running / last operation"),
            ("⌘⇧P", "command palette"),
            ("s  q  d", "serve / queue / database actions"),
        ]),
    ]

    private let right = [
        Section(title: "TERMINAL", keys: [
            ("⌃`", "focus list ⇄ terminal"),
            ("⌘T", "new tab"),
            ("⌘⇧W  ×", "close tab"),
            ("⌘⇧[  ⌘⇧]", "previous / next tab"),
            ("⌘1 … ⌘9", "go to tab"),
        ]),
        Section(title: "FORMS", keys: [
            ("⌘⏎", "confirm"),
            ("esc", "back"),
        ]),
        Section(title: "WINDOW", keys: [
            ("?", "this sheet"),
            ("esc  ⌘W", "hide window"),
            ("⌘Q", "quit"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { store.showingKeys = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("keyboard").foregroundStyle(Theme.bright).fontWeight(.semibold)
                    Spacer()
                    Button { store.showingKeys = false } label: {
                        KeyHint(key: "esc", label: "close")
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .top, spacing: 28) {
                    column(left)
                    column(right)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bar))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .fixedSize()
        }
    }

    private func column(_ sections: [Section]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    ForEach(section.keys, id: \.key) { entry in
                        HStack(spacing: 10) {
                            Text(entry.key)
                                .foregroundStyle(Theme.green)
                                .frame(width: 96, alignment: .leading)
                            Text(entry.label).foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        }
    }
}
