// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RuterWidget",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RuterWidget",
            targets: ["RuterWidget"]
        ),
    ],
    dependencies: [
        // No external dependencies needed - using native frameworks
    ],
    targets: [
        .executableTarget(
            name: "RuterWidget",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
