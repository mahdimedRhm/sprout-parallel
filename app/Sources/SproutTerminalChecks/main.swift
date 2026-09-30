import AppKit
import CheckKit

_ = NSApplication.shared

MainActor.assumeIsolated { sessionChecks() }

finishChecks()
