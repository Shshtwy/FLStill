// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FLStill",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FLStill"
        ),
    ]
)
