// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetoStats",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BetoStats",
            path: "Sources/BetoStats"
        )
    ]
)
