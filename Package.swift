// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BtoStats",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BtoStatsHelperShared",
            path: "Sources/BtoStatsHelperShared"
        ),
        .executableTarget(
            name: "BtoStats",
            dependencies: ["BtoStatsHelperShared"],
            path: "Sources/BtoStats",
            linkerSettings: [.linkedFramework("CoreWLAN")]
        ),
        .executableTarget(
            name: "BtoStatsHelper",
            dependencies: ["BtoStatsHelperShared"],
            path: "Sources/BtoStatsHelper"
        )
    ]
)
