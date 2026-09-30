# Sprout Embedded Terminals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every worktree its own terminal tabs inside the Sprout window, running the user's `zsh -l` in the worktree folder.

**Architecture:** A new `SproutTerminal` library wraps SwiftTerm: `ShellTerminal` is one real shell; `TerminalSessions` (an `ObservableObject`) keeps tabs per worktree path and is tested with fake handles. `SproutUI` gains a `SplitPane` + `TerminalPane` under the existing right-pane content; the app delegate owns the sessions, prunes them when worktrees disappear, and warns on quit.

**Tech Stack:** Swift 5.9 tools / Swift 6.2 CLT toolchain, SwiftUI + AppKit, SwiftTerm 1.20.x (first third-party dependency). No Xcode.

**Spec:** `docs/superpowers/specs/2026-09-30-sprout-terminals-design.md`

## Global Constraints

- Root `app/Package.swift` stays `// swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`.
- The only external dependency is SwiftTerm: `.package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0"))`. Commit `app/Package.resolved`.
- `XCTest`/`Testing` are unavailable; tests are executables: `cd app && swift run SproutCoreChecks`, `swift run SproutTerminalChecks`. Both exit non-zero on failure. Bash suites: `bash tests/status_test.sh`, `bash tests/clear_test.sh`, `bash tests/serve_test.sh`.
- Shell: `/bin/zsh -l`, cwd = worktree path, env = process env + `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG=en_US.UTF-8` if unset.
- Terminal colours: background `#070A0D`, foreground `#C9D1D9`, caret `#39FFA0`, selection `#1D3A4A`; ANSI 16 = `#0B0F14 #FF6B6B #39FFA0 #FFCC66 #56D4FF #C792EA #56D4FF #C9D1D9 #6B7A8C #FF8A8A #7CFFC0 #FFDD99 #8AE2FF #DDB3F5 #8AE2FF #E6EDF3`. Font JetBrains Mono 12 if installed, else system monospaced 12.
- UserDefaults keys: `sprout.terminalFraction` (Double, default 0.45, clamp 0.15–0.85), `sprout.terminalCollapsed` (Bool, default false).
- Keys: ``⌃` `` toggle focus list ⇄ terminal (expanding if collapsed); `⌘T` new tab; `⌘⇧W` close tab (confirm if busy). When the terminal has focus, all other keys go to the shell.
- `cd app && swift build` must produce no new warnings.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `app/.build/`, `app/build/`, `.superpowers/`.

## Review Focus

1. **Keys typed in the terminal** (`esc`, letters, `⏎`, arrows, e.g. in `vim`) must reach the shell and never trigger Sprout's list shortcuts or hide the window. Pinned: Task 4 live checklist items 3–4 (can't be exercised headlessly).
2. **A shell exiting on its own** (`exit`) removes its tab, and the worktree's terminal does not silently reopen. Pinned: Task 1 (`ensureTab doesn't reopen after the user closed everything`), Task 2 (`exit fires onExit`).
3. **A worktree removed while its shells run** (delete, clear, removed outside Sprout) terminates those shells. Pinned: Task 1 (`prune terminates tabs of vanished worktrees`), Task 4 checklist item 7.
4. **A worktree folder that no longer exists** gives a failure state, not a crash or a shell in the wrong folder. Pinned: Task 2 (`no shell for a missing folder`), Task 1 (`failed start is remembered`).
5. **Quitting with busy tabs** lists each as `<title> — <project>/<folder>` and can be cancelled. Pinned: Task 1 (`busy label names project and folder`), Task 4 checklist item 8.

---

## File Map

