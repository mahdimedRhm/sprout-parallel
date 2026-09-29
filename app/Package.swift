// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sprout",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SproutCore"),
        .executableTarget(name: "SproutCoreChecks", dependencies: ["SproutCore"]),
    ]
)
