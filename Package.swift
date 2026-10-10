// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCWorldKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MCWorldKit", targets: ["MCWorldKit"]),
        .executable(name: "mcworld", targets: ["mcworld"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "MCWorldKit", dependencies: ["CZlib"]),
        .executableTarget(name: "mcworld", dependencies: ["MCWorldKit"]),
        .testTarget(name: "MCWorldKitTests", dependencies: ["MCWorldKit", "CZlib"]),
    ]
)
