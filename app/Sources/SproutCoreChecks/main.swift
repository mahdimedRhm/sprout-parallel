import CheckKit
import Foundation

modelChecks()
await shellChecks()
await cliChecks()
await liveChecks()
await storeChecks()
await actionChecks()

finishChecks()
