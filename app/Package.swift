// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SproutCore"),
        .target(name: "SproutUI", dependencies: ["SproutCore"]),
        .executableTarget(name: "Sprout", dependencies: ["SproutCore", "SproutUI"]),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore"]),
        .executableTarget(name: "SproutSnapshots", dependencies: ["SproutCore", "SproutUI"]),
    ]
)
