import CheckKit
import Foundation

modelChecks()
await shellChecks()
await cliChecks()
await liveChecks()
await storeChecks()

finishChecks()
