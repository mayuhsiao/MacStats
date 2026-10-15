// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacStats",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacStats",
            path: "Sources/MacStats"
        )
    ]
)
