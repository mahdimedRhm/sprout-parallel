import ServiceManagement
import SwiftUI

struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var failed = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(enabled ? "[x]" : "[ ]").foregroundStyle(enabled ? Theme.green : Theme.muted)
                Text("login").foregroundStyle(failed ? Theme.red : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .help(failed ? "couldn't change the login item — is Sprout in ~/Applications?" : "launch at login")
    }

    private func toggle() {
        do {
            if enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            failed = false
        } catch {
            failed = true
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
