// Key-routing checks: the real Sprout panel with real shells in a real window,
// driven by synthetic key events through NSApp.sendEvent (the same path as
// typing). Opens a window for ~40s and needs it to stay the key window, so
// don't use the Mac while it runs. Run: swift run SproutKeyChecks
import AppKit
import CheckKit
import SproutCore
import SproutTerminal
import SproutUI
import SwiftUI

/// Serves a fixed status and counts refreshes.
final class FixtureShell: Shell {
    let json: String
    var statusCalls = 0
    init(_ json: String) { self.json = json }
    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        if command.contains("status") { statusCalls += 1 }
        if command.contains(" create ") {
            // A slow create (like copying vendor/): long enough to move around meanwhile.
            onLine("Copying vendor from main project")
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            return ShellResult(exitCode: 0, stdout: "Created worktree")
        }
        return ShellResult(exitCode: 0, stdout: json)
    }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("sprout-keys-\(UUID().uuidString)")
let pathX = root.appendingPathComponent("demo-worktrees/feature-x").path
let pathY = root.appendingPathComponent("demo-worktrees/feature-y").path
let pathZ = root.appendingPathComponent("other-worktrees/feature-z").path
for path in [pathX, pathY, pathZ] {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}

func worktreeJSON(_ branch: String, _ path: String, herd: String? = nil, serve: String? = nil) -> String {
    let folder = (path as NSString).lastPathComponent
    let herdValue = herd.map { "\"\($0)\"" } ?? "null"
    let serveValue = serve.map { "\"\($0)\"" } ?? "null"
    return #"{"branch":"\#(branch)","folder":"\#(folder)","path":"\#(path)","base":"main","changes":0,"ahead":0,"behind":0,"lastCommit":null,"mysqlDb":null,"redisDb":null,"redisPrefix":null,"herdUrl":\#(herdValue),"serveUrl":\#(serveValue),"serveRunning":false}"#
}

let statusJSON = #"{"projects":[{"name":"demo","path":"\#(root.path)/demo","branches":["main"],"worktrees":["#
    + worktreeJSON("feature/x", pathX, herd: "https://demo-feature-x.test", serve: "http://127.0.0.1:8001") + ","
    + worktreeJSON("feature/y", pathY)
    + #"]},{"name":"other","path":"\#(root.path)/other","branches":["main"],"worktrees":["#
    + worktreeJSON("feature/z", pathZ) + "]}]}"

setvbuf(stdout, nil, _IOLBF, 0)   // keep output if a check run crashes
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

// MARK: - Synthetic keys

let keyCodes: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "o": 31, "u": 32, "i": 34,
    "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ".": 47, " ": 49, "`": 50,
    "]": 30, "[": 33, "/": 44,
]
let shifted: [Character: Character] = [">": ".", "?": "/", "{": "[", "}": "]"]

enum Special: UInt16 {
    case returnKey = 36, backspace = 51, escape = 53, left = 123, right = 124, down = 125, up = 126

    var characters: String {
        switch self {
        case .returnKey: "\r"
        case .backspace: "\u{7f}"
        case .escape: "\u{1b}"
        case .left: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case .right: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case .down: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .up: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        }
    }

    var isArrow: Bool { rawValue >= 123 }
}

@MainActor
func pause(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

@MainActor
func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        await pause(0.05)
    }
    return condition()
}

@MainActor
func send(_ characters: String, ignoring: String, code: UInt16, mods: NSEvent.ModifierFlags, to window: NSWindow) {
    if !window.isKeyWindow {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(event)
    }
}

/// Types text as a user would (shift for uppercase and shifted symbols).
@MainActor
func type(_ text: String, into window: NSWindow) async {
    for ch in text {
        let base = shifted[ch] ?? Character(ch.lowercased())
        let shift = ch.isUppercase || shifted[ch] != nil
        send(String(ch), ignoring: String(ch), code: keyCodes[base] ?? 0, mods: shift ? [.shift] : [], to: window)
        await pause(0.03)
    }
}

@MainActor
func press(_ key: Special, _ window: NSWindow, _ mods: NSEvent.ModifierFlags = []) async {
    let flags = key.isArrow ? mods.union([.numericPad, .function]) : mods
    send(key.characters, ignoring: key.characters, code: key.rawValue, mods: flags, to: window)
    await pause(0.15)
}

/// A shortcut like ⌘T or ⌘⇧]: characters reflect shift, ⌃` becomes NUL.
@MainActor
func shortcut(_ key: Character, _ mods: NSEvent.ModifierFlags, _ window: NSWindow) async {
    let base = shifted[key] ?? key
    let shown = mods.contains(.shift) && shifted[key] == nil ? String(key).uppercased() : String(key)
    let typed = mods.contains(.control) && key == "`" ? "\u{0}" : shown
    send(typed, ignoring: shown, code: keyCodes[Character(base.lowercased())] ?? 0, mods: mods, to: window)
    await pause(0.2)
}

