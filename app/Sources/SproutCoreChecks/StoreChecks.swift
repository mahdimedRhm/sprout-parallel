import CheckKit
import Foundation
import SproutCore

@MainActor
func storeChecks() async {
    await refreshChecks()
    await createChecks()
    await deleteChecks()
    await deleteFailureChecks()
    await busyDuringReloadChecks()
    await clearChecks()
    await navigationChecks()
}

@MainActor
private func clearChecks() async {
    var branches = ["feature/a", "feature/b"]
    var clearResult = ShellResult(exitCode: 0, stdout: "Deleted worktree 'feature-a'\n\ncleared 2 · skipped 0 · failed 0\n")
    let shell = FakeShell { command in
        if command.contains(" clear ") {
            if clearResult.exitCode == 0 { branches = [] }
            return clearResult
        }
        return ShellResult(exitCode: 0, stdout: statusJSON(branches))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.beginClear()
    guard case .clear(let project) = store.mode else {
        check(false, "beginClear enters clear mode")
        return
    }
    checkEqual(project.name, "scooda", "clear targets the selected project")

    await store.clear(project, force: false, dropData: true)
    checkEqual(store.log.first, "$ sprout-parallel clear --project scooda", "clear log starts with command")
    check(store.log.contains("cleared 2 · skipped 0 · failed 0"), "clear streams the summary")
    checkEqual(store.operation, .succeeded, "clear succeeded")
    checkEqual(store.worktreeCount, 0, "list refreshed after clear")
    checkEqual(store.selectedWorktree, nil, "no worktree selected after clear")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after clear")

    store.backToList()
    branches = ["feature/a", "feature/locked"]
    await store.refresh()
    clearResult = ShellResult(
        exitCode: 1,
        stdout: "cleared 1 · skipped 0 · failed 1\n",
        stderr: "Error: Failed to delete 1 worktree(s) in 'scooda'.\n")
    store.beginClear()
    if case .clear(let again) = store.mode {
        await store.clear(again, force: true, dropData: false)
    }
    check(shell.commands.contains("sprout-parallel clear --project scooda --force --keep-db"),
          "clear passes --force and --keep-db")
    checkEqual(store.operation, .failed("Error: Failed to delete 1 worktree(s) in 'scooda'."), "clear failure shown")
    check(store.log.contains("Error: Failed to delete 1 worktree(s) in 'scooda'."), "clear failure keeps Error: line in log")

    store.backToList()
    store.selectProject("prayercal")
    store.beginClear()
    checkEqual(store.mode, .list, "beginClear ignored for a project without worktrees")
}

@MainActor
private func refreshChecks() async {
    var fail = false
    let shell = FakeShell { _ in
        fail ? ShellResult(exitCode: 1, stderr: "Error: boom\n")
             : ShellResult(exitCode: 0, stdout: statusJSON(["feature/a", "feature/b"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    checkEqual(store.projects.map(\.name), ["scooda", "prayercal"], "refresh loads projects")
    checkEqual(store.selectedProjectName, "scooda", "first project selected")
    checkEqual(store.selectedWorktree?.branch, "feature/a", "first worktree selected")
    checkEqual(store.worktreeCount, 2, "worktree count")
    check(store.lastRefresh != nil, "lastRefresh set")
    check(!store.isRefreshing, "not refreshing afterwards")

    fail = true
    await store.refresh()
    checkEqual(store.projects.count, 2, "failed refresh keeps previous data")
    checkEqual(store.error, "Error: boom", "failed refresh shows error")

    fail = false
    await store.refresh()
    checkEqual(store.error, nil, "successful refresh clears error")

    let missing = WorktreeStore(cli: SproutCLI(shell: FakeShell { _ in ShellResult(exitCode: 127) }))
    await missing.refresh()
    check(missing.scriptMissing, "exit 127 flags script missing")
}

@MainActor
private func createChecks() async {
    var branches = ["feature/a"]
    let shell = FakeShell { command in
        if command.contains(" create ") {
            if command.contains("feature/taken") {
                return ShellResult(exitCode: 1, stderr: "Error: Branch 'feature/taken' already exists in 'scooda'.\n")
            }
            branches.append("feature/new")
            return ShellResult(exitCode: 0, stdout: "Created worktree\n  → Copying .env from main project\n")
        }
        return ShellResult(exitCode: 0, stdout: statusJSON(branches))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.beginCreate()
    checkEqual(store.mode, .create, "beginCreate switches mode")
    await store.create(branch: "feature/new", base: "main", runSetup: true)
    checkEqual(store.log.first, "$ sprout-parallel create feature/new --project scooda --from main", "log starts with command")
    check(store.log.contains("  → Copying .env from main project"), "log streams script output")
    checkEqual(store.operation, .succeeded, "create succeeded")
    checkEqual(store.selectedWorktree?.branch, "feature/new", "new worktree selected after create")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after create")
    checkEqual(store.mode, .create, "stays in create mode to show the log")

    store.backToList()
    checkEqual(store.mode, .list, "backToList returns to list")
    checkEqual(store.log, [], "backToList clears log")
    checkEqual(store.operation, .idle, "backToList resets operation")

    store.beginCreate()
    await store.create(branch: "feature/taken", base: "main", runSetup: false)
    checkEqual(store.operation, .failed("Error: Branch 'feature/taken' already exists in 'scooda'."), "create failure shown")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after failed create")
    check(store.log.contains("Error: Branch 'feature/taken' already exists in 'scooda'."),
          "failed create keeps Error: line in log")

    let slow = FakeShell { command in
        command.contains(" create ") ? ShellResult(exitCode: 0, stdout: "ok")
                                     : ShellResult(exitCode: 0, stdout: statusJSON([]))
    }
    slow.delayNanos = 50_000_000
    let busy = WorktreeStore(cli: SproutCLI(shell: slow))
    await busy.refresh()
    async let first: Void = busy.create(branch: "feature/one", base: "main", runSetup: true)
    async let second: Void = busy.create(branch: "feature/two", base: "main", runSetup: true)
    _ = await (first, second)
    checkEqual(slow.commands.filter { $0.contains(" create ") }.count, 1, "only one operation at a time")
}

@MainActor
private func deleteChecks() async {
    var branches = ["feature/a", "feature/b"]
    let shell = FakeShell { command in
        if command.contains(" delete ") {
            branches.removeFirst()
            return ShellResult(exitCode: 0, stdout: "Deleted worktree 'feature-a'\n")
        }
        return ShellResult(exitCode: 0, stdout: statusJSON(branches))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.beginDelete()
    guard case .delete(let worktree) = store.mode else {
        check(false, "beginDelete enters delete mode")
        return
    }
    checkEqual(worktree.branch, "feature/a", "delete targets selected worktree")

    await store.delete(worktree, force: false, dropData: false)
    check(shell.commands.contains("sprout-parallel delete feature-a --project scooda --keep-db"),
          "delete uses folder name and --keep-db when not dropping data")
    checkEqual(store.operation, .succeeded, "delete succeeded")
    checkEqual(store.selectedWorktree?.branch, "feature/b", "selection moves to remaining worktree")
    checkEqual(store.worktreeCount, 1, "list refreshed after delete")
}

@MainActor
private func deleteFailureChecks() async {
    let message = "Error: Worktree 'feature-a' has uncommitted changes. Use --force to delete anyway."
    let shell = FakeShell { command in
        command.contains(" delete ")
            ? ShellResult(exitCode: 1, stderr: message + "\n")
            : ShellResult(exitCode: 0, stdout: statusJSON(["feature/a", "feature/b"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    store.beginDelete()
    guard case .delete(let worktree) = store.mode else {
        check(false, "beginDelete enters delete mode (failure case)")
        return
    }
    await store.delete(worktree, force: false, dropData: false)
    checkEqual(store.operation, .failed(message), "delete failure shown")
    check(store.log.contains(message), "failed delete keeps Error: line in log")
    checkEqual(shell.commands.last, "sprout-parallel status --json", "refreshes after failed delete")
    checkEqual(store.worktreeCount, 2, "failed delete leaves worktrees")
}

/// The store must stay busy through the post-operation reload.
@MainActor
private func busyDuringReloadChecks() async {
    let shell = FakeShell { command in
        command.contains(" create ") ? ShellResult(exitCode: 0, stdout: "ok")
                                     : ShellResult(exitCode: 0, stdout: statusJSON(["feature/a"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    shell.delayNanos = 100_000_000
    store.beginCreate()
    let task = Task { @MainActor in
        await store.create(branch: "feature/new", base: "main", runSetup: true)
    }
    // create command finishes at ~100ms; the reload then runs until ~200ms.
    try? await Task.sleep(nanoseconds: 150_000_000)
    check(shell.commands.last == "sprout-parallel status --json", "post-op reload is in flight")
    check(store.isBusy, "busy during post-op reload")
    store.backToList()
    checkEqual(store.mode, .create, "backToList ignored during post-op reload")
    check(!store.log.isEmpty, "log kept during post-op reload")
    store.beginDelete()
    checkEqual(store.mode, .create, "beginDelete ignored during post-op reload")
    await task.value
    check(!store.isBusy, "not busy after reload finishes")
    checkEqual(store.operation, .succeeded, "operation succeeded after reload")
}

@MainActor
private func navigationChecks() async {
    let shell = FakeShell { _ in ShellResult(exitCode: 0, stdout: statusJSON(["feature/a", "feature/b"])) }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()

    store.moveWorktree(by: 1)
    checkEqual(store.selectedWorktree?.branch, "feature/b", "move down")
    store.moveWorktree(by: 5)
    checkEqual(store.selectedWorktree?.branch, "feature/b", "move clamps at end")
    store.moveWorktree(by: -9)
    checkEqual(store.selectedWorktree?.branch, "feature/a", "move clamps at start")

    store.moveProject(by: 1)
    checkEqual(store.selectedProjectName, "prayercal", "move to next project")
    checkEqual(store.selectedWorktree, nil, "empty project has no selection")
    store.beginDelete()
    checkEqual(store.mode, .list, "beginDelete ignored without a worktree")
    store.selectProject("scooda")
    checkEqual(store.selectedWorktree?.branch, "feature/a", "selectProject picks its first worktree")
}
