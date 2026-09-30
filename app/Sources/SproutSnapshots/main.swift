import AppKit
import SproutCore
import SproutTerminal
import SproutUI
import SwiftUI

/// Answers commands from canned results so views can be rendered offline.
final class FixtureShell: Shell {
    private let respond: (String) -> ShellResult

    init(_ respond: @escaping (String) -> ShellResult) {
        self.respond = respond
    }

    func run(_ command: String, onLine: @escaping (String) -> Void) async -> ShellResult {
        let result = respond(command)
        for line in (result.stdout + "\n" + result.stderr).split(separator: "\n") {
            onLine(String(line))
        }
        return result
    }
}

/// Terminal stand-in for snapshots (the AppKit terminal doesn't render in ImageRenderer).
@MainActor
final class SnapshotTerminal: TerminalHandle {
    let id = UUID()
    let title: String
    let isBusy: Bool
    var view: NSView? { nil }
    var onExit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    init(title: String = "zsh", busy: Bool = false) {
        self.title = title
        self.isBusy = busy
    }

    func terminate() {}
    func send(_ text: String) {}
}

let fixture = #"""
{"projects":[
 {"name":"scooda","path":"/Users/mehdi/projects/scooda","branches":["develop","main","production"],"worktrees":[
  {"branch":"feature/payments-v2","folder":"feature-payments-v2","path":"/Users/mehdi/projects/scooda-worktrees/feature-payments-v2","base":"main","changes":3,"ahead":3,"behind":1,"lastCommit":{"hash":"a1f9c2e","subject":"Add Stripe webhook","when":"2 hours ago"},"mysqlDb":"scooda_feature_payments_v2","redisDb":3,"redisPrefix":"scooda_feature_payments_v2_","herdUrl":"https://scooda-feature-payments-v2.test","serveUrl":"http://127.0.0.1:8001","serveRunning":true},
  {"branch":"fix/TICKET-123","folder":"fix-TICKET-123","path":"/Users/mehdi/projects/scooda-worktrees/fix-TICKET-123","base":"main","changes":0,"ahead":1,"behind":0,"lastCommit":{"hash":"77be01d","subject":"Guard null invoice","when":"5 days ago"},"mysqlDb":"scooda_fix_TICKET_123","redisDb":4,"redisPrefix":"scooda_fix_ticket_123_","herdUrl":"https://scooda-fix-ticket-123.test","serveUrl":"http://127.0.0.1:8002","serveRunning":false}
 ]},
 {"name":"orphan7","path":"/Users/mehdi/projects/orphan7","branches":["main"],"worktrees":[
  {"branch":"feature/donor-export","folder":"feature-donor-export","path":"/Users/mehdi/projects/orphan7-worktrees/feature-donor-export","base":"main","changes":0,"ahead":5,"behind":12,"lastCommit":{"hash":"0c4d9aa","subject":"CSV export","when":"3 weeks ago"},"mysqlDb":null,"redisDb":null,"redisPrefix":null}
 ]},
 {"name":"bookcast","path":"/Users/mehdi/projects/bookcast","branches":["main"],"worktrees":[]}
]}
"""#.replacingOccurrences(of: "\n", with: "")

let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // SproutSnapshots
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // app
    .appendingPathComponent("build/snapshots")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

_ = NSApplication.shared

@MainActor
func makeStore(_ respond: @escaping (String) -> ShellResult) async -> WorktreeStore {
    let store = WorktreeStore(cli: SproutCLI(shell: FixtureShell(respond)))
    await store.refresh()
    return store
}

@MainActor
func render(_ name: String, _ store: WorktreeStore, terminals: TerminalSessions? = nil,
            size: CGSize = CGSize(width: 900, height: 640)) {
    let terminals = terminals ?? TerminalSessions { _ in SnapshotTerminal() }
    let renderer = ImageRenderer(
        content: PanelView().environmentObject(store).environmentObject(terminals).frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("FAIL - could not render \(name)")
        exit(1)
    }
    let url = outDir.appendingPathComponent("\(name).png")
    try! png.write(to: url)
    print("wrote \(url.path)")
}

let ok: (String) -> ShellResult = { _ in ShellResult(exitCode: 0, stdout: fixture) }

let list = await makeStore(ok)
render("list", list)
render("min-size-list", list, size: PanelView.minimumSize)
do {
    // Drag the divider to its cap (bottom = 85%) and check list mode still holds together.
    let key = "sprout.terminalFraction"
    let saved = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(0.85, forKey: key)
    render("list-fraction-cap", list)
    if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
}

let empty = await makeStore(ok)
empty.selectProject("bookcast")
render("list-empty-project", empty)

let missing = await makeStore { _ in ShellResult(exitCode: 127) }
render("script-missing", missing)

var failRefresh = false
let erroring = await makeStore { _ in
    failRefresh ? ShellResult(exitCode: 1, stderr: "Error: Projects root '/nope' does not exist.")
                : ShellResult(exitCode: 0, stdout: fixture)
}
failRefresh = true
await erroring.refresh()
render("refresh-error", erroring)

let createOK: (String) -> ShellResult = { command in
    command.contains(" create ")
        ? ShellResult(exitCode: 0, stdout: """
            Created worktree for branch 'feature-invoices'
            Running setup in /Users/mehdi/projects/scooda-worktrees/feature-invoices ...
              → Copying .env from main project
              → Creating database 'scooda_feature_invoices' (clone of 'scooda')
              Warning: mysqldump not found — database created but not populated.
              → Updated .env: REDIS_DB=5, REDIS_CACHE_DB=5
            """)
        : ShellResult(exitCode: 0, stdout: fixture)
}

let creating = await makeStore(createOK)
creating.beginCreate()
render("create-empty", creating)
render("min-size-create", creating, size: PanelView.minimumSize)
await creating.create(branch: "feature/invoices", base: "main", runSetup: true)
render("create-done", creating)

let createFail = await makeStore { command in
    command.contains(" create ")
        ? ShellResult(exitCode: 1, stderr: "Error: Branch 'feature/payments-v2' already exists in 'scooda'.")
        : ShellResult(exitCode: 0, stdout: fixture)
}
createFail.beginCreate()
await createFail.create(branch: "feature/payments-v2", base: "main", runSetup: true)
render("create-failed", createFail)

let deleting = await makeStore(ok)
deleting.beginDelete()
render("delete-dirty", deleting)

let clearing = await makeStore(ok)
clearing.beginClear()
render("clear-confirm", clearing)

let clearFail = await makeStore { command in
    command.contains(" clear ")
        ? ShellResult(
            exitCode: 1,
            stdout: """
                Skipped 'feature-payments-v2' (uncommitted changes — use --force to delete it)
                Deleted worktree 'fix-TICKET-123'

                cleared 1 · skipped 1 · failed 0
                """)
        : ShellResult(exitCode: 0, stdout: fixture)
}
clearFail.beginClear()
if case .clear(let project) = clearFail.mode {
    await clearFail.clear(project, force: false, dropData: true)
}
render("clear-done", clearFail)

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

let withKeys = await makeStore(ok)
withKeys.showingKeys = true
render("keys", withKeys)

let withPalette = await makeStore(ok)
withPalette.palette = "serve "
render("palette", withPalette)