| File | Responsibility |
|---|---|
| `app/Package.swift` | + SwiftTerm, `CheckKit`, `SproutTerminal`, `SproutTerminalChecks`; UI/app/snapshots depend on `SproutTerminal` (Task 3) |
| `app/Sources/CheckKit/Check.swift` | Shared check harness (moved from `SproutCoreChecks`) |
| `app/Sources/SproutTerminal/TerminalHandle.swift` | Protocol for one shell as sessions see it |
| `app/Sources/SproutTerminal/TerminalSessions.swift` | Tabs per worktree, active tab, prune, busy list |
| `app/Sources/SproutTerminal/ShellTerminal.swift` | Real `zsh -l` in a SwiftTerm view; title/busy/exit |
| `app/Sources/SproutTerminal/TerminalTheme.swift` | Palette + font for SwiftTerm |
| `app/Sources/SproutTerminalChecks/*.swift` | Fake handle, session checks, live shell checks |
| `app/Sources/SproutUI/SplitPane.swift` | Top/bottom split with draggable divider, collapse |
| `app/Sources/SproutUI/TerminalPane.swift` | Tab bar, terminal host, empty states |
| `app/Sources/SproutUI/PanelView.swift` (modify) | Split layout, ``⌃` `` / `⌘T` / `⌘⇧W` |
| `app/Sources/SproutUI/Chrome.swift` (modify) | Footer hints |
| `app/Sources/Sprout/SproutApp.swift` (modify) | Owns sessions, prunes, quit alert |
| `app/Sources/SproutSnapshots/main.swift` (modify) | Snapshot fakes + terminal snapshot |
| `docs/README.md` (modify) | Terminal section |

---

### Task 1: SwiftTerm dependency, shared check harness, TerminalSessions

**Files:**
- Modify: `app/Package.swift`
- Move: `app/Sources/SproutCoreChecks/Check.swift` → `app/Sources/CheckKit/Check.swift` (made public)
- Modify: every `app/Sources/SproutCoreChecks/*.swift` (add `import CheckKit`)
- Create: `app/Sources/SproutTerminal/TerminalHandle.swift`, `app/Sources/SproutTerminal/TerminalSessions.swift`
- Create: `app/Sources/SproutTerminalChecks/FakeTerminal.swift`, `SessionChecks.swift`, `main.swift`

**Interfaces:**
- Produces (module `CheckKit`, public): `var failures: Int`, `check(_:_:file:line:)`, `checkEqual(_:_:_:file:line:)`, `finishChecks() -> Never`.
- Produces (module `SproutTerminal`, public, all `@MainActor`):
  - `protocol TerminalHandle: AnyObject { var id: UUID { get }; var title: String { get }; var isBusy: Bool { get }; var view: NSView? { get }; var onExit: (() -> Void)? { get set }; func terminate() }`
  - `final class TerminalSessions: ObservableObject` with `typealias Factory = (_ directory: String) -> (any TerminalHandle)?`, `struct BusyTab: Equatable { path: String; title: String; var label: String }`, `init(factory:)`, `@Published private(set) var tabsByPath: [String: [any TerminalHandle]]`, `activeByPath: [String: UUID]`, `failedPaths: Set<String>`, and `tabs(for:)`, `activeTab(for:)`, `ensureTab(in:)`, `@discardableResult openTab(in:) -> (any TerminalHandle)?`, `activate(_:in:)`, `closeTab(_:in:)`, `prune(keeping:)`, `busyTabs() -> [BusyTab]`, `terminateAll()`.

- [ ] **Step 1: Package manifest**

Replace `app/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        .target(name: "SproutCore"),
        .target(name: "SproutTerminal", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .target(name: "SproutUI", dependencies: ["SproutCore"]),
        .target(name: "CheckKit"),
        .executableTarget(name: "Sprout", dependencies: ["SproutCore", "SproutUI"]),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore", "CheckKit"]),
        .executableTarget(name: "SproutTerminalChecks", dependencies: ["SproutTerminal", "CheckKit"]),
        .executableTarget(name: "SproutSnapshots", dependencies: ["SproutCore", "SproutUI"]),
    ]
)
```

- [ ] **Step 2: Move the check harness into `CheckKit`**

```bash
cd app
mkdir -p Sources/CheckKit
git mv Sources/SproutCoreChecks/Check.swift Sources/CheckKit/Check.swift
for f in Sources/SproutCoreChecks/*.swift; do
  grep -q '^import CheckKit' "$f" || sed -i '' '1s/^/import CheckKit\n/' "$f"
done
```

Replace `app/Sources/CheckKit/Check.swift`:

```swift
import Foundation

/// Number of failed checks so far; `finishChecks()` exits non-zero if any.
public var failures = 0

public func check(_ condition: Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name) (\(file):\(line))")
    }
}

public func checkEqual<T: Equatable>(
    _ actual: T, _ expected: T, _ name: String,
    file: StaticString = #fileID, line: UInt = #line
) {
    if actual == expected {
        print("ok   - \(name)")
    } else {
        failures += 1
        print("FAIL - \(name): expected \(expected), got \(actual) (\(file):\(line))")
    }
}

/// Prints the summary and exits: 0 when every check passed, 1 otherwise.
public func finishChecks() -> Never {
    print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
    exit(failures == 0 ? 0 : 1)
}
```

In `app/Sources/SproutCoreChecks/main.swift`, replace the last two lines (the `print(failures == 0 …)` and `exit(…)`) with:

```swift
finishChecks()
```

Run: `cd app && swift run SproutCoreChecks 2>&1 | tail -1`
Expected: `all checks passed` (the move changed nothing). SwiftPM fetches SwiftTerm on this first build.

- [ ] **Step 3: Write the failing session checks**

`app/Sources/SproutTerminalChecks/FakeTerminal.swift`:

```swift
import AppKit
import SproutTerminal

/// In-memory stand-in for a shell.
@MainActor
final class FakeTerminal: TerminalHandle {
    let id = UUID()
    var title = "zsh"
    var isBusy = false
    var view: NSView? { nil }
    var onExit: (() -> Void)?
    private(set) var terminated = false

    func terminate() { terminated = true }

    /// Simulates the shell exiting on its own (e.g. the user typed `exit`).
    func exitShell() { onExit?() }
}
```

`app/Sources/SproutTerminalChecks/SessionChecks.swift`:

```swift
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
}
```

`app/Sources/SproutTerminalChecks/main.swift`:

```swift
import AppKit
import CheckKit

_ = NSApplication.shared

await sessionChecks()

finishChecks()
```

Also create `app/Sources/SproutTerminal/TerminalHandle.swift` containing only `import AppKit` so the target has a source file.

- [ ] **Step 4: Run to verify it fails**

Run: `cd app && swift run SproutTerminalChecks 2>&1 | grep -m3 error:`
Expected: `cannot find type 'TerminalHandle'` / `cannot find 'TerminalSessions'`.

- [ ] **Step 5: Implement**

`app/Sources/SproutTerminal/TerminalHandle.swift`:

```swift
import AppKit

/// One shell session as `TerminalSessions` sees it. `ShellTerminal` is the real
/// one; checks use fakes.
@MainActor
public protocol TerminalHandle: AnyObject {
    var id: UUID { get }
    /// What the tab shows: the running command, else the shell's title, else the shell name.
    var title: String { get }
    /// A command other than the shell itself is in the foreground.
    var isBusy: Bool { get }
    /// The view to host; nil for fakes.
    var view: NSView? { get }
    /// Called once if the shell exits on its own (not after `terminate()`).
    var onExit: (() -> Void)? { get set }
    func terminate()
}
```

`app/Sources/SproutTerminal/TerminalSessions.swift`:

```swift
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
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd app && swift build 2>&1 | grep -E 'warning:|error:' ; swift run SproutTerminalChecks 2>&1 | tail -3; swift run SproutCoreChecks 2>&1 | tail -1`
Expected: no warnings/errors from our sources; `all checks passed` twice.

- [ ] **Step 7: Commit**

```bash
git add app/Package.swift app/Package.resolved app/Sources/CheckKit app/Sources/SproutCoreChecks app/Sources/SproutTerminal app/Sources/SproutTerminalChecks
git commit -m "Add SwiftTerm dependency and TerminalSessions (tabs per worktree)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ShellTerminal and TerminalTheme

**Files:**
- Create: `app/Sources/SproutTerminal/ShellTerminal.swift`, `app/Sources/SproutTerminal/TerminalTheme.swift`
- Create: `app/Sources/SproutTerminalChecks/ShellChecks.swift`
- Modify: `app/Sources/SproutTerminalChecks/main.swift`

**Interfaces:**
- Consumes: `TerminalHandle` (Task 1).
- Produces (public, `SproutTerminal`): `@MainActor final class ShellTerminal: NSObject, TerminalHandle` with `init?(directory: String, shell: String = "/bin/zsh")`, `let terminalView: LocalProcessTerminalView`, `var foregroundProcessName: String?`, `static func environment(base: [String: String] = …) -> [String]`. `enum TerminalTheme` with `static let ansi: [UInt32]`, `static func apply(to: TerminalView)`, `static func nsColor(_: UInt32) -> NSColor`.

- [ ] **Step 1: Write the failing checks**

`app/Sources/SproutTerminalChecks/ShellChecks.swift`:

```swift
import CheckKit
import Foundation
import SproutTerminal

/// Polls `condition` (letting the main queue run the shell's I/O) until it's
/// true or `seconds` pass.
@MainActor
func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}

@MainActor
func shellChecks() async {
    let env = ShellTerminal.environment(base: ["PATH": "/bin", "TERM": "dumb"])
    check(env.contains("TERM=xterm-256color"), "environment sets TERM")
    check(env.contains("COLORTERM=truecolor"), "environment sets COLORTERM")
    check(env.contains("LANG=en_US.UTF-8"), "environment defaults LANG")
    check(env.contains("PATH=/bin"), "environment keeps the rest")
    check(ShellTerminal.environment(base: ["LANG": "fr_FR.UTF-8"]).contains("LANG=fr_FR.UTF-8"),
          "environment keeps an existing LANG")
    checkEqual(TerminalTheme.ansi.count, 16, "theme has 16 ANSI colours")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprout-term-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    check(ShellTerminal(directory: dir.appendingPathComponent("missing").path) == nil, "no shell for a missing folder")

    guard let terminal = ShellTerminal(directory: dir.path) else {
        check(false, "shell starts in an existing folder")
        return
    }
    var exited = false
    terminal.onExit = { exited = true }

    let marker = dir.appendingPathComponent("pwd.txt")
    terminal.terminalView.send(txt: "pwd -P > '\(marker.path)'\n")
    let realDir = (dir.path as NSString).resolvingSymlinksInPath
    let startedInFolder = await waitUntil(10) {
        (try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == realDir
    }
    check(startedInFolder, "shell starts in the worktree folder")
    check(!terminal.isBusy, "idle shell is not busy")

    terminal.terminalView.send(txt: "sleep 3\n")
    check(await waitUntil(3) { terminal.isBusy }, "busy while a command runs")
    checkEqual(terminal.title, "sleep", "title is the running command")
    check(await waitUntil(6) { !terminal.isBusy }, "idle again when it finishes")

    terminal.terminalView.send(txt: "exit\n")
    check(await waitUntil(5) { exited }, "exit fires onExit")

    guard let other = ShellTerminal(directory: dir.path) else {
        check(false, "second shell starts")
        return
    }
    var otherExited = false
    other.onExit = { otherExited = true }
    other.terminate()
    _ = await waitUntil(1.5) { otherExited }
    check(!otherExited, "terminate() doesn't report an exit")
    check(!other.isBusy, "a terminated shell is not busy")
}
```

Replace `app/Sources/SproutTerminalChecks/main.swift`:

```swift
import AppKit
import CheckKit

_ = NSApplication.shared

await sessionChecks()
await shellChecks()

finishChecks()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && swift run SproutTerminalChecks 2>&1 | grep -m3 error:`
Expected: `cannot find 'ShellTerminal'` / `cannot find 'TerminalTheme'`.

- [ ] **Step 3: Implement the theme**

`app/Sources/SproutTerminal/TerminalTheme.swift`:

```swift
import AppKit
import SwiftTerm

/// Sprout's palette applied to SwiftTerm.
public enum TerminalTheme {
    /// ANSI 0–15: normal then bright.
    public static let ansi: [UInt32] = [
        0x0B0F14, 0xFF6B6B, 0x39FFA0, 0xFFCC66, 0x56D4FF, 0xC792EA, 0x56D4FF, 0xC9D1D9,
        0x6B7A8C, 0xFF8A8A, 0x7CFFC0, 0xFFDD99, 0x8AE2FF, 0xDDB3F5, 0x8AE2FF, 0xE6EDF3,
    ]

    public static func apply(to view: TerminalView) {
        view.installColors(ansi.map(terminalColor))
        view.nativeBackgroundColor = nsColor(0x070A0D)
        view.nativeForegroundColor = nsColor(0xC9D1D9)
        view.caretColor = nsColor(0x39FFA0)
        view.selectedTextBackgroundColor = nsColor(0x1D3A4A)
        view.font = NSFont(name: "JetBrainsMono-Regular", size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    public static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// SwiftTerm colours are 16-bit per channel.
    static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257)
    }
}
```

- [ ] **Step 4: Implement the shell**

`app/Sources/SproutTerminal/ShellTerminal.swift`:

```swift
import AppKit
import Darwin
import SwiftTerm

/// A real login shell running in a folder inside a SwiftTerm view.
@MainActor
public final class ShellTerminal: NSObject, TerminalHandle {
    public let id = UUID()
    public let terminalView: LocalProcessTerminalView
    public var onExit: (() -> Void)?
    public var view: NSView? { terminalView }

    private let shellName: String
    private var shellTitle: String?
    private var ended = false

    /// Returns nil when `directory` isn't an existing folder or the shell can't start.
    public init?(directory: String, shell: String = "/bin/zsh") {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        shellName = (shell as NSString).lastPathComponent
        terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        super.init()
        terminalView.processDelegate = self
        TerminalTheme.apply(to: terminalView)
        terminalView.startProcess(
            executable: shell, args: ["-l"], environment: Self.environment(), currentDirectory: directory)
        guard terminalView.process.running else { return nil }
    }

    /// The process environment plus what a colour terminal needs.
    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var env = base
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"]?.isEmpty ?? true { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Name of the terminal's foreground process group leader (the shell when idle).
    public var foregroundProcessName: String? {
        guard !ended, terminalView.process.running else { return nil }
        let group = tcgetpgrp(terminalView.process.childfd)
        guard group > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(group, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    public var isBusy: Bool {
        guard let name = foregroundProcessName else { return false }
        return name != shellName
    }

    public var title: String {
        if let name = foregroundProcessName, name != shellName { return name }
        if let shellTitle, !shellTitle.isEmpty { return shellTitle }
        return shellName
    }

    public func terminate() {
        guard !ended else { return }
        ended = true
        terminalView.terminate()
    }
}

extension ShellTerminal: LocalProcessTerminalViewDelegate {
    nonisolated public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.shellTitle = title }
        }
    }

    nonisolated public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated public func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                // After terminate() the tab is already gone; only report exits the shell made itself.
                guard !self.ended else { return }
                self.ended = true
                self.onExit?()
            }
        }
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd app && swift build 2>&1 | grep -E 'warning:|error:' | grep -v '/.build/checkouts/' ; swift run SproutTerminalChecks 2>&1 | grep -E 'FAIL|all checks|failed'`
Expected: no warnings/errors from our sources; `all checks passed`. If a live check fails, debug the cause (e.g. print `terminal.foregroundProcessName`) — never loosen a check.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/SproutTerminal app/Sources/SproutTerminalChecks
git commit -m "Add ShellTerminal (zsh in a worktree) and terminal theme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Split layout, terminal pane, and terminal keys

**Files:**
- Modify: `app/Package.swift` (SproutUI, Sprout, SproutSnapshots depend on `SproutTerminal`)
- Create: `app/Sources/SproutUI/SplitPane.swift`, `app/Sources/SproutUI/TerminalPane.swift`
- Modify: `app/Sources/SproutUI/PanelView.swift`, `app/Sources/SproutUI/Chrome.swift`
- Modify: `app/Sources/SproutSnapshots/main.swift`

**Interfaces:**
- Consumes: `TerminalSessions`, `TerminalHandle` (Task 1); `WorktreeStore.selectedWorktree`, `Theme`, `KeyHint`, `Hairline` (existing).
- Produces: `PanelView` now also requires `TerminalSessions` as an `environmentObject` (Task 4 supplies it in the app).

- [ ] **Step 1: Snapshot cases first (failing)**

In `app/Package.swift`, change these three targets:

```swift
        .target(name: "SproutUI", dependencies: ["SproutCore", "SproutTerminal"]),
        .executableTarget(name: "Sprout", dependencies: ["SproutCore", "SproutUI", "SproutTerminal"]),
        .executableTarget(name: "SproutSnapshots", dependencies: ["SproutCore", "SproutUI", "SproutTerminal"]),
```

In `app/Sources/SproutSnapshots/main.swift`:

1. Add `import SproutTerminal` to the imports.
2. Directly after the `FixtureShell` class, add:

```swift
/// Terminal stand-in for snapshots (the AppKit terminal doesn't render in ImageRenderer).
@MainActor
final class SnapshotTerminal: TerminalHandle {
    let id = UUID()
    let title: String
    let isBusy: Bool
    var view: NSView? { nil }
    var onExit: (() -> Void)?

    init(title: String = "zsh", busy: Bool = false) {
        self.title = title
        self.isBusy = busy
    }

    func terminate() {}
}
```

3. Change `render`'s signature and renderer line to:

```swift
@MainActor
func render(_ name: String, _ store: WorktreeStore, terminals: TerminalSessions = TerminalSessions { _ in SnapshotTerminal() }) {
    let renderer = ImageRenderer(
        content: PanelView().environmentObject(store).environmentObject(terminals).frame(width: 900, height: 640))
```

4. Append at the end of the file:

```swift
let withTerminals = await makeStore(ok)
var nextTitles = [("php", true), ("npm", true), ("zsh", false)]
let busyTerminals = TerminalSessions { _ in
    let (title, busy) = nextTitles.isEmpty ? ("zsh", false) : nextTitles.removeFirst()
    return SnapshotTerminal(title: title, busy: busy)
}
if let path = withTerminals.selectedWorktree?.path {
    busyTerminals.openTab(in: path)
    busyTerminals.openTab(in: path)
    busyTerminals.openTab(in: path)
}
render("terminal-tabs", withTerminals, terminals: busyTerminals)
```

Run: `cd app && swift run SproutSnapshots 2>&1 | tail -2`
Expected: it builds and writes `terminal-tabs.png`, but that image shows **no** terminal area or tab bar — `PanelView` doesn't use `TerminalSessions` yet. That's the failing state.

- [ ] **Step 2: SplitPane**

`app/Sources/SproutUI/SplitPane.swift`:

```swift
import AppKit
import SwiftUI

/// `top` above a draggable divider, `bottom` below. The bottom's share of the
/// height and its collapsed state persist across launches.
struct SplitPane<Top: View, Bottom: View>: View {
    @AppStorage("sprout.terminalFraction") private var fraction = 0.45
    @AppStorage("sprout.terminalCollapsed") private var collapsed = false
    @State private var dragStartFraction: Double?

    /// Height of the bottom when collapsed: just its tab bar.
    static var collapsedHeight: CGFloat { 30 }

    private let top: Top
    private let bottom: Bottom

    init(@ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let bottomHeight = collapsed
                ? Self.collapsedHeight
                : max(Self.collapsedHeight, (height * fraction).rounded())
            VStack(spacing: 0) {
                top.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                divider(totalHeight: height)
                bottom.frame(height: bottomHeight)
            }
        }
    }

    private func divider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: collapsed ? 1 : 5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside && !collapsed { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard !collapsed, totalHeight > 0 else { return }
                        let start = dragStartFraction ?? fraction
                        dragStartFraction = start
                        fraction = min(0.85, max(0.15, start - value.translation.height / totalHeight))
                    }
                    .onEnded { _ in dragStartFraction = nil })
    }
}
```

- [ ] **Step 3: TerminalPane**

`app/Sources/SproutUI/TerminalPane.swift`:

```swift
import AppKit
import SproutCore
import SproutTerminal
import SwiftUI

/// The selected worktree's terminal tabs, below the worktree info.
struct TerminalPane: View {
    @EnvironmentObject private var store: WorktreeStore
    @EnvironmentObject private var terminals: TerminalSessions
    @AppStorage("sprout.terminalCollapsed") private var collapsed = false

    private var path: String? { store.selectedWorktree?.path }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if !collapsed {
                Hairline()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.logBg)
        .onAppear(perform: openIfNeeded)
        .onChange(of: store.selectedWorktreePath) { _, _ in openIfNeeded() }
        .onChange(of: collapsed) { _, _ in openIfNeeded() }
    }

    private func openIfNeeded() {
        guard !collapsed, let path else { return }
        terminals.ensureTab(in: path)
    }

    private var tabBar: some View {
        // Titles and busy dots follow what's running, so re-read them every second.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 2) {
                if let path {
                    ForEach(terminals.tabs(for: path), id: \.id) { tab in
                        TerminalTabButton(
                            title: tab.title, busy: tab.isBusy,
                            active: terminals.activeTab(for: path)?.id == tab.id
                        ) {
                            terminals.activate(tab.id, in: path)
                            collapsed = false
                        }
                    }
                    Button {
                        terminals.openTab(in: path)
                        collapsed = false
                    } label: {
                        Text("＋").foregroundStyle(Theme.muted).padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                    .help("new tab (⌘T)")
                } else {
                    Text("terminal").foregroundStyle(Theme.muted).padding(.horizontal, 10)
                }
                Spacer()
                Button { collapsed.toggle() } label: {
                    KeyHint(key: "⌃`", label: collapsed ? "show" : "hide")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
            .frame(height: SplitPane<EmptyView, EmptyView>.collapsedHeight - 1)
        }
        .font(Theme.mono(11))
        .background(Theme.bar)
    }

    @ViewBuilder private var content: some View {
        if let path {
            if let tab = terminals.activeTab(for: path) {
                if let view = tab.view {
                    TerminalHost(view: view).id(tab.id).padding(6)
                } else {
                    placeholder("terminal · \(tab.title)")
                }
            } else if terminals.failedPaths.contains(path) {
                placeholder("✗ could not start shell · ⌘T to retry", color: Theme.red)
            } else {
                placeholder("no terminal · ⌘T to open")
            }
        } else {
            placeholder("select a worktree to open its terminal")
        }
    }

    private func placeholder(_ text: String, color: Color = Theme.muted) -> some View {
        Text(text).foregroundStyle(color).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalTabButton: View {
    let title: String
    let busy: Bool
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy { Text("●").foregroundStyle(Theme.green) }
                Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
            }
            .foregroundStyle(active ? Theme.bright : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Theme.logBg : Color.clear)
            .overlay(alignment: .top) {
                if active { Rectangle().fill(Theme.green).frame(height: 2) }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Hosts a terminal's AppKit view. The view outlives this wrapper, so it's
/// re-parented (not recreated) when tabs or worktrees switch.
struct TerminalHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {}

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
```

- [ ] **Step 4: PanelView — split layout and terminal keys**

In `app/Sources/SproutUI/PanelView.swift`:

1. Add `import SproutTerminal` to the imports.
2. Below `@FocusState private var focused: Bool`, add:

```swift
    @EnvironmentObject private var terminals: TerminalSessions
    @AppStorage("sprout.terminalCollapsed") private var terminalCollapsed = false
```

3. Replace

```swift
                    content
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

with

```swift
                    SplitPane {
                        content
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } bottom: {
                        TerminalPane()
                    }
```

4. Directly after `.onKeyPress(action: handleKey)`, add:

```swift
        .background { terminalShortcuts }
```

5. Add these members inside `PanelView` (after `content`):

```swift
    /// Window-level shortcuts: they fire even while the terminal has focus.
    private var terminalShortcuts: some View {
        ZStack {
            Button("", action: toggleTerminalFocus).keyboardShortcut("`", modifiers: .control)
            Button("", action: newTerminalTab).keyboardShortcut("t", modifiers: .command)
            Button("", action: closeTerminalTab).keyboardShortcut("w", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var terminalPath: String? { store.selectedWorktree?.path }

    private func toggleTerminalFocus() {
        guard let path = terminalPath else { return }
        if let view = terminals.activeTab(for: path)?.view, view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
            focused = true
            return
        }
        terminalCollapsed = false
        terminals.ensureTab(in: path)
        focusTerminal(in: path)
    }

    private func newTerminalTab() {
        guard let path = terminalPath else { return }
        terminalCollapsed = false
        terminals.openTab(in: path)
        focusTerminal(in: path)
    }

    private func closeTerminalTab() {
        guard let path = terminalPath, let tab = terminals.activeTab(for: path) else { return }
        if tab.isBusy {
            let alert = NSAlert()
            alert.messageText = "Close “\(tab.title)”?"
            alert.informativeText = "It's still running. Closing the tab stops it."
            alert.addButton(withTitle: "Close Tab")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        terminals.closeTab(tab.id, in: path)
    }

    private func focusTerminal(in path: String) {
        // The view is attached to the window on the next layout pass.
        DispatchQueue.main.async {
            guard let view = terminals.activeTab(for: path)?.view else { return }
            view.window?.makeFirstResponder(view)
        }
    }
```

- [ ] **Step 5: Footer hints**

In `app/Sources/SproutUI/Chrome.swift`, in `FooterBar.hints`, `.list` case, replace

```swift
             Hint(key: "r", label: "refresh"), Hint(key: "↑↓", label: "move")]
```

with

```swift
             Hint(key: "r", label: "refresh"), Hint(key: "↑↓", label: "move"),
             Hint(key: "⌃`", label: "terminal"), Hint(key: "⌘T", label: "tab")]
```

- [ ] **Step 6: Build, render, inspect**

Run: `cd app && swift build 2>&1 | grep -E 'warning:|error:' | grep -v '/.build/checkouts/'; swift run SproutSnapshots 2>&1 | grep -c wrote; swift run SproutCoreChecks 2>&1 | tail -1; swift run SproutTerminalChecks 2>&1 | tail -1`
Expected: no warnings/errors from our sources; `11` snapshots; `all checks passed` twice.

Open `app/build/snapshots/terminal-tabs.png` (Read tool): the right pane is split — worktree table/details on top, a divider, then a tab bar with `● php`, `● npm`, `zsh` (the last active, bright, green top border), `＋`, and `⌃` hide` on the right, and `terminal · zsh` in the terminal area. `list.png` shows the tab bar with no tabs and `no terminal · ⌘T to open` (fakes don't auto-open under ImageRenderer). The footer shows `⌃` terminal` and `⌘T tab`.

- [ ] **Step 7: Commit**

```bash
git add app/Package.swift app/Sources/SproutUI app/Sources/SproutSnapshots
git commit -m "Add split layout with per-worktree terminal tabs and terminal keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: App wiring (sessions, pruning, quit warning), docs, install

**Files:**
- Modify: `app/Sources/Sprout/SproutApp.swift`
- Modify: `docs/README.md`

**Interfaces:**
- Consumes: `TerminalSessions(factory:)`, `prune(keeping:)`, `busyTabs()`, `BusyTab.label`, `terminateAll()` (Task 1); `ShellTerminal(directory:)` (Task 2); `PanelView` needing `TerminalSessions` (Task 3); `WorktreeStore.$projects`.

- [ ] **Step 1: Wire the app delegate**

In `app/Sources/Sprout/SproutApp.swift`:

1. Add `import Combine` and `import SproutTerminal` to the imports.
2. Below `private let store = WorktreeStore(cli: SproutCLI(shell: LoginShell()))`, add:

```swift
    private let terminals = TerminalSessions { ShellTerminal(directory: $0) }
    private var projectsWatch: AnyCancellable?
```

3. At the end of `applicationDidFinishLaunching`, add:

```swift
        // Close the terminals of worktrees that no longer exist (deleted, cleared, removed elsewhere).
        projectsWatch = store.$projects.dropFirst().sink { [weak self] projects in
            MainActor.assumeIsolated {
                self?.terminals.prune(keeping: Set(projects.flatMap { $0.worktrees.map(\.path) }))
            }
        }
```

4. Add this method to `AppDelegate`:

```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let busy = terminals.busyTabs()
        if !busy.isEmpty {
            let alert = NSAlert()
            alert.messageText = busy.count == 1
                ? "1 terminal is still running"
                : "\(busy.count) terminals are still running"
            alert.informativeText = busy.map(\.label).joined(separator: "\n") + "\n\nQuitting Sprout stops them."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        terminals.terminateAll()
        return .terminateNow
    }
```

5. In `makeWindow()`, change the hosting line to:

```swift
        let hosting = NSHostingView(
            rootView: PanelView().environmentObject(store).environmentObject(terminals))
```

Run: `cd app && swift build 2>&1 | grep -E 'warning:|error:' | grep -v '/.build/checkouts/'; swift run SproutCoreChecks 2>&1 | tail -1; swift run SproutTerminalChecks 2>&1 | tail -1`
Expected: clean build; `all checks passed` twice.

- [ ] **Step 2: Document**

In `docs/README.md`, in the "Sprout menu bar app" section, insert before `### Install`:

```markdown
### Terminals

Every worktree has its own terminal tabs below its details, running your login
shell (`zsh -l`, so `~/.zshrc` applies) in the worktree folder. Switching
worktree switches terminals; the others keep running. Drag the divider to
resize; ``⌃` `` hides/shows it and moves focus between the list and the
terminal. While the terminal has focus every key goes to the shell. Terminals
of deleted worktrees are closed, and quitting Sprout warns if a command is still
running.
```

In the Keys table, add after the `⇧X` row:

```markdown
| ``⌃` `` | focus the terminal / back to the list |
| `⌘T` / `⌘⇧W` | new terminal tab / close tab |
```

In the Development block, add after the `SproutCoreChecks` line:

```bash
swift run SproutTerminalChecks # terminal sessions + live zsh checks
```

- [ ] **Step 3: Full verification, install**

Run: `bash tests/status_test.sh | tail -1; bash tests/clear_test.sh | tail -1; bash tests/serve_test.sh | tail -1; (cd app && swift run SproutCoreChecks 2>&1 | tail -1; swift run SproutTerminalChecks 2>&1 | tail -1); bash app/build.sh`
Expected: `all tests passed` ×3, `all checks passed` ×2, `Installed: …/Sprout.app`.

- [ ] **Step 4: Commit**

```bash
git add app/Sources/Sprout/SproutApp.swift docs/README.md
git commit -m "Wire terminals into the app: prune on refresh, warn on quit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Live checklist (human — controller runs it with the user)**

With Sprout running on real projects:
1. Select a worktree: a terminal opens below, in its folder (`pwd`).
2. `php artisan serve` (or `sleep 30`) → tab shows `● php` / `● sleep`.
3. Click into the terminal; type `vim`, press `esc`, `:q⏎` — vim handles every key; the window doesn't hide, no Sprout shortcut fires.
4. ``⌃` `` → focus back on the list (arrows move worktrees); ``⌃` `` again → back in the terminal.
5. `⌘T` → second tab; switch worktree and back → both tabs still there, `serve` still running.
6. Drag the divider; ``⌃` `` hide/show; quit and relaunch → size/collapsed remembered.
7. Delete a worktree that has a terminal → its tabs are gone after the list refreshes.
8. With a busy tab, `⌘Q` → alert lists `php — <project>/<folder>`; Cancel keeps Sprout running; Quit Anyway quits.
