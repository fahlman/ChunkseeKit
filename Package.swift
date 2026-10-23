// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ChunkseeKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "ChunkseeKit", targets: ["ChunkseeKit"]),
        .library(name: "ChunkseeIndex", targets: ["ChunkseeIndex"]),
        .library(name: "ChunkseeKitTestSupport", targets: ["ChunkseeKitTestSupport"]),
        .executable(name: "chunksee", targets: ["chunksee"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "ChunkseeKit", dependencies: ["CZlib"]),
        .target(name: "ChunkseeIndex", dependencies: ["ChunkseeKit"]),
        .target(name: "ChunkseeKitTestSupport", dependencies: ["ChunkseeKit"]),
        .executableTarget(name: "chunksee", dependencies: ["ChunkseeKit", "ChunkseeIndex"]),
        .testTarget(name: "ChunkseeKitTests", dependencies: ["ChunkseeKit", "ChunkseeKitTestSupport", "CZlib"]),
        .testTarget(name: "ChunkseeIndexTests", dependencies: ["ChunkseeIndex", "ChunkseeKit", "ChunkseeKitTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
