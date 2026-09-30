import AppKit
import SproutCore
import SwiftUI

struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Label/value row used in detail boxes and forms.
struct KV<Content: View>: View {
    let key: String
    let content: Content

    init(_ key: String, @ViewBuilder content: () -> Content) {
        self.key = key
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(key).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct KeyHint: View {
    let key: String
    let label: String
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(tint))
            Text(label).foregroundStyle(Theme.muted)
        }
    }
}

/// A clickable key hint. Callers attach `.keyboardShortcut` where one applies.
struct ActionChip: View {
    let key: String
    let label: String
    var tint: Color = Theme.muted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyHint(key: key, label: label, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

struct HeaderBar: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        HStack(spacing: 6) {
            Text("❯").foregroundStyle(Theme.green)
            Text("sprout").foregroundStyle(Theme.bright).fontWeight(.semibold)
            Text(rootLabel).foregroundStyle(Theme.muted)
            ActivityChip()
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(statusLabel(now: context.date)).foregroundStyle(Theme.muted)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Text(store.isRefreshing ? "◌" : "⟳").foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
            .help("refresh (r)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bar)
    }

    private var rootLabel: String {
        guard let path = store.projects.first?.path else { return "" }
        let root = (path as NSString).deletingLastPathComponent
        return (root as NSString).abbreviatingWithTildeInPath
    }

    private func statusLabel(now: Date) -> String {
        let count = "\(store.worktreeCount) wt"
        guard let last = store.lastRefresh else { return count }
        return "\(count) · refreshed \(max(0, Int(now.timeIntervalSince(last))))s ago"
    }
}

struct ProjectSidebar: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("PROJECTS")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                ForEach(store.projects) { project in
                    row(project).id(project.name)
                }
            }
        }
        .onChange(of: store.selectedProjectName) { _, name in
            if let name { proxy.scrollTo(name) }
        }
        }
        .background(Theme.sidebar)
    }

    private func row(_ project: Project) -> some View {
        let selected = project.name == store.selectedProjectName
        return HStack {
            Text(project.name)
                .foregroundStyle(selected ? Theme.bright : (project.worktrees.isEmpty ? Theme.muted : Theme.text))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(selected && store.isBusy ? "◌" : "[\(project.worktrees.count)]")
                .foregroundStyle(selected && store.isBusy ? Theme.green : Theme.muted)
        }
        .padding(.leading, selected ? 10 : 12)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(selected ? Theme.selection : Color.clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Theme.green).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Allowed while an operation runs in the background too.
            if store.mode == .list || store.isBusy {
                store.backToList()
                store.selectProject(project.name)
            }
        }
    }
}

struct FooterBar: View {
    @EnvironmentObject private var store: WorktreeStore

    private struct Hint: Hashable {
        let key: String
        let label: String
        var primary = false
    }

    var body: some View {
        HStack(spacing: 12) {
            // Full hint list when it fits, otherwise the short one; never wraps.
            ViewThatFits(in: .horizontal) {
                hintRow(hints)
                hintRow(shortHints)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LoginItemToggle().lineLimit(1).fixedSize()
            Button("close") { NSApp.keyWindow?.orderOut(nil) }
                .buttonStyle(.plain).lineLimit(1).fixedSize()
                .foregroundStyle(Theme.muted)
                .keyboardShortcut("w")
            Button("quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).lineLimit(1).fixedSize()
                .foregroundStyle(Theme.muted)
                .keyboardShortcut("q")
        }
        .font(Theme.mono(11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.bar)
    }

    private func hintRow(_ hints: [Hint]) -> some View {
        HStack(spacing: 12) {
            ForEach(hints, id: \.self) { hint in
                KeyHint(key: hint.key, label: hint.label, tint: hint.primary ? Theme.green : Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Lower-priority hints dropped, for narrow windows.
    private var shortHints: [Hint] {
        guard store.mode == .list else { return hints }
        return [Hint(key: "⏎", label: "code", primary: true), Hint(key: "⌃`", label: "terminal"),
                Hint(key: "?", label: "keys", primary: true)]
    }

    private var hints: [Hint] {
        switch store.mode {
        case .list:
            [Hint(key: "⏎", label: "code", primary: true), Hint(key: "←→↑↓", label: "move"),
             Hint(key: "n", label: "new"), Hint(key: "⌃`", label: "terminal"),
             Hint(key: "⌘T", label: "tab"), Hint(key: "?", label: "keys", primary: true)]
        case .create:
            [Hint(key: "⌘⏎", label: "create", primary: true), Hint(key: "esc", label: "back")]
        case .delete:
            [Hint(key: "⌘⏎", label: "delete", primary: true), Hint(key: "esc", label: "back")]
        case .clear:
            [Hint(key: "⌘⏎", label: "clear all", primary: true), Hint(key: "esc", label: "back")]
        case .activity:
            [Hint(key: "esc", label: "back", primary: true)]
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Text("✗").foregroundStyle(Theme.red)
            Text(message).foregroundStyle(Theme.red).lineLimit(2)
            Spacer()
        }
        .font(Theme.mono(11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.red.opacity(0.08))
    }
}

struct ScriptMissingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("✗ sprout-parallel not found on your shell PATH (~/.zshrc)").foregroundStyle(Theme.red)
            (Text("$ ").foregroundStyle(Theme.green) + Text("bash install.sh").foregroundStyle(Theme.bright))
            Text("then reopen this panel").foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The running or last create/delete/clear, in the header. Click (or `l`) for its log.
struct ActivityChip: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        if let activity = store.activity {
            Button { store.showActivity() } label: {
                HStack(spacing: 4) {
                    switch store.operation {
                    case .running:
                        BlinkingText(text: "◌ \(activity.runningTitle)…", color: Theme.green)
                    case .succeeded:
                        Text("✓ \(activity.doneTitle)").foregroundStyle(Theme.green)
                    case .failed:
                        Text("✗ \(activity.failedTitle)").foregroundStyle(Theme.red)
                    case .idle:
                        EmptyView()
                    }
                    KeyHint(key: "l", label: "log")
                }
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .help("show the log")
        }
    }
}

/// The running or last operation's live log, reopened from the header.
struct ActivityView: View {
    @EnvironmentObject private var store: WorktreeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(Theme.bright).padding(.bottom, 4)
            LogView()
            Spacer(minLength: 0)
            ActionChip(key: "esc", label: "back") { store.backToList() }
                .font(Theme.mono(11))
        }
    }

    private var title: String {
        guard let activity = store.activity else { return "" }
        switch store.operation {
        case .running: return activity.runningTitle
        case .failed: return activity.failedTitle
        default: return activity.doneTitle
        }
    }
}
