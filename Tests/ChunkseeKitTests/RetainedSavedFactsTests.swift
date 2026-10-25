import Foundation
import Testing
import ChunkseeKit
import ChunkseeKitTestSupport

@Suite struct RetainedSavedFactsTests {
    private func item(_ id: String, _ count: Int32 = 1) -> NBT {
        .compound(["id": .string(id), "count": .int(count)])
    }

    @Test func modernChunksUseTheirStructureWithAnyOrNoVersionLabel() throws {
        for version in [nil, 1, 5023, 999999] as [Int32?] {
            var fields = try #require(Fixtures.chunk(x: -1, z: 2, sections: [
                Fixtures.section(y: 0, palette: [.string("example:stone")]),
            ]).compound)
            fields["DataVersion"] = version.map(NBT.int)
            let chunk = try Chunk(nbt: .compound(fields))
            #expect(chunk.dataVersion == version.map(Int.init))
            #expect(chunk.x == -1 && chunk.z == 2)
            #expect(chunk.block(x: 0, y: 0, z: 0)?.id == "example:stone")
            fields["Level"] = .compound(["Sections": .list(.compound, [])])
            #expect(throws: ChunkError.unsupportedLegacyFormat(dataVersion: version.map(Int.init))) {
                try Chunk(nbt: .compound(fields))
            }
        }
    }

    @Test func signTextUsesSavedFieldsInsteadOfTheTypeName() throws {
        let place: [String: NBT] = ["id": .string("example:notice_board"), "x": .int(1), "y": .int(2), "z": .int(3)]
        for fields in [["front_text": NBT.compound(["messages": .list([.string("Modern")])])],
                       ["back_text": .compound(["messages": .list([.string("Back")])])],
                       ["Text1": .string("Legacy")]] {
            let sign = try #require(Sign(blockEntity: .compound(place.merging(fields) { $1 })))
            #expect(sign.kind == "example:notice_board" && sign.hasText)
        }
        #expect(Sign(blockEntity: .compound(place)) == nil)
        #expect(Sign(blockEntity: .compound(place.merging(["front_text": .int(1)]) { $1 })) == nil)
    }

    @Test func equipmentRetainsEverySavedSlotAndCurrentFieldsWinOverLegacy() throws {
        let equipment = NBT.compound(["head": item("minecraft:iron_helmet"), "example:back": item("example:pack")])
        let player = PlayerInfo(uuid: UUID(), nbt: .compound(["equipment": equipment]))
        #expect(player.equipment.mapValues(\.id) == ["head": "minecraft:iron_helmet", "example:back": "example:pack"])
        var fields: [String: NBT] = ["id": .string("minecraft:wolf"), "Pos": .list([.double(1), .double(2), .double(3)]),
                                    "Owner": .string(UUID().uuidString), "equipment": equipment,
                                    "ArmorItems": .list([item("minecraft:diamond_boots")])]
        let creature = try #require(Creature(Fixtures.mob(fields)))
        #expect(creature.equipment?.mapValues(\.id) == player.equipment.mapValues(\.id))
        fields["equipment"] = .compound([:])
        #expect(Creature(Fixtures.mob(fields))?.equipment?.isEmpty == true)
    }

    @Test func sharedScanAndCacheKeepCustomTextSpawnersInventoriesAndEquipment() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Retained saved facts"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        var terrain = try #require(Fixtures.chunk(x: 0, z: 0, sections: [], extra: [
            "block_entities": .list([
                .compound(["id": .string("example:notice_board"), "x": .int(1), "y": .int(64), "z": .int(1),
                           "front_text": .compound(["messages": .list([.string("Kept")])])]),
                .compound(["id": .string("example:generator"), "x": .int(2), "y": .int(64), "z": .int(1),
                           "SpawnData": .compound(["entity": .compound(["id": .string("example:visitor")])])]),
            ]),
        ]).compound)
        terrain["DataVersion"] = nil
        let position = NBT.list([.double(1), .double(64), .double(2)])
        let entities = NBT.compound(["Entities": .list([
            .compound(["id": .string("minecraft:item_display"), "Pos": position, "item": item("minecraft:diamond", 2)]),
            .compound(["id": .string("minecraft:armor_stand"), "Pos": position,
                       "equipment": .compound(["feet": item("minecraft:iron_boots")])]),
            .compound(["id": .string("example:carrier"), "Pos": position,
                       "Inventory": .list([item("minecraft:bread", 3)]),
                       "equipment": .compound(["example:back": item("minecraft:torch", 4)])]),
        ])])
        let region = RegionPosition(x: 0, z: 0)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound(terrain))]),
                           to: dimension.regionURL(.terrain, at: region))
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: entities)]),
                           to: dimension.regionURL(.entities, at: region))
        let facts = try dimension.scan(region: region)
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 0)
        #expect(facts.signs.first?.front == ["Kept"])
        #expect(facts.spawners == [Spawner(x: 2, y: 64, z: 1, mob: "example:visitor")])
        #expect(facts.containers.count == 3)
        let totals = Dictionary(uniqueKeysWithValues: facts.containers.flatMap(\.items).map { ($0.id, $0.count) })
        #expect(totals == ["minecraft:diamond": 2, "minecraft:iron_boots": 1, "minecraft:bread": 3, "minecraft:torch": 4])
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.containers == facts.containers && restored.signs == facts.signs && restored.spawners == facts.spawners)
    }
}
