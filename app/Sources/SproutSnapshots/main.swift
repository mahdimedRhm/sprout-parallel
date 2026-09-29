import AppKit
import SproutCore
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

let fixture = #"""
{"projects":[
 {"name":"scooda","path":"/Users/mehdi/projects/scooda","branches":["develop","main","production"],"worktrees":[
  {"branch":"feature/payments-v2","folder":"feature-payments-v2","path":"/Users/mehdi/projects/scooda-worktrees/feature-payments-v2","base":"main","changes":3,"ahead":3,"behind":1,"lastCommit":{"hash":"a1f9c2e","subject":"Add Stripe webhook","when":"2 hours ago"},"mysqlDb":"scooda_feature_payments_v2","redisDb":3,"redisPrefix":"scooda_feature_payments_v2_"},
  {"branch":"fix/TICKET-123","folder":"fix-TICKET-123","path":"/Users/mehdi/projects/scooda-worktrees/fix-TICKET-123","base":"main","changes":0,"ahead":1,"behind":0,"lastCommit":{"hash":"77be01d","subject":"Guard null invoice","when":"5 days ago"},"mysqlDb":"scooda_fix_TICKET_123","redisDb":4,"redisPrefix":"scooda_fix_ticket_123_"}
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
func render(_ name: String, _ store: WorktreeStore) {
    let renderer = ImageRenderer(content: PanelView().environmentObject(store))
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
