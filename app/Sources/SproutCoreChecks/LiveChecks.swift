import Foundation
import SproutCore

/// Prepends environment setup to every command, so the live check runs this
/// repo's script against a scratch projects root.
final class EnvShell: Shell {
    private let base: Shell
    private let prefix: String

    init(base: Shell, prefix: String) {
        self.base = base
        self.prefix = prefix
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        await base.run(prefix + command, onLine: onLine)
    }
}

/// End-to-end: real zsh, real script (from this checkout), scratch git repo.
func liveChecks() async {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SproutCoreChecks
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // app
        .deletingLastPathComponent()   // repo root
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sprout-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let shell = EnvShell(
        base: LoginShell(),
        prefix: "export SPROUT_PROJECTS_ROOT=\(shellQuote(root.path)); export PATH=\(shellQuote(repo.path)):\"$PATH\"; ")

    let setup = await shell.run("""
        mkdir -p "$SPROUT_PROJECTS_ROOT/demo" && cd "$SPROUT_PROJECTS_ROOT/demo" \
        && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
        """) { _ in }
    checkEqual(setup.exitCode, 0, "live: scratch project created")

    let cli = SproutCLI(shell: shell)
    do {
        try await cli.run(SproutCLI.createCommand(project: "demo", branch: "feature/live", base: "main", runSetup: false)) { _ in }
        let status = try await cli.status()
        let worktree = status.projects.first { $0.name == "demo" }?.worktrees.first
        checkEqual(worktree?.branch, "feature/live", "live: real script output decodes")
        checkEqual(worktree?.base, "main", "live: base recorded")
        checkEqual(worktree?.ahead, 0, "live: ahead computed")

        try await cli.run(SproutCLI.deleteCommand(project: "demo", folder: "feature-live", force: false, keepData: false)) { _ in }
        let after = try await cli.status()
        checkEqual(after.projects.first { $0.name == "demo" }?.worktrees.count, 0, "live: delete by folder works")
    } catch {
        check(false, "live: \(error)")
    }
}
