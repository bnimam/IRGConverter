// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IRGConverter",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .target(
            name: "IRGConverterCore",
            dependencies: []
        ),
        .executableTarget(
            name: "IRGConverter",
            dependencies: ["IRGConverterCore"]
        ),
        // Command-line converter, and what the Lightroom plugin drives.
        .executableTarget(
            name: "irgconvert",
            dependencies: ["IRGConverterCore"]
        ),
        // Numeric self-check, runnable without Xcode: `swift run IRGConverterCheck`
        .executableTarget(
            name: "IRGConverterCheck",
            dependencies: ["IRGConverterCore"]
        ),
    ]
)
