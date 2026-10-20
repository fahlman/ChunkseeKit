import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct BlockEntityTests {
    @Test func savedOrderAndUnavailableFieldsSurviveTypedDecoding() throws {
        let raw = Fixtures.chunk(x: -1, z: -2, sections: [], extra: ["block_entities": .list([
            .compound(["id": .string("custom:unfamiliar"), "x": .int(-9), "y": .int(-64), "z": .int(-17)]),
            .compound(["id": .string("minecraft:chest"), "x": .int(-8), "y": .double(64), "z": .int(-17)]),
            .compound(["id": .int(1), "x": .int(-8), "y": .int(64), "z": .int(-17)]),
            .compound([:]),
        ])])
        let chunk = try Chunk(nbt: NBT.read(raw.serialized()).value)
        #expect(chunk.blockEntities.map(\.id) == ["custom:unfamiliar", "minecraft:chest", nil, nil])
        #expect(chunk.blockEntities.map(\.position) == [
            BlockPosition(blockX: -9, blockY: -64, blockZ: -17), nil,
            BlockPosition(blockX: -8, blockY: 64, blockZ: -17), nil,
        ])
        #expect(chunk.blockEntity(x: 7, y: -64, z: 15) == chunk.blockEntities[0])
        #expect(chunk.blockEntity(x: -9, y: -64, z: -17) == chunk.blockEntities[0])
        // An unreadable Y cannot shadow the following record or invent a position.
        #expect(chunk.blockEntity(x: 8, y: 64, z: 15) == chunk.blockEntities[2])
        #expect(chunk.blockEntity(x: 7, y: 0, z: 15) == nil)

        let absent = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: []))
        #expect(absent.blockEntities.isEmpty)
        let malformed = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [], extra: [
            "block_entities": .list([.string("unreadable entry")]),
        ]))
        #expect(malformed.blockEntities.count == 1)
        #expect(malformed.blockEntities[0].id == nil && malformed.blockEntities[0].position == nil)
    }

    @Test func firstMatchingRecordAndIntegerEdgesKeepTheirLookupSemantics() throws {
        let first: NBT = .compound(["x": .long(Int64.min), "y": .long(Int64.max), "z": .long(Int64.max)])
        var later = first.compound!
        later["id"] = .string("minecraft:chest")
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [], extra: [
            "block_entities": .list([first, .compound(later)]),
        ]))
        let found = try #require(chunk.blockEntity(x: Int.min, y: Int.max, z: Int.max))
        #expect(found.id == nil)
        #expect(found.position == BlockPosition(blockX: Int.min, blockY: Int.max, blockZ: Int.max))
        #expect(chunk.blockEntity(x: 0, y: Int.max, z: 15) == found)
        #expect(chunk.blockEntity(x: 0, y: Int.min, z: 15) == nil)
    }

    @Test func terrainCommandsKeepCountsAndKnownOrUnknownIDs() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Typed block entities"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        let chunk = Fixtures.chunk(x: -1, z: -1, sections: [], extra: ["block_entities": .list([
            .compound(["id": .string("custom:storage"), "x": .int(-9), "y": .int(64), "z": .int(-1)]),
            .compound(["x": .int(-8), "y": .int(64), "z": .int(-1)]),
            .compound(["id": .string("minecraft:chest")]),
        ])])
        try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 31, nbt: chunk)]),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.-1.-1.mca"))
        let count = try Fixtures.runCLI(root, command: "chunk", arguments: ["-1", "-1"])
        #expect(count.status == 0 && count.output.contains("Block entities: 3\n"))
        for (x, expected) in [("-9", "Block entity: custom:storage\n"), ("-8", "Block entity: ?\n")] {
            let result = try Fixtures.runCLI(root, command: "block", arguments: [x, "64", "-1"])
            #expect(result.status == 0 && result.output.contains(expected))
        }
        let absent = try Fixtures.runCLI(root, command: "block", arguments: ["-7", "64", "-1"])
        #expect(absent.status == 0 && !absent.output.contains("Block entity:"))
    }
}
