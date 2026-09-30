import AppKit
import CheckKit

_ = NSApplication.shared

// sessionChecks() is synchronous; assumeIsolated is unavailable directly in
// top-level (async) code, so wrap it in a plain function.
func runSessionChecks() {
    MainActor.assumeIsolated { sessionChecks() }
}

runSessionChecks()
await shellChecks()

finishChecks()
