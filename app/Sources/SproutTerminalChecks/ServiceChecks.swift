import CheckKit
import Foundation
import SproutTerminal

@MainActor
func serviceChecks() async {
    var made: [FakeTerminal] = []
    let sessions = TerminalSessions { _ in
        let terminal = FakeTerminal()
        made.append(terminal)
        return terminal
    }
    sessions.serviceTimeout = 0.3
    let path = "/p/demo-worktrees/feature-a"

    check(sessions.startService(.serve, command: "php artisan serve", in: path), "start opens a serve tab")
    let serve = made.last!
    checkEqual(serve.sent, ["php artisan serve\n"], "start types the command")
    check(sessions.isServiceRunning(.serve, in: path), "serve is running")
    checkEqual(sessions.service(of: serve.id, in: path), .serve, "the tab is known as serve")
    check(sessions.activeTab(for: path) === serve, "start activates the service tab")
    check(!sessions.startService(.serve, command: "php artisan serve", in: path), "start refuses when already running")
    checkEqual(made.count, 1, "no second serve tab")

    await sessions.restartService(.serve, command: "php artisan serve", in: path)
    checkEqual(serve.sent, ["php artisan serve\n", "\u{3}", "php artisan serve\n"], "restart sends ⌃C then the command")
    check(sessions.isServiceRunning(.serve, in: path), "running again after restart")

    await sessions.stopService(.serve, in: path)
    check(serve.terminated, "stop closes the serve tab")
    check(sessions.serviceTab(.serve, in: path) == nil, "serve is forgotten after stop")
    check(!sessions.isServiceRunning(.serve, in: path), "serve not running after stop")

    // A command that ignores ⌃C
    sessions.startService(.queue, command: "php artisan queue:work", in: path)
    let stubborn = made.last!
    stubborn.ignoresInterrupt = true
    await sessions.restartService(.queue, command: "php artisan queue:work", in: path)
    check(stubborn.terminated, "restart terminates a tab that ignores ⌃C")
    let fresh = sessions.serviceTab(.queue, in: path) as? FakeTerminal
    check(fresh != nil && fresh !== stubborn, "restart starts a fresh queue tab")
    checkEqual(fresh?.sent, ["php artisan queue:work\n"], "the fresh tab runs the command")

    // Reusing an idle service tab
    fresh?.isBusy = false
    let countBefore = made.count
    sessions.startService(.queue, command: "php artisan queue:work", in: path)
    checkEqual(made.count, countBefore, "start reuses an idle service tab")

    // A service tab closed by hand is forgotten
    if let fresh { sessions.closeTab(fresh.id, in: path) }
    check(sessions.serviceTab(.queue, in: path) == nil, "a hand-closed service tab is forgotten")
    sessions.startService(.serve, command: "php artisan serve", in: path)
    made.last!.exitShell()
    check(sessions.serviceTab(.serve, in: path) == nil, "a service whose shell exits is forgotten")

    // Prune forgets services of vanished worktrees
    sessions.startService(.serve, command: "php artisan serve", in: path)
    sessions.prune(keeping: [])
    check(sessions.serviceTab(.serve, in: path) == nil, "prune forgets services")
    await sessions.stopService(.queue, in: path)   // nothing to stop: no crash

    await raceChecks()
}

@MainActor
private func raceChecks() async {
    var made: [FakeTerminal] = []
    let sessions = TerminalSessions { _ in
        let terminal = FakeTerminal()
        made.append(terminal)
        return terminal
    }
    sessions.serviceTimeout = 0.5
    let path = "/p/demo-worktrees/race"
    let cmd = "php artisan serve"

    // Tab closed by hand while a restart waits
    sessions.startService(.serve, command: cmd, in: path)
    let a = made.last!
    a.ignoresInterrupt = true
    let restartA = Task { await sessions.restartService(.serve, command: cmd, in: path) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    sessions.closeTab(a.id, in: path)
    let sentAtClose = a.sent.count
    await restartA.value
    checkEqual(made.count, 1, "closed mid-restart: no new tab opened")
    checkEqual(a.sent.count, sentAtClose, "closed mid-restart: nothing sent after close")
    check(sessions.activeTab(for: path) == nil && sessions.activeByPath[path] == nil, "closed mid-restart: no stale active tab")

    // Worktree pruned while a restart waits
    sessions.startService(.serve, command: cmd, in: path)
    let b = made.last!
    b.ignoresInterrupt = true
    let restartB = Task { await sessions.restartService(.serve, command: cmd, in: path) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    sessions.prune(keeping: [])
    await restartB.value
    checkEqual(made.count, 2, "pruned mid-restart: no tab resurrected")
    check(sessions.tabs(for: path).isEmpty && sessions.activeByPath[path] == nil, "pruned mid-restart: nothing left")

    // Overlapping restarts type the command once
    sessions.startService(.queue, command: cmd, in: path)
    let c = made.last!
    c.ignoresInterrupt = true   // stays busy until we let it go, so the restart is in flight
    let r1 = Task { await sessions.restartService(.queue, command: cmd, in: path) }
    let r2 = Task { await sessions.restartService(.queue, command: cmd, in: path) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    c.isBusy = false
    await r1.value
    await r2.value
    checkEqual(c.sent, [cmd + "\n", "\u{3}", cmd + "\n"], "overlapping restarts type the command once")

    // Stop during a restart is ignored
    let r3 = Task { await sessions.restartService(.queue, command: cmd, in: path) }
    try? await Task.sleep(nanoseconds: 100_000_000)
    await sessions.stopService(.queue, in: path)
    check(sessions.serviceTab(.queue, in: path) === c, "stop during restart is ignored")
    await r3.value   // c ignores ⌃C, so it is replaced
    await sessions.stopService(.queue, in: path)
    check(sessions.serviceTab(.queue, in: path) == nil, "a later stop works")
}
