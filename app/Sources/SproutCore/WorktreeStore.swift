import Foundation

/// App state: what's on disk (via `status --json`), what's selected, and the
/// create/delete operation in flight.
@MainActor
public final class WorktreeStore: ObservableObject {
    public enum Mode: Equatable {
        case list
        case create
        case delete(Worktree)
        case clear(Project)
        /// The log of the running (or last) operation, reopened from the header.
        case activity
    }

    /// The running (or last) create/delete/clear, shown in the header so it can
    /// keep going while the user moves around.
    public struct Activity: Equatable {
        public enum Kind: Equatable {
            case create(branch: String)
            case delete(branch: String)
            case clear
        }

        public let kind: Kind
        public let project: String

        public init(kind: Kind, project: String) {
            self.kind = kind
            self.project = project
        }

        public var runningTitle: String {
            switch kind {
            case .create(let branch): "creating \(branch) in \(project)"
            case .delete(let branch): "deleting \(branch) in \(project)"
            case .clear: "clearing \(project)"
            }
        }

        public var doneTitle: String {
            switch kind {
            case .create(let branch): "created \(branch)"
            case .delete(let branch): "deleted \(branch)"
            case .clear: "cleared \(project)"
            }
        }

        public var failedTitle: String {
            switch kind {
            case .create: "create failed"
            case .delete: "delete failed"
            case .clear: "clear failed"
            }
        }
    }

    public enum Operation: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    @Published public private(set) var projects: [Project] = []
    @Published public var selectedProjectName: String?
    @Published public var selectedWorktreePath: String?
    /// The keyboard cheat sheet (`?`) is showing.
    @Published public var showingKeys = false
    @Published public private(set) var mode: Mode = .list
    @Published public private(set) var operation: Operation = .idle
    @Published public private(set) var activity: Activity?
    @Published public private(set) var log: [String] = []
    @Published public private(set) var error: String?
    @Published public private(set) var scriptMissing = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?

    private let cli: SproutCLI
    private var refreshQueued = false

    public init(cli: SproutCLI) {
        self.cli = cli
    }

    public var selectedProject: Project? {
        projects.first { $0.name == selectedProjectName }
    }

    public var selectedWorktree: Worktree? {
        selectedProject?.worktrees.first { $0.path == selectedWorktreePath }
    }

    public var worktreeCount: Int {
        projects.reduce(0) { $0 + $1.worktrees.count }
    }

    public var isBusy: Bool { operation == .running }

    // MARK: Loading

    /// UI-triggered refresh. Overlapping calls coalesce into one extra load.
    public func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        repeat {
            refreshQueued = false
            await loadStatus()
        } while refreshQueued
        isRefreshing = false
    }

    private func loadStatus() async {
        do {
            let status = try await cli.status()
            projects = status.projects
            scriptMissing = false
            error = nil
            lastRefresh = Date()
            repairSelection()
        } catch CLIError.notFound {
            scriptMissing = true
        } catch let cliError as CLIError {
            error = cliError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func repairSelection() {
        if selectedProject == nil {
            selectedProjectName = projects.first?.name
        }
        if selectedWorktree == nil {
            selectedWorktreePath = selectedProject?.worktrees.first?.path
        }
    }

    // MARK: Navigation

    public func selectProject(_ name: String) {
        selectedProjectName = name
        selectedWorktreePath = selectedProject?.worktrees.first?.path
    }

    public func moveProject(by offset: Int) {
        guard let index = projects.firstIndex(where: { $0.name == selectedProjectName }) else { return }
        let target = min(max(index + offset, 0), projects.count - 1)
        selectProject(projects[target].name)
    }

    public func moveWorktree(by offset: Int) {
        guard let worktrees = selectedProject?.worktrees, !worktrees.isEmpty else { return }
        let index = worktrees.firstIndex { $0.path == selectedWorktreePath } ?? 0
        let target = min(max(index + offset, 0), worktrees.count - 1)
        selectedWorktreePath = worktrees[target].path
    }

    // MARK: Modes

    public func beginCreate() {
        guard !isBusy, selectedProject != nil else { return }
        resetOperation()
        mode = .create
    }

    public func beginDelete() {
        guard !isBusy, let worktree = selectedWorktree else { return }
        resetOperation()
        mode = .delete(worktree)
    }

    public func beginClear() {
        guard !isBusy, let project = selectedProject, !project.worktrees.isEmpty else { return }
        resetOperation()
        mode = .clear(project)
    }

    /// Leaves a form (or the activity log). A running operation keeps going in
    /// the background, and its log stays available from the header.
    public func backToList() {
        mode = .list
    }

    /// Shows the running or last operation's log.
    public func showActivity() {
        guard activity != nil else { return }
        mode = .activity
    }

    private func resetOperation() {
        operation = .idle
        log = []
        activity = nil
    }

    // MARK: Operations

    public func create(branch: String, base: String, runSetup: Bool) async {
        guard !isBusy, let project = selectedProject else { return }
        activity = Activity(kind: .create(branch: branch), project: project.name)
        let command = SproutCLI.createCommand(project: project.name, branch: branch, base: base, runSetup: runSetup)
        let outcome = await perform(command)
        await loadStatus()
        // Only jump to the new worktree if the user is still on its project.
        if case .succeeded = outcome, selectedProjectName == project.name,
           let created = selectedProject?.worktrees.first(where: { $0.branch == branch }) {
            selectedWorktreePath = created.path
        }
        operation = outcome
    }

    public func delete(_ worktree: Worktree, force: Bool, dropData: Bool) async {
        guard !isBusy, let project = selectedProject else { return }
        activity = Activity(kind: .delete(branch: worktree.branch), project: project.name)
        let command = SproutCLI.deleteCommand(
            project: project.name, folder: worktree.folder, force: force, keepData: !dropData)
        let outcome = await perform(command)
        if case .succeeded = outcome, selectedWorktreePath == worktree.path {
            selectedWorktreePath = nil
        }
        await loadStatus()
        operation = outcome
    }

    public func clear(_ project: Project, force: Bool, dropData: Bool) async {
        guard !isBusy else { return }
        activity = Activity(kind: .clear, project: project.name)
        let command = SproutCLI.clearCommand(project: project.name, force: force, keepData: !dropData)
        let outcome = await perform(command)
        await loadStatus()
        operation = outcome
    }

    /// Runs the command and returns its outcome without publishing it: the
    /// store stays `.running` (busy) until the caller has reloaded status.
    private func perform(_ command: String) async -> Operation {
        log = ["$ " + command]
        operation = .running
        do {
            try await cli.run(command) { line in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.log.append(line) }
                }
            }
            await drainMainQueue()
            return .succeeded
        } catch {
            await drainMainQueue()
            return .failed((error as? CLIError)?.message ?? error.localizedDescription)
        }
    }

    /// Lets log lines already queued on the main queue land before we report
    /// the final status.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
