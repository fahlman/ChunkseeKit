import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct CreatureEntryTests {
    @Test func categoryPrecedenceAndIdentityMatchExistingCreatureSelection() throws {
        let uuid = try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
        var creature = Creature(id: "minecraft:wolf", x: -8.7, y: 62, z: 0)
        #expect(CreatureEntry(creature)?.group == .mob)
        creature.customName = "Summer"
        #expect(CreatureEntry(creature)?.group == .named)
        #expect(CreatureEntry(creature)?.id == "minecraft:wolf@-8.7,62.0,0.0")
        creature.owner = uuid
        #expect(CreatureEntry(creature)?.group == .pet)
        creature.villager = Villager(.compound(["VillagerData": .compound([
            "profession": .string("minecraft:farmer")])]))
        #expect(CreatureEntry(creature)?.group == .villager)
        creature.uuid = uuid
        let original = try #require(CreatureEntry(creature))
        creature.x = 512.5
        #expect(CreatureEntry(creature)?.id == original.id)
        #expect(original.id == "creature:00112233-4455-6677-8899-aabbccddeeff")
    }

    @Test func invalidLocationsAreExcludedWithoutTrapping() throws {
        let located = Creature(id: "minecraft:cat", x: -0.1, y: -64.5, z: 0, customName: "Cat")
        #expect(CreatureEntry(located)?.creature == located)
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max)] {
            var creature = located
            creature.x = value; #expect(CreatureEntry(creature) == nil)
            creature = located; creature.y = value; #expect(CreatureEntry(creature) == nil)
            creature = located; creature.z = value; #expect(CreatureEntry(creature) == nil)
        }
        var creature = located
        creature.x = Double(Int32.min); creature.z = Double(Int32.max) + 0.5
        #expect(CreatureEntry(creature) != nil)
        creature.x -= 0.5
        #expect(CreatureEntry(creature) == nil)
        creature.x = 0; creature.z = Double(Int32.max) + 1
        #expect(CreatureEntry(creature) == nil)
    }

    @Test func scannedFloatingFlagsRetainEveryMobCategoryInTheDimensionIndex() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Mob categories"), "DataVersion": .int(Int32.max)
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/overworld"),
                                                withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let coordinate = RegionPosition(x: 0, z: 0), catalog = NotableBlock.Catalog(tags: [:])
        let owner = UUID()
        let records: [NBT] = (0..<4).map { index in
            var fields: [String: NBT] = [
                "id": .string("future:mob_\(index)"), "Pos": .list([.double(Double(index)), .double(64), .double(0)]),
                "CanPickUpLoot": .float(0.5), "PersistenceRequired": .double(-0.5), "LeftHanded": .double(.nan)
            ]
            if index > 0 { fields["CustomName"] = .string("Visitor") }
            if index > 1 { fields["Owner"] = Fixtures.uuidInts(owner) }
            if index > 2 {
                fields["VillagerData"] = .compound(["profession": .string("minecraft:farmer")])
            }
            return .compound(fields)
        }
        let input = NBT.compound(["DataVersion": .int(Int32.max), "Entities": .list(records)])
        let file = dimension.regionURL(.entities, at: coordinate)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: input)]), to: file)
        let bytes = try Data(contentsOf: file)
        let facts = try dimension.scan(region: coordinate, options: .init(blockIDs: catalog.blockIDs))
        let region = RegionIndex(facts, caveBiomeIDs: [], notableBlocks: catalog)
        let index = DimensionIndex(dimension: dimension.id, caveBiomeIDs: [], notableBlocks: catalog)
            .updating(available: [coordinate], selected: nil, replacements: [region])
        let retained = try #require(index.regions[coordinate]).creatures
        #expect(retained.map(\.creature.id) == (0..<4).map { "future:mob_\($0)" })
        #expect(retained.map(\.group) == [.mob, .named, .pet, .villager])
        #expect(try Data(contentsOf: file) == bytes)
    }
}
