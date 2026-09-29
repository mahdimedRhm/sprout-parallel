import Foundation

modelChecks()
await shellChecks()
await cliChecks()
await liveChecks()

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
