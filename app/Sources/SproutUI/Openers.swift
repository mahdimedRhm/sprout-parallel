import AppKit

public enum Openers {
    public static func vscode(_ path: String) {
        open(["-a", "Visual Studio Code", path])
    }

    public static func warp(_ path: String) {
        open(["-a", "Warp", path])
    }

    public static func browser(_ url: String) {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }

    public static func finder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }
}
