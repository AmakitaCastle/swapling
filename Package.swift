// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swapling",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "IslandCore",
            path: "Sources/IslandCore"
        ),
        .executableTarget(
            name: "Swapling",
            dependencies: ["IslandCore"],
            path: "Sources/Swapling"
        ),
        .testTarget(
            name: "IslandCoreTests",
            dependencies: ["IslandCore"],
            path: "Tests/IslandCoreTests"
        ),
    ]
)
