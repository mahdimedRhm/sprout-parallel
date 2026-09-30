// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        .target(name: "SproutCore"),
        .target(name: "SproutTerminal", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .target(name: "SproutUI", dependencies: ["SproutCore", "SproutTerminal"]),
        .target(name: "CheckKit"),
        .executableTarget(name: "Sprout", dependencies: ["SproutCore", "SproutUI", "SproutTerminal"]),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore", "CheckKit"]),
        .executableTarget(name: "SproutTerminalChecks", dependencies: ["SproutTerminal", "CheckKit"]),
        .executableTarget(name: "SproutSnapshots", dependencies: ["SproutCore", "SproutUI", "SproutTerminal"]),
    ]
)
