import Foundation

/// Hand-written `status --json` output covering every field shape.
let statusFixture = #"""
{"projects":[
 {"name":"scooda","path":"/Users/me/projects/scooda","branches":["develop","main"],"worktrees":[
  {"branch":"feature/payments-v2","folder":"feature-payments-v2","path":"/Users/me/projects/scooda-worktrees/feature-payments-v2","base":"main","changes":3,"ahead":3,"behind":1,"lastCommit":{"hash":"a1f9c2e","subject":"Say \"hi\" \\ ok","when":"2 hours ago"},"mysqlDb":"scooda_feature_payments_v2","redisDb":3,"redisPrefix":"scooda_feature_payments_v2_","herdUrl":"https://scooda-feature-payments-v2.test","serveUrl":"http://127.0.0.1:8003","serveRunning":true},
  {"branch":"HEAD","folder":"detached","path":"/Users/me/projects/scooda-worktrees/detached","base":"main","changes":0,"ahead":null,"behind":null,"lastCommit":null,"mysqlDb":null,"redisDb":null,"redisPrefix":null}
 ]},
 {"name":"prayercal","path":"/Users/me/projects/prayercal","branches":["main"],"worktrees":[]}
]}
"""#

/// Single-line status JSON with project "scooda" holding one clean worktree per
/// branch, plus an empty project "prayercal".
func statusJSON(_ branches: [String]) -> String {
    let worktrees = branches.map { branch -> String in
        let folder = branch.replacingOccurrences(of: "/", with: "-")
        return #"{"branch":"\#(branch)","folder":"\#(folder)","path":"/p/scooda-worktrees/\#(folder)","base":"main","changes":0,"ahead":0,"behind":0,"lastCommit":null,"mysqlDb":null,"redisDb":null,"redisPrefix":null}"#
    }.joined(separator: ",")
    return #"{"projects":[{"name":"scooda","path":"/p/scooda","branches":["main"],"worktrees":[\#(worktrees)]},{"name":"prayercal","path":"/p/prayercal","branches":["main"],"worktrees":[]}]}"#
}
