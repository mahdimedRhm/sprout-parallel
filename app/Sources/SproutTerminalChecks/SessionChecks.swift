import CheckKit
import Foundation
import SproutTerminal

@MainActor
func sessionChecks() {
    var made: [FakeTerminal] = []
    var failing = Set<String>()
    let sessions = TerminalSessions { directory in
        if failing.contains(directory) { return nil }
        let terminal = FakeTerminal()
        made.append(terminal)
        return terminal
    }
    let a = "/p/scooda-worktrees/feature-a"
    let b = "/p/scooda-worktrees/feature-b"

    sessions.ensureTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 1, "ensureTab opens the first tab")
    sessions.ensureTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 1, "ensureTab doesn't open a second tab")
    let second = sessions.openTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 2, "openTab adds a tab")
    check(sessions.activeTab(for: a) === second, "new tab becomes active")
    checkEqual(sessions.tabs(for: b).count, 0, "tabs are per worktree")

    sessions.activate(made[0].id, in: a)
    check(sessions.activeTab(for: a) === made[0], "activate switches tab")
    sessions.activate(UUID(), in: a)
    check(sessions.activeTab(for: a) === made[0], "activating an unknown id is ignored")

    sessions.closeTab(made[0].id, in: a)
    check(made[0].terminated, "closeTab terminates the shell")
    checkEqual(sessions.tabs(for: a).map { $0.id }, [made[1].id], "closeTab removes the tab")
    check(sessions.activeTab(for: a) === made[1], "active moves to the neighbour")

    made[1].exitShell()
    checkEqual(sessions.tabs(for: a).count, 0, "a shell exiting removes its tab")
    check(sessions.activeTab(for: a) == nil, "no active tab when none are left")
    sessions.ensureTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 0, "ensureTab doesn't reopen after the user closed everything")
    sessions.openTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 1, "openTab still works after that")

    failing.insert(b)
    check(sessions.openTab(in: b) == nil, "a failed start returns nil")
    check(sessions.failedPaths.contains(b), "failed start is remembered")
    failing.remove(b)
    sessions.openTab(in: b)
    check(!sessions.failedPaths.contains(b), "a successful retry clears the failure")

    let aTab = made[2]
    let bTab = made[3]
    aTab.isBusy = true
    aTab.title = "php"
    checkEqual(sessions.busyTabs(), [TerminalSessions.BusyTab(path: a, title: "php")], "busyTabs lists only busy tabs")
    checkEqual(sessions.busyTabs().first?.label, "php — scooda/feature-a", "busy label names project and folder")

    sessions.prune(keeping: [b])
    check(aTab.terminated, "prune terminates tabs of vanished worktrees")
    checkEqual(sessions.tabs(for: a).count, 0, "prune removes them")
    checkEqual(sessions.tabs(for: b).count, 1, "prune keeps existing worktrees")
    sessions.ensureTab(in: a)
    checkEqual(sessions.tabs(for: a).count, 1, "a re-created worktree gets a fresh first tab")

    sessions.terminateAll()
    check(bTab.terminated, "terminateAll terminates every shell")
    checkEqual(sessions.busyTabs(), [], "nothing is left after terminateAll")

    // Focus tracking (the flag esc-handling in forms and window-key handling rely on).
    let f = TerminalSessions { _ in FakeTerminal() }
    let one = f.openTab(in: a) as! FakeTerminal
    let two = f.openTab(in: a) as! FakeTerminal
    check(!f.terminalHasFocus, "no terminal focus initially")
    one.setFocused(true)
    check(f.terminalHasFocus, "focus report sets terminalHasFocus")
    one.setFocused(false)
    check(!f.terminalHasFocus, "resign clears terminalHasFocus")
    one.setFocused(true)
    two.setFocused(true)
    one.setFocused(false)
    check(f.terminalHasFocus, "a stale resign from another tab keeps the flag")
    two.setFocused(false)
    check(!f.terminalHasFocus, "flag clears once the focused tab resigns")

    let before = f.focusLostCount
    two.setFocused(true)
    f.closeTab(two.id, in: a)
    check(!f.terminalHasFocus, "closing the focused tab clears the flag")
    checkEqual(f.focusLostCount, before + 1, "closing the focused tab signals focus loss")
    f.closeTab(one.id, in: a)
    checkEqual(f.focusLostCount, before + 1, "closing an unfocused tab doesn't")
    let three = f.openTab(in: a) as! FakeTerminal
    three.setFocused(true)
    three.exitShell()
    checkEqual(f.focusLostCount, before + 2, "a focused shell exiting signals focus loss")
}
