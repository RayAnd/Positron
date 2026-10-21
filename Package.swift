// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Positron",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PositronCore", targets: ["PositronCore"]),
        .executable(name: "positron", targets: ["PositronCLI"]),
        .executable(name: "PositronApp", targets: ["PositronApp"])
    ],
    targets: [
        .target(
            name: "PositronCore",
            path: "Sources/PositronCore"
        ),
        .executableTarget(
            name: "PositronCLI",
            dependencies: ["PositronCore"],
            path: "Sources/PositronCLI"
        ),
        .executableTarget(
            name: "PositronApp",
            dependencies: ["PositronCore"],
            path: "Sources/PositronApp"
        ),
        .testTarget(
            name: "PositronCoreTests",
            dependencies: ["PositronCore"],
            path: "Tests/PositronCoreTests"
        )
    ]
)