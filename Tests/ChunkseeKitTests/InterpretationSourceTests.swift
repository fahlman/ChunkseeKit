import CryptoKit
import Foundation
import Testing
@testable import ChunkseeKit

/// Output fixtures cannot exercise every reader path. Source changes therefore also
/// require an explicit review of the cache contract, including unchanged meaning.
@Suite struct InterpretationSourceTests {
    @Test(arguments: [RegionFacts.interpretationVersion, RegionBlockCounts.interpretationVersion])
    func cachedReaderSourceHasAReviewedContract(version: InterpretationVersion) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = try sourceFiles(at: root)
        let digest = try InterpretationKey.identity(of: files)
        #expect(reviewedSources[version]?.contains(digest) == true,
                """
                Review the complete \(version.domain) contract and add its reviewed source fingerprint,
                including after a revision bump. Source SHA-256: \(digest)
                """)
    }

    /// Keep earlier snapshots. A source-only refactor can keep the contract only after
    /// review establishes unchanged meaning; a reader change still needs its revision.
    private var reviewedSources: [InterpretationVersion: Set<String>] {
        let terrain = InterpretationVersion(domain: "terrain", revision: 2,
            generatedFacts: "ecf3d4cb262728a6dc1418c48cb262fa32d4415dcdb64287ea520c87ba1b8702",
            dependencies: [])
        let regionFacts = InterpretationVersion(domain: "regionFacts", revision: 33,
            generatedFacts: "6afb63a4e924041cd0ea6d94cd632680b32fa2cae558224f66fe6d62ac54b287",
            dependencies: [terrain])
        let regionFacts34 = InterpretationVersion(domain: "regionFacts", revision: 34,
            generatedFacts: "5c5168ccdb0d4407fc19f2e7decc7178dd453dd4a3327b4136e9bf2a44c99574",
            dependencies: [terrain])
        let regionFacts35 = InterpretationVersion(domain: "regionFacts", revision: 35,
            generatedFacts: "5c5168ccdb0d4407fc19f2e7decc7178dd453dd4a3327b4136e9bf2a44c99574",
            dependencies: [terrain])
        let regionFacts36 = InterpretationVersion(domain: "regionFacts", revision: 36,
            generatedFacts: "5c5168ccdb0d4407fc19f2e7decc7178dd453dd4a3327b4136e9bf2a44c99574",
            dependencies: [terrain])
        let blockCounts1 = InterpretationVersion(domain: "blockCounts", revision: 1,
            generatedFacts: "", dependencies: [terrain])
        return [
            // Published source 30e2b22861a92da0fed92aa518340d617b850da9.
            regionFacts: ["c05630d57eee90a0d9d3ae21a7469f1207d793fa99b4762f9258fa665fa94cd0"],
            // Published source 4b8e4b9795e0e71a785a4f25b58786af23d0b2fc.
            regionFacts34: ["3ed0c074b4ef384408d82044c2e8f2de72d54093d8c48f7b485584e61c4cd004"],
            // Source a36a7d6a1e307ae2d9aa45a855938736f7f160d0 and the documentation-only F574
            // correction, independently reviewed on #357. Both retain the revision-35 contract.
            regionFacts35: [
                "438ed31afd03de0227db610f9a4cc37c1cadb9ca65ca44c97e979d05626566e7",
                "ac0b6d32689f5780001382fffea3b7ebbb8ae5cba77e6e909ed7e991b07f0bc9",
            ],
            // Both contracts independently approved at 68844db on #359/6919625016.
            // Folder-discovery status at f67a0dd changes neither cached output; both contracts
            // independently approved on #363/6923420688, with the fingerprint reproduced.
            // Declaration cleanup at 7af4586 changes neither cached output; both contracts
            // independently approved on #360/6931158790.
            regionFacts36: [
                "f7bd5746857c071c6c30aabb2574a16f3dec37eaa23b9d8cf8f2d16fa0e8d704",
                "1afee1b98ad4077e0632b43c7761dd5cf8b9a77474a41033319e475e3af6f1da",
                "57fe841781d121f9c5f5c10ec32b85476d0d2f976e2854e531fc948a718f79f7",
            ],
            blockCounts1: [
                "f7bd5746857c071c6c30aabb2574a16f3dec37eaa23b9d8cf8f2d16fa0e8d704",
                "1afee1b98ad4077e0632b43c7761dd5cf8b9a77474a41033319e475e3af6f1da",
                "57fe841781d121f9c5f5c10ec32b85476d0d2f976e2854e531fc948a718f79f7",
            ],
        ]
    }

    private func sourceFiles(at root: URL) throws -> [String: String] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var files: [String: String] = [:]

        func include(_ url: URL) throws {
            let values = try url.resourceValues(forKeys: keys)
            try #require(values.isSymbolicLink == false)
            if values.isDirectory == true {
                for child in try manager.contentsOfDirectory(at: url,
                    includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) {
                    try include(child)
                }
            } else {
                try #require(values.isRegularFile == true && url.path.hasPrefix(root.path + "/"))
                let relative = String(url.path.dropFirst(root.path.count + 1))
                let data = try Data(contentsOf: url)
                files[relative] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }

        // Cover complete current dependency roots for both contracts, including generated sources.
        // Each core edit requires a decision for regionFacts and blockCounts independently,
        // even when the same digest witnesses both. This requests review instead of keeping a
        // field or file allowlist that could miss the next cached reader.
        try include(root.appendingPathComponent("Package.swift"))
        try include(root.appendingPathComponent("Sources/ChunkseeKit", isDirectory: true))
        try include(root.appendingPathComponent("Sources/CZlib", isDirectory: true))
        try #require(!files.isEmpty)
        return files
    }
}
