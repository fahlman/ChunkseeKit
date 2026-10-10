// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ChunkseeKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "ChunkseeKit", targets: ["ChunkseeKit"]),
        .executable(name: "chunksee", targets: ["chunksee"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "ChunkseeKit", dependencies: ["CZlib"]),
        .executableTarget(name: "chunksee", dependencies: ["ChunkseeKit"]),
        .testTarget(name: "ChunkseeKitTests", dependencies: ["ChunkseeKit", "CZlib"]),
    ],
    swiftLanguageModes: [.v6]
)
