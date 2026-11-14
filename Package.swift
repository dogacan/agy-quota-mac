// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AntigravityQuota",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgyQuotaCore",
            targets: ["AgyQuotaCore"]
        ),
        .executable(
            name: "AntigravityQuota",
            targets: ["AgyQuotaApp"]
        )
    ],
    targets: [
        .target(
            name: "AgyQuotaCore"
        ),
        .executableTarget(
            name: "AgyQuotaApp",
            dependencies: ["AgyQuotaCore"]
        ),
        .testTarget(
            name: "AgyQuotaCoreTests",
            dependencies: ["AgyQuotaCore"]
        )
    ]
)
