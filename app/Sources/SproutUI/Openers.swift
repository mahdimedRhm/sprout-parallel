import AppKit

public enum Openers {
    /// When set, openers report `"<app>:<target>"` here instead of launching
    /// anything (used by the key checks).
    @MainActor public static var intercept: ((String) -> Void)?

    @MainActor
    public static func vscode(_ path: String) {
        if let intercept { return intercept("vscode:\(path)") }
        open(["-a", "Visual Studio Code", path])
    }

    @MainActor
    public static func warp(_ path: String) {
        if let intercept { return intercept("warp:\(path)") }
        open(["-a", "Warp", path])
    }

    @MainActor
    public static func browser(_ url: String) {
        if let intercept { return intercept("browser:\(url)") }
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    public static func finder(_ path: String) {
        if let intercept { return intercept("finder:\(path)") }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }
}
