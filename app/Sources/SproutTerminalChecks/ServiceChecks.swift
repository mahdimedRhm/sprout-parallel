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
}
