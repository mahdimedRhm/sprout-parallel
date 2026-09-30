import Foundation

/// Terminal tabs per worktree path, and which one is active.
@MainActor
public final class TerminalSessions: ObservableObject {
    /// Starts a shell in the directory, or returns nil if it can't.
    public typealias Factory = (_ directory: String) -> (any TerminalHandle)?

    public struct BusyTab: Equatable {
        public let path: String
        public let title: String

        public init(path: String, title: String) {
            self.path = path
            self.title = title
        }

        /// "<title> — <project>/<folder>" for a path like ".../<project>-worktrees/<folder>".
        public var label: String {
            let url = URL(fileURLWithPath: path)
            var project = url.deletingLastPathComponent().lastPathComponent
            if project.hasSuffix("-worktrees") { project.removeLast("-worktrees".count) }
            return "\(title) — \(project)/\(url.lastPathComponent)"
        }
    }

    @Published public private(set) var tabsByPath: [String: [any TerminalHandle]] = [:]
    @Published public private(set) var activeByPath: [String: UUID] = [:]
    @Published public private(set) var failedPaths: Set<String> = []

    /// True while a terminal view is the window's first responder.
    @Published public private(set) var terminalHasFocus = false
    /// Bumped when the focused tab goes away (closed, exited, pruned), so the
    /// UI can hand focus to another tab or back to the list.
    @Published public private(set) var focusLostCount = 0
    private var focusedTabID: UUID?

    private let factory: Factory
    /// Worktrees whose terminal has been opened at least once.
    private var startedPaths: Set<String> = []

    public init(factory: @escaping Factory) {
        self.factory = factory
    }

    public func tabs(for path: String) -> [any TerminalHandle] {
        tabsByPath[path] ?? []
    }

    public func activeTab(for path: String) -> (any TerminalHandle)? {
        let tabs = tabs(for: path)
        return tabs.first { $0.id == activeByPath[path] } ?? tabs.last
    }

    /// Opens the first tab the first time a worktree's terminal is shown. Once
    /// the user has closed all of its tabs it stays closed until `openTab`.
    public func ensureTab(in path: String) {
        guard !startedPaths.contains(path) else { return }
        openTab(in: path)
    }

    @discardableResult
    public func openTab(in path: String) -> (any TerminalHandle)? {
        startedPaths.insert(path)
        guard let handle = factory(path) else {
            failedPaths.insert(path)
            return nil
        }
        failedPaths.remove(path)
        let id = handle.id
        handle.onExit = { [weak self] in self?.remove(id, in: path) }
        handle.onFocusChange = { [weak self] focused in self?.focusChanged(id, focused) }
        tabsByPath[path, default: []].append(handle)
        activeByPath[path] = id
        return handle
    }

    /// A terminal reports that it gained or lost first responder.
    public func focusChanged(_ id: UUID, _ focused: Bool) {
        if focused {
            focusedTabID = id
        } else if focusedTabID == id {
            focusedTabID = nil
        }
        terminalHasFocus = focusedTabID != nil
    }

    public func activate(_ id: UUID, in path: String) {
        guard tabs(for: path).contains(where: { $0.id == id }) else { return }
        activeByPath[path] = id
    }

    /// Activates the tab `offset` places from the active one, wrapping around.
    public func activateNeighbour(of path: String, by offset: Int) {
        let tabs = tabs(for: path)
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == activeTab(for: path)?.id } ?? 0
        let target = ((current + offset) % tabs.count + tabs.count) % tabs.count
        activeByPath[path] = tabs[target].id
    }

    /// Activates the tab at `index` (0-based); ignored past the last tab.
    public func activateTab(at index: Int, in path: String) {
        let tabs = tabs(for: path)
        guard tabs.indices.contains(index) else { return }
        activeByPath[path] = tabs[index].id
    }

    public func closeTab(_ id: UUID, in path: String) {
        tabs(for: path).first { $0.id == id }?.terminate()
        remove(id, in: path)
    }

    /// Terminates and forgets the tabs of every worktree not in `paths`.
    public func prune(keeping paths: Set<String>) {
        for path in Array(tabsByPath.keys) where !paths.contains(path) {
            tabs(for: path).forEach { $0.terminate() }
            tabsByPath[path] = nil
            activeByPath[path] = nil
        }
        startedPaths.formIntersection(paths)
        failedPaths.formIntersection(paths)
        reconcileFocus()
    }

    public func busyTabs() -> [BusyTab] {
        tabsByPath.keys.sorted().flatMap { path in
            tabs(for: path).filter { $0.isBusy }.map { BusyTab(path: path, title: $0.title) }
        }
    }

    public func terminateAll() {
        tabsByPath.values.flatMap { $0 }.forEach { $0.terminate() }
        tabsByPath = [:]
        activeByPath = [:]
        reconcileFocus()
    }

    private func remove(_ id: UUID, in path: String) {
        var tabs = tabs(for: path)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        tabsByPath[path] = tabs.isEmpty ? nil : tabs
        if activeByPath[path] == id {
            activeByPath[path] = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        reconcileFocus()
    }

    /// If the focused tab no longer exists, drop the flag and tell the UI.
    private func reconcileFocus() {
        guard let id = focusedTabID,
              !tabsByPath.values.contains(where: { $0.contains { $0.id == id } }) else { return }
        focusedTabID = nil
        terminalHasFocus = false
        focusLostCount += 1
    }
}
