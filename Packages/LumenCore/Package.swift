// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LumenCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"]),
    ],
    targets: [
        .target(name: "LumenCore"),
        // Debug-only command-line harness for checking the backend against real hardware.
        .executableTarget(name: "lumen-probe", dependencies: ["LumenCore"]),
        .testTarget(name: "LumenCoreTests", dependencies: ["LumenCore"]),
    ]
)
