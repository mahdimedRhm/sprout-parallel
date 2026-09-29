import Foundation
import SproutCore

func cliChecks() async {
    checkEqual(
        SproutCLI.createCommand(project: "scooda", branch: "feature/x", base: "main", runSetup: true),
        "sprout-parallel create feature/x --project scooda --from main",
        "create command")
    checkEqual(
        SproutCLI.createCommand(project: "scooda", branch: "feature/x", base: "develop", runSetup: false),
        "sprout-parallel create feature/x --project scooda --from develop --no-setup",
        "create command without setup")
    checkEqual(
        SproutCLI.createCommand(project: "my proj", branch: "it's", base: "main", runSetup: true),
        "sprout-parallel create 'it'\\''s' --project 'my proj' --from main",
        "create command quotes arguments")

    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: false, keepData: false),
        "sprout-parallel delete feature-x --project scooda", "delete command")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: true, keepData: false),
        "sprout-parallel delete feature-x --project scooda --force", "delete --force")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: false, keepData: true),
        "sprout-parallel delete feature-x --project scooda --keep-db", "delete --keep-db")
    checkEqual(
        SproutCLI.deleteCommand(project: "scooda", folder: "feature-x", force: true, keepData: true),
        "sprout-parallel delete feature-x --project scooda --force --keep-db", "delete both flags")

    checkEqual(SproutCLI.folderName(for: "feature/my-thing"), "feature-my-thing", "folder name")
    checkEqual(SproutCLI.folderName(for: "/x/"), "x", "folder name trims edge dashes")

    checkEqual(SproutCLI.validateBranch("feature/ok-1"), nil, "valid branch")
    check(SproutCLI.validateBranch("") != nil, "empty branch rejected")
    check(SproutCLI.validateBranch("-rf") != nil, "leading dash rejected")
    check(SproutCLI.validateBranch("has space") != nil, "space rejected")
    check(SproutCLI.validateBranch("a..b") != nil, "double dot rejected")
    check(SproutCLI.validateBranch("trailing/") != nil, "trailing slash rejected")
    check(SproutCLI.validateBranch("x.lock") != nil, ".lock suffix rejected")
    check(SproutCLI.validateBranch("quo\"te") != nil, "quote rejected")

    // status()
    let banner = FakeShell { _ in ShellResult(exitCode: 0, stdout: "Welcome to zsh!\n" + statusJSON(["feature/a"]) + "\n") }
    let status = try? await SproutCLI(shell: banner).status()
    checkEqual(status?.projects.first?.worktrees.first?.branch, "feature/a", "status ignores login-shell banner")
    let escaped = FakeShell { _ in ShellResult(exitCode: 0, stdout: "\u{1B}]0;title\u{07}" + statusJSON(["feature/a"]) + "\n") }
    let escStatus = try? await SproutCLI(shell: escaped).status()
    checkEqual(escStatus?.projects.first?.worktrees.first?.branch, "feature/a", "status ignores escape sequence before JSON")
    checkEqual(banner.commands, ["sprout-parallel status --json"], "status runs the status command")

    await expectError(ShellResult(exitCode: 127, stderr: "zsh: command not found: sprout-parallel"),
                      .notFound, "exit 127 means script not found")
    await expectError(ShellResult(exitCode: 1, stderr: "Error: Projects root '/x' does not exist.\n"),
                      .failed("Error: Projects root '/x' does not exist."), "status failure carries Error: line")
    let garbage = FakeShell { _ in ShellResult(exitCode: 0, stdout: "garbage") }
    do {
        _ = try await SproutCLI(shell: garbage).status()
        check(false, "non-JSON output throws")
    } catch let error as CLIError {
        if case .badOutput = error { check(true, "non-JSON output throws badOutput") }
        else { check(false, "non-JSON output throws badOutput, got \(error)") }
    } catch {
        check(false, "non-JSON output throws CLIError")
    }

    // run()
    let failing = FakeShell { _ in
        ShellResult(exitCode: 1, stdout: "Preparing…\n", stderr: "Error: Branch 'x' already exists in 'scooda'.\n")
    }
    let box = LinesBox()
    do {
        try await SproutCLI(shell: failing).run("sprout-parallel create x --project scooda --from main") { box.append($0) }
        check(false, "failed run throws")
    } catch let error as CLIError {
        checkEqual(error, .failed("Error: Branch 'x' already exists in 'scooda'."), "run failure carries Error: line")
    } catch {
        check(false, "run throws CLIError")
    }
    checkEqual(box.lines, ["Preparing…", "Error: Branch 'x' already exists in 'scooda'."], "run streams lines")

    let noErrorLine = FakeShell { _ in ShellResult(exitCode: 2, stdout: "", stderr: "fatal: bad thing\n") }
    do {
        try await SproutCLI(shell: noErrorLine).run("x") { _ in }
    } catch let error as CLIError {
        checkEqual(error.message, "fatal: bad thing", "falls back to last non-empty line")
    } catch {
        check(false, "run throws CLIError")
    }
    checkEqual(CLIError.notFound.message, "sprout-parallel not found — run install.sh", "notFound message")
}

private func expectError(_ result: ShellResult, _ expected: CLIError, _ name: String) async {
    let shell = FakeShell { _ in result }
    do {
        _ = try await SproutCLI(shell: shell).status()
        check(false, name)
    } catch let error as CLIError {
        checkEqual(error, expected, name)
    } catch {
        check(false, "\(name): unexpected \(error)")
    }
}
