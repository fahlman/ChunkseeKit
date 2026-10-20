import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct CLIScanTests {
    @Test func uniformAndPackedStatesMergeByBlockID() throws {
        let root = try world(sections: [
            Fixtures.section(y: 0, palette: [.string("minecraft:oak_log")]),
            Fixtures.section(y: 1, palette: [
                .compound(["id": .string("minecraft:oak_log"), "properties": .compound(["axis": .string("x")])]),
                .compound(["id": .string("minecraft:oak_log"), "properties": .compound(["axis": .string("y")])]),
            ], indices: (0..<4096).map { $0 % 2 }),
            Fixtures.section(y: 2, palette: [.string("minecraft:air"), .string("minecraft:dirt")], indices: (0..<4096).map { $0 % 2 }),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "scan", arguments: ["overworld"])
        #expect(result.status == 0)
        #expect(result.output == """
        minecraft:overworld: 1 chunks, 3 sections, 0 chunks with entities
          8192\tminecraft:oak_log
          2048\tminecraft:air
          2048\tminecraft:dirt

        """)
    }

    @Test func fiveBitPaddingAndCountTiesPreserveTheTopEight() throws {
        let palette = (0..<17).map { NBT.string("minecraft:block_\($0)") }
        let root = try world(sections: [Fixtures.section(y: 0, palette: palette, indices: (0..<4096).map { $0 % 17 }, bits: 5)])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "scan", arguments: ["overworld"])
        #expect(result.status == 0)
        let lines = ["minecraft:overworld: 1 chunks, 1 sections, 0 chunks with entities"] +
            [0, 1, 10, 11, 12, 13, 14, 15].map { "  241\tminecraft:block_\($0)" }
        #expect(result.output == lines.joined(separator: "\n") + "\n")
    }

    @Test func invalidReferencesAreIgnoredAndZeroCountsRemainVisible() throws {
        let root = try world(sections: [Fixtures.section(y: 0, palette: [.string("minecraft:stone"), .string("minecraft:dirt")],
                                                         indices: (0..<4096).map { $0 % 512 == 0 ? 0 : 15 })])
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try Fixtures.runCLI(root, command: "scan", arguments: ["overworld"])
        #expect(result.status == 0)
        #expect(result.output == """
        minecraft:overworld: 1 chunks, 1 sections, 0 chunks with entities
          8\tminecraft:stone
          0\tminecraft:dirt

        """)
    }

    private func world(sections: [NBT]) throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("CLI counts"), "DataVersion": .int(5023)])]),
                                    to: root.appendingPathComponent("level.dat"))
        try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 0,
                                                     nbt: Fixtures.chunk(x: -1, z: 0, dataVersion: 5023, sections: sections))]),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.-1.0.mca"))
        return root
    }
}
