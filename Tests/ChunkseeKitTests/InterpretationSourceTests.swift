import CryptoKit
import Foundation
import Testing
@testable import ChunkseeKit

/// Output fixtures cannot exercise every reader path. Source changes therefore also
/// require an explicit review of the cache contract, including unchanged meaning.
@Suite struct InterpretationSourceTests {
    @Test func regionFactsSourceHasAReviewedContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = try sourceFiles(at: root)
        let digest = try InterpretationKey.identity(of: files)
        let version = RegionFacts.interpretationVersion
        #expect(reviewedSources[version]?.contains(digest) == true,
                "Region-facts source changed; review its complete cache contract. Source SHA-256: \(digest)")
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
        // Published source 30e2b22861a92da0fed92aa518340d617b850da9.
        return [regionFacts: ["c05630d57eee90a0d9d3ae21a7469f1207d793fa99b4762f9258fa665fa94cd0"]]
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
                    includingPropertiesForKeys: Array(keys)) {
                    try include(child)
                }
            } else {
                try #require(values.isRegularFile == true && url.path.hasPrefix(root.path + "/"))
                let relative = String(url.path.dropFirst(root.path.count + 1))
                let data = try Data(contentsOf: url)
                files[relative] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }

        // Cover complete current dependency roots, including generated sources. This
        // intentionally requests review for unrelated core edits instead of keeping a
        // field or file allowlist that could miss the next cached reader.
        try include(root.appendingPathComponent("Package.swift"))
        try include(root.appendingPathComponent("Sources/ChunkseeKit", isDirectory: true))
        try include(root.appendingPathComponent("Sources/CZlib", isDirectory: true))
        try #require(!files.isEmpty)
        return files
    }
}
