import CheckKit
import Foundation

modelChecks()
ownDatabaseChecks()
await shellChecks()
await cliChecks()
await liveChecks()
await storeChecks()
await actionChecks()

finishChecks()
