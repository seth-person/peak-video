// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Peak",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Peak", targets: ["Peak"])],
    targets: [
        .target(name: "PeakCore"),
        .executableTarget(name: "Peak", dependencies: ["PeakCore"]),
        .executableTarget(name: "PeakCoreChecks", dependencies: ["PeakCore"], path: "Tests/PeakCoreTests")
    ]
)