@MainActor
func contents(_ path: String, _ name: String) -> String? {
    (try? String(contentsOfFile: (path as NSString).appendingPathComponent(name), encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Checks

@MainActor
func keyChecks() async {
    var opened: [String] = []
    Openers.intercept = { opened.append($0) }
    UserDefaults.standard.set(false, forKey: "sprout.terminalCollapsed")

    let shell = FixtureShell(statusJSON)
    let store = WorktreeStore(cli: SproutCLI(shell: shell))
    await store.refresh()
    let terminals = TerminalSessions { ShellTerminal(directory: $0) }
    let window = NSWindow(
        contentRect: NSRect(x: 120, y: 120, width: 900, height: 700),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = NSHostingView(
        rootView: PanelView().environmentObject(store).environmentObject(terminals))
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    defer {
        terminals.terminateAll()
        window.orderOut(nil)
    }
    check(await waitUntil(5) { terminals.activeTab(for: pathX)?.view?.window != nil }, "first terminal opens")
    await pause(1.5)   // let zsh start

    func focusList() async {
        window.makeFirstResponder(window.contentView)
        _ = await waitUntil(2) { !terminals.terminalHasFocus }
    }

    // ── List keys ────────────────────────────────────────────────────────
    await focusList()
    await press(.down, window)
    checkEqual(store.selectedWorktreePath, pathY, "↓ selects the next worktree")
    await press(.up, window)
    checkEqual(store.selectedWorktreePath, pathX, "↑ selects the previous worktree")
    await press(.right, window)
    checkEqual(store.selectedProjectName, "other", "→ selects the next project")
    await press(.left, window)
    checkEqual(store.selectedProjectName, "demo", "← selects the previous project")
    checkEqual(store.selectedWorktreePath, pathX, "changing project selects its first worktree")

    opened = []
    await press(.returnKey, window)
    await type("t", into: window)
    await type("f", into: window)
    await type("o", into: window)
    await type("O", into: window)
    checkEqual(opened, [
        "vscode:\(pathX)", "warp:\(pathX)", "finder:\(pathX)",
        "browser:https://demo-feature-x.test", "browser:http://127.0.0.1:8001",
    ], "⏎ t f o ⇧O open VS Code, Warp, Finder, Herd URL, serve URL")

    let calls = shell.statusCalls
    await type("r", into: window)
    check(await waitUntil(2) { shell.statusCalls > calls }, "r refreshes")
    let callsAfterR = shell.statusCalls
    await shortcut("r", [.command], window)
    check(await waitUntil(2) { shell.statusCalls > callsAfterR }, "⌘R refreshes")

    await type("?", into: window)
    check(store.showingKeys, "? shows the keyboard cheat sheet")
    await press(.escape, window)
    check(!store.showingKeys, "esc closes the cheat sheet")
    check(window.isVisible, "esc closing the cheat sheet doesn't hide the window")
    await type("?", into: window)
    await type("?", into: window)
    check(!store.showingKeys, "? again closes the cheat sheet")

    await type("n", into: window)
    checkEqual(store.mode, .create, "n opens the create form")
    await pause(0.4)   // a person doesn't press esc within 30ms of the form appearing
    await press(.escape, window)
    checkEqual(store.mode, .list, "esc goes back from the create form")
    await press(.backspace, window)
    check({ if case .delete = store.mode { return true }; return false }(), "⌫ opens delete for the worktree")
    await pause(0.4)
    await press(.escape, window)
    await type("X", into: window)
    check({ if case .clear = store.mode { return true }; return false }(), "⇧X opens clear all")
    await pause(0.4)
    await press(.escape, window)
    checkEqual(store.mode, .list, "esc goes back to the list")

    await press(.escape, window)
    check(!window.isVisible, "esc in the list hides the window")
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    await pause(0.3)

    // ── Terminal keys ────────────────────────────────────────────────────
    await shortcut("`", [.control], window)
    check(await waitUntil(3) { terminals.terminalHasFocus }, "⌃` focuses the terminal")

    opened = []
    await type("echo north forest rX > keys.txt", into: window)
    await press(.returnKey, window)
    check(await waitUntil(5) { contents(pathX, "keys.txt") != nil }, "⏎ in the terminal runs the command")
    checkEqual(contents(pathX, "keys.txt"), "north forest rX", "every letter reaches the shell")
    await type("echo abX", into: window)
    await press(.backspace, window)
    await type("c > back.txt", into: window)
    await press(.returnKey, window)
    check(await waitUntil(5) { contents(pathX, "back.txt") != nil }, "command with backspace runs")
    checkEqual(contents(pathX, "back.txt"), "abc", "backspace reaches the shell")
    checkEqual(store.mode, .list, "typing in the terminal triggers no list action")
    checkEqual(opened, [], "typing in the terminal opens nothing")
    check(!store.showingKeys, "typing ? in the terminal doesn't show the cheat sheet")
    check(terminals.terminalHasFocus, "the terminal keeps focus while typing")

    await shortcut("t", [.command], window)
    await shortcut("t", [.command], window)
    check(await waitUntil(3) { terminals.tabs(for: pathX).count == 3 }, "⌘T opens tabs")
    let ids = terminals.tabs(for: pathX).map { $0.id }
    guard ids.count == 3 else {
        check(false, "tab shortcuts need 3 tabs, have \(ids.count)")
        return
    }
    await shortcut("1", [.command], window)
    check(terminals.activeTab(for: pathX)?.id == ids.first, "⌘1 jumps to the first tab")
    await shortcut("3", [.command], window)
    check(terminals.activeTab(for: pathX)?.id == ids.last, "⌘3 jumps to the third tab")
    await shortcut("{", [.command, .shift], window)
    check(terminals.activeTab(for: pathX)?.id == ids[1], "⌘⇧[ goes to the previous tab")
    await shortcut("}", [.command, .shift], window)
    check(terminals.activeTab(for: pathX)?.id == ids[2], "⌘⇧] goes to the next tab")
    await shortcut("w", [.command, .shift], window)
    check(await waitUntil(3) { terminals.tabs(for: pathX).count == 2 }, "⌘⇧W closes the active tab")
    check(await waitUntil(2) { terminals.terminalHasFocus }, "focus moves to the remaining tab")

    await shortcut("`", [.control], window)
    check(await waitUntil(3) { !terminals.terminalHasFocus }, "⌃` moves focus to the list")
    await press(.down, window)
    checkEqual(store.selectedWorktreePath, pathY, "list keys work after ⌃`")
    await press(.up, window)

    // Moving to another project while a command runs in the terminal
    await shortcut("`", [.control], window)
    _ = await waitUntil(2) { terminals.terminalHasFocus }
    await type("sleep 20", into: window)
    await press(.returnKey, window)
    check(await waitUntil(3) { terminals.activeTab(for: pathX)?.isBusy == true }, "a command is running")
    await shortcut("`", [.control], window)
    _ = await waitUntil(2) { !terminals.terminalHasFocus }
    await press(.right, window)
    checkEqual(store.selectedProjectName, "other", "→ switches project while a command runs")
    await press(.left, window)
    checkEqual(store.selectedProjectName, "demo", "← switches back while a command runs")
    check(terminals.activeTab(for: pathX)?.isBusy == true, "the command keeps running across project switches")

    // A form open while typing in the terminal
    await type("n", into: window)
    checkEqual(store.mode, .create, "n opens the form from the list")
    await pause(0.5)
    await shortcut("`", [.control], window)
    check(await waitUntil(3) { terminals.terminalHasFocus }, "⌃` focuses the terminal with a form open")
    await press(.escape, window)
    checkEqual(store.mode, .create, "esc in the terminal doesn't close the form")
    await shortcut("`", [.control], window)
    _ = await waitUntil(2) { !terminals.terminalHasFocus }
    await press(.escape, window)
    checkEqual(store.mode, .list, "esc closes the form once the terminal isn't focused")

    // Collapsing a focused terminal hands the keys to the list
    await shortcut("`", [.control], window)
    _ = await waitUntil(2) { terminals.terminalHasFocus }
    UserDefaults.standard.set(true, forKey: "sprout.terminalCollapsed")
    _ = await waitUntil(2) { !terminals.terminalHasFocus }
    await pause(0.3)
    await press(.down, window)
    checkEqual(store.selectedWorktreePath, pathY, "list keys work after collapsing a focused terminal")
    UserDefaults.standard.set(false, forKey: "sprout.terminalCollapsed")

    // Moving around while a create runs in the background (it used to lock everything)
    await focusList()
    store.selectProject("demo")
    await type("n", into: window)
    await pause(0.5)
    await type("feature/bg", into: window)
    send("\r", ignoring: "\r", code: 36, mods: [.command], to: window)   // ⌘⏎ create
    check(await waitUntil(2) { store.isBusy }, "the create is running")
    await press(.right, window)
    checkEqual(store.selectedProjectName, "other", "→ moves to another project while a create runs")
    checkEqual(store.mode, .list, "moving leaves the create form")
    await press(.left, window)
    await type("l", into: window)
    checkEqual(store.mode, .activity, "l shows the running create's log")
    check(store.log.contains("Copying vendor from main project"), "with its live output")
    await press(.escape, window)
    checkEqual(store.mode, .list, "esc leaves the log; the create keeps running")
    check(await waitUntil(5) { !store.isBusy }, "the create finishes in the background")
    checkEqual(store.operation, .succeeded, "and succeeds")
    // ── Command palette ──────────────────────────────────────────────────
    await focusList()
    store.selectProject("demo")
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette from the list")
    opened = []
    await type("open war", into: window)
    await pause(0.2)
    await press(.returnKey, window)
    checkEqual(opened, ["warp:\(pathX)"], "typing filters and ⏎ runs the action")
    check(store.palette == nil, "running an action closes the palette")
    checkEqual(store.mode, .list, "typing in the palette triggers no list action")

    await type("s", into: window)
    checkEqual(store.palette, "serve ", "s opens the palette filtered to serve")
    await press(.escape, window)
    check(store.palette == nil, "esc closes the palette")
    check(window.isVisible, "esc closing the palette doesn't hide the window")
    await type("d", into: window)
    checkEqual(store.palette, "db ", "d opens the palette filtered to db")
    await press(.escape, window)
    await type("q", into: window)
    checkEqual(store.palette, "queue ", "q opens the palette filtered to queue")
    await press(.escape, window)

    // Window shortcuts do nothing while the palette is open.
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette before the shortcut check")
    await shortcut("`", [.control], window)
    await pause(0.3)
    await type("abc", into: window)
    check(store.palette != nil, "⌃` doesn't close the palette")
    check(store.palette?.contains("abc") == true, "typing after ⌃` still reaches the palette field")
    check(!terminals.terminalHasFocus, "⌃` doesn't move focus to a terminal behind the palette")
    await press(.escape, window)
    check(store.palette == nil, "esc closes the palette")

    await shortcut("`", [.control], window)
    check(await waitUntil(3) { terminals.terminalHasFocus }, "back in the terminal")
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette from the terminal")
    opened = []
    await type("open fin", into: window)
    await pause(0.2)
    await press(.returnKey, window)
    checkEqual(opened, ["finder:\(pathX)"], "the palette runs actions opened from the terminal")
    check(await waitUntil(2) { terminals.terminalHasFocus }, "closing the palette returns focus to the terminal")

    // An action that opens a form keeps the keyboard for the form, not the terminal.
    await shortcut("P", [.command, .shift], window)
    check(await waitUntil(2) { store.palette != nil }, "⌘⇧P opens the palette again from the terminal")
    await type("worktree new", into: window)
    await pause(0.2)
    await press(.returnKey, window)
    checkEqual(store.mode, .create, "worktree: new opens the create form")
    await pause(1)
    check(!terminals.terminalHasFocus, "the form keeps the keyboard; the terminal doesn't take it back")
    await press(.escape, window)
    checkEqual(store.mode, .list, "esc leaves the form")
    Openers.intercept = nil
}

DispatchQueue.main.async {
    Task { @MainActor in
        await keyChecks()
        try? FileManager.default.removeItem(at: root)
        finishChecks()
    }
}
NSApp.run()
