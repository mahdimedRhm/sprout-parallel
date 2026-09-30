import CheckKit
import Foundation
import SproutCore

@MainActor
func actionChecks() async {
    // Palette matching
    check(PaletteMatcher.matches("serve: restart", query: "ser re"), "every token must appear")
    check(!PaletteMatcher.matches("serve: restart", query: "ser xyz"), "a missing token fails the match")
    check(PaletteMatcher.matches("DB: Drop", query: "db drop"), "matching ignores case")
    check(PaletteMatcher.matches("anything", query: "  "), "an empty query matches everything")
    let titles = ["open: serve URL", "serve: start", "queue: start", "serve: stop"]
    checkEqual(PaletteMatcher.order(titles, query: "serve", title: { $0 }),
               ["serve: start", "serve: stop", "open: serve URL"],
               "titles starting with the first token come first, then catalog order")

    // Service commands
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprout-svc-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    checkEqual(ServiceCommand.serve, "php artisan serve", "serve command")
    checkEqual(ServiceCommand.queue(worktreePath: dir.path), "php artisan queue:work", "queue:work without composer.json")
    try? #"{"require":{"laravel/framework":"^11.0","laravel/horizon":"^5.0"}}"#
        .write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
    checkEqual(ServiceCommand.queue(worktreePath: dir.path), "php artisan horizon", "horizon when required")

    // db command strings
    checkEqual(SproutCLI.dbCommand(action: .refresh, project: "scooda", folder: "feature-x"),
               "sprout-parallel db refresh feature-x --project scooda", "db command")

    // Store: database operation
    var calls: [String] = []
    let shell = FakeShell { command in
        calls.append(command)
        if command.contains(" db ") { return ShellResult(exitCode: 0, stdout: "Refreshing 'x'\n") }
        return ShellResult(exitCode: 0, stdout: statusJSON(["feature/a"]))
    }
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    guard let worktree = store.selectedWorktree else { return check(false, "fixture has a worktree") }
    await store.database(.refresh, worktree: worktree)
    check(calls.contains("sprout-parallel db refresh feature-a --project scooda"), "database runs the db command")
    checkEqual(store.operation, .succeeded, "database succeeds")
    checkEqual(store.activity?.doneTitle, "database refreshed for feature/a", "database done title")
    checkEqual(store.activity?.runningTitle, "refreshing the database of feature/a", "database running title")
    checkEqual(WorktreeStore.Activity(kind: .database(.drop, branch: "b"), project: "p").failedTitle,
               "database drop failed", "database failed title")
    checkEqual(calls.last, "sprout-parallel status --json", "refreshes after a database action")

    // Refused while another operation runs
    shell.delayNanos = 200_000_000
    store.beginCreate()
    let running = Task { await store.create(branch: "feature/z", base: "main", runSetup: true) }
    try? await Task.sleep(nanoseconds: 50_000_000)
    let before = calls.count
    await store.database(.drop, worktree: worktree)
    check(!calls.dropFirst(before).contains { $0.contains(" db ") }, "database is refused while busy")
    await running.value

    // Palette state
    checkEqual(store.palette, nil, "palette starts closed")
    store.palette = "serve "
    checkEqual(store.paletteSelection, 0, "selection starts at the top")
}
