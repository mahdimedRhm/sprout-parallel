import SproutCore
import SproutUI
import SwiftUI

@main
struct SproutApp: App {
    @StateObject private var store = WorktreeStore(cli: SproutCLI(shell: LoginShell()))

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            Image(systemName: "leaf.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
