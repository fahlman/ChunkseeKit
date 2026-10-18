import Foundation
import Testing
import ChunkseeKit

@Suite struct DimensionLookupTests {
    @Test func invalidArgumentUsesTheNormalCLIErrorInsteadOfTrapping() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "chunk", arguments: ["0", "0", "minecraft:"])
        #expect(result.status == 1)
        #expect(result.output == "no such dimension: minecraft:\n")
    }

    @Test func emptyLookupComponentsReturnNil() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try World(contentsOf: root)
        for id in ["", ":", "minecraft:", ":overworld", "::"] { #expect(saved.dimension(id) == nil) }
        #expect(saved.dimension("example:missing") == nil)
    }

    @Test func shorthandNestedPathsAndLegacyDimensionsKeepTheirLocations() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["DIM-1/region", "DIM1/region", "dimensions/example/deep/mines/region"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let saved = try World(contentsOf: root)
        #expect(saved.dimension("overworld")?.id == "minecraft:overworld")
        #expect(saved.dimension("minecraft:overworld")?.url == root)
        #expect(saved.dimension("the_nether")?.url == root.appendingPathComponent("DIM-1"))
        #expect(saved.dimension("the_end")?.url == root.appendingPathComponent("DIM1"))
        #expect(saved.dimension("example:deep/mines")?.url == root.appendingPathComponent("dimensions/example/deep/mines"))
        let validCLI = try Fixtures.runCLI(root, command: "chunk", arguments: ["0", "0", "overworld"])
        #expect(validCLI.status == 1 && validCLI.output == "chunk 0, 0 not generated\n")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/overworld/region"), withIntermediateDirectories: true)
        #expect(try World(contentsOf: root).dimension("overworld")?.url == root.appendingPathComponent("dimensions/minecraft/overworld"))
    }

    private func world() throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Dimension lookup"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        return root
    }
}
