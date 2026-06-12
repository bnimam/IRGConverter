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
    ]
)
