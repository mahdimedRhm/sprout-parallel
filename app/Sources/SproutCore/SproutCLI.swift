import Foundation

public enum CLIError: Error, Equatable {
    case notFound
    case failed(String)
    case badOutput(String)

    public var message: String {
        switch self {
        case .notFound: "sprout-parallel not found — run install.sh"
        case .failed(let message), .badOutput(let message): message
        }
    }
}

/// Builds and runs `sprout-parallel` commands.
public struct SproutCLI {
    public let shell: Shell

    public init(shell: Shell) {
        self.shell = shell
    }

    public static let statusCommand = "sprout-parallel status --json"

    public static func createCommand(project: String, branch: String, base: String, runSetup: Bool) -> String {
        var parts = ["sprout-parallel", "create", shellQuote(branch),
                     "--project", shellQuote(project), "--from", shellQuote(base)]
        if !runSetup { parts.append("--no-setup") }
        return parts.joined(separator: " ")
    }

    /// `folder` is the worktree folder name; the script's safe_name() maps it
    /// to itself, so this also works for detached-HEAD worktrees.
    public static func deleteCommand(project: String, folder: String, force: Bool, keepData: Bool) -> String {
        var parts = ["sprout-parallel", "delete", shellQuote(folder), "--project", shellQuote(project)]
        if force { parts.append("--force") }
        if keepData { parts.append("--keep-db") }
        return parts.joined(separator: " ")
    }

    /// Mirrors the script's safe_name(): `feature/x` → `feature-x`.
    public static func folderName(for branch: String) -> String {
        var name = branch.replacingOccurrences(of: "/", with: "-")
        if name.hasPrefix("-") { name.removeFirst() }
        if name.hasSuffix("-") { name.removeLast() }
        return name
    }

    /// Returns why `branch` can't be used, or nil if it's fine.
    public static func validateBranch(_ branch: String) -> String? {
        if branch.isEmpty { return "branch name required" }
        if branch.hasPrefix("-") { return "branch can't start with '-'" }
        if branch.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return "branch can't contain spaces" }
        let forbidden = CharacterSet(charactersIn: "\"'`$\\~^:?*[")
        if branch.rangeOfCharacter(from: forbidden) != nil { return "branch contains a character git doesn't allow" }
        if branch.contains("..") || branch.hasSuffix("/") || branch.hasSuffix(".lock") {
            return "not a valid git branch name"
        }
        return nil
    }

    public func status() async throws -> Status {
        let result = await shell.run(Self.statusCommand) { _ in }
        try Self.throwIfFailed(result)
        // Interactive login shells may print banners or escape sequences, even on the
        // same line: take the last line containing the JSON start and cut from there.
        guard let line = result.stdout.split(separator: "\n").last(where: { $0.contains("{\"projects\":") }),
              let start = line.range(of: "{\"projects\":") else {
            throw CLIError.badOutput("no JSON in status output")
        }
        let json = line[start.lowerBound...]
        do {
            return try Status.decode(Data(json.utf8))
        } catch {
            throw CLIError.badOutput("could not read status JSON: \(error.localizedDescription)")
        }
    }

    public func run(_ command: String, onLine: @escaping (String) -> Void) async throws {
        let result = await shell.run(command, onLine: onLine)
        try Self.throwIfFailed(result)
    }

    private static func throwIfFailed(_ result: ShellResult) throws {
        if result.exitCode == 127 { throw CLIError.notFound }
        guard result.exitCode == 0 else { throw CLIError.failed(errorLine(result)) }
    }

    private static func errorLine(_ result: ShellResult) -> String {
        let lines = (result.stderr + "\n" + result.stdout).split(separator: "\n").map(String.init)
        if let error = lines.last(where: { $0.hasPrefix("Error:") }) { return error }
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "exited with code \(result.exitCode)"
    }
}
