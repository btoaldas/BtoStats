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
        .target(
            name: "CIOReport",
            path: "Sources/CIOReport"
        ),
        .executableTarget(
            name: "BtoStats",
            dependencies: ["BtoStatsHelperShared", "CIOReport"],
            path: "Sources/BtoStats",
            linkerSettings: [.linkedFramework("CoreWLAN"),
                             .linkedFramework("IOKit"),
                             .unsafeFlags(["-lIOReport"])]
        ),
        .executableTarget(
            name: "BtoStatsHelper",
            dependencies: ["BtoStatsHelperShared"],
            path: "Sources/BtoStatsHelper"
        )
    ]
)
