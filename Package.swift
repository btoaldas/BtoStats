// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BtoStats",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BtoStats",
            path: "Sources/BtoStats",
            linkerSettings: [.linkedFramework("CoreWLAN")]
        )
    ]
)
