import Foundation
import SproutCore

func modelChecks() {
    guard let status = try? Status.decode(Data(statusFixture.utf8)) else {
        check(false, "fixture decodes")
        return
    }
    checkEqual(status.projects.map(\.name), ["scooda", "prayercal"], "decodes projects in order")

    let wt = status.projects[0].worktrees[0]
    checkEqual(wt.branch, "feature/payments-v2", "decodes branch")
    checkEqual(wt.id, wt.path, "worktree id is its path")
    checkEqual(wt.ahead, 3, "decodes ahead")
    checkEqual(wt.behind, 1, "decodes behind")
    checkEqual(wt.redisDb, 3, "decodes redisDb as Int")
    checkEqual(wt.lastCommit?.subject, "Say \"hi\" \\ ok", "decodes escaped subject")
    checkEqual(wt.lastCommit?.hash, "a1f9c2e", "decodes hash")
    check(wt.isDirty, "changes > 0 is dirty")
    checkEqual(wt.herdUrl, "https://scooda-feature-payments-v2.test", "decodes herdUrl")
    checkEqual(wt.serveUrl, "http://127.0.0.1:8003", "decodes serveUrl")
    check(wt.isServing, "serveRunning true is serving")

    let bare = status.projects[0].worktrees[1]
    check(bare.ahead == nil && bare.behind == nil, "null sync decodes as nil")
    check(bare.lastCommit == nil && bare.mysqlDb == nil, "null commit and db decode as nil")
    check(bare.redisDb == nil && bare.redisPrefix == nil, "null redis decodes as nil")
    check(!bare.isDirty, "changes == 0 is clean")
    check(bare.herdUrl == nil && bare.serveUrl == nil && !bare.isServing, "missing URL fields decode as nil / not serving")

    checkEqual(status.projects[1].worktrees.count, 0, "project without worktrees")
    checkEqual(status.projects[1].id, "prayercal", "project id is its name")
    check((try? Status.decode(Data("not json".utf8))) == nil, "invalid JSON throws")
    check((try? Status.decode(Data(statusJSON(["feature/a"]).utf8))) != nil, "statusJSON helper decodes")
}
