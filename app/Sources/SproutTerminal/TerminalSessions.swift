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
        tabsByPath[path, default: []].append(handle)
        activeByPath[path] = id
        return handle
    }

    public func activate(_ id: UUID, in path: String) {
        guard tabs(for: path).contains(where: { $0.id == id }) else { return }
        activeByPath[path] = id
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
    }

    private func remove(_ id: UUID, in path: String) {
        var tabs = tabs(for: path)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        tabsByPath[path] = tabs.isEmpty ? nil : tabs
        if activeByPath[path] == id {
            activeByPath[path] = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }
}
