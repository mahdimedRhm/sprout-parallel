import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

/// The selected worktree's terminal tabs, below the worktree info.
struct TerminalPane: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    @AppStorage("sprout.terminalCollapsed") private var collapsed = false
    /// Moves keyboard focus into the worktree's terminal.
    let focusTerminal: (String) -> Void

    private var path: String? { store.selectedWorktree?.path }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if !collapsed {
                Hairline()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.logBg)
        .onAppear(perform: openIfNeeded)
        .onChange(of: store.selectedWorktreePath) { _, _ in openIfNeeded() }
        .onChange(of: collapsed) { _, _ in openIfNeeded() }
    }

    private func openIfNeeded() {
        guard !collapsed, let path else { return }
        terminals.ensureTab(in: path)
    }

    private var tabBar: some View {
        // Titles and busy dots follow what's running, so re-read them every second.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 2) {
                if let path {
                    ForEach(terminals.tabs(for: path), id: \.id) { tab in
                        TerminalTabButton(
                            title: tab.title, busy: tab.isBusy,
                            active: terminals.activeTab(for: path)?.id == tab.id
                        ) {
                            terminals.activate(tab.id, in: path)
                            collapsed = false
                            focusTerminal(path)
                        }
                    }
                    Button {
                        terminals.openTab(in: path)
                        collapsed = false
                        focusTerminal(path)
                    } label: {
                        Text("＋").foregroundStyle(Theme.muted).padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                    .help("new tab (⌘T)")
                } else {
                    Text("terminal").foregroundStyle(Theme.muted).padding(.horizontal, 10)
                }
                Spacer()
                Button { collapsed.toggle() } label: {
                    Text(collapsed ? "▴ show" : "▾ hide").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
            .frame(height: SplitPane<EmptyView, EmptyView>.collapsedHeight - 1)
        }
        .font(Theme.mono(11))
        .background(Theme.bar)
    }

    @ViewBuilder private var content: some View {
        if let path {
            if let tab = terminals.activeTab(for: path) {
                if let view = tab.view {
                    TerminalHost(view: view).id(tab.id).padding(6)
                } else {
                    placeholder("terminal · \(tab.title)")
                }
            } else if terminals.failedPaths.contains(path) {
                placeholder("✗ could not start shell · ⌘T to retry", color: Theme.red)
            } else {
                placeholder("no terminal · ⌘T to open")
            }
        } else {
            placeholder("select a worktree to open its terminal")
        }
    }

    private func placeholder(_ text: String, color: Color = Theme.muted) -> some View {
        Text(text).foregroundStyle(color).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalTabButton: View {
    let title: String
    let busy: Bool
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy { Text("●").foregroundStyle(Theme.green) }
                Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180).fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(active ? Theme.bright : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Theme.logBg : Color.clear)
            .overlay(alignment: .top) {
                if active { Rectangle().fill(Theme.green).frame(height: 2) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Hosts a terminal's AppKit view. The view outlives this wrapper, so it's
/// re-parented (not recreated) when tabs or worktrees switch.
struct TerminalHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
