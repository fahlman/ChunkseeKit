import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct CreatureFlagTests {
    private let keys = ["CanPickUpLoot", "PersistenceRequired", "LeftHanded"]
    private let owner = UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!

    private func mob(_ tag: NBT, field: String? = nil, suffix: String = "sample") -> NBT {
        var fields: [String: NBT] = [
            "id": .string("future:" + suffix), "Pos": .list([.double(1.25), .double(64), .double(-2.5)]),
            "Health": .float(9.25), "Owner": Fixtures.uuidInts(owner), "CustomName": .string("Visitor")
        ]
        for key in keys { fields[key] = field == nil || field == key ? tag : .byte(0) }
        return .compound(fields)
    }

    @Test(arguments: SavedNumericSample.all)
    func everyReadableNumericFlagRetainsTheMobIncludingFalse(_ sample: SavedNumericSample) throws {
        // Both true and false are readable fields; neither the value nor the type ID decides membership.
        for key in keys {
            let bytes = mob(sample.tag, field: key).serialized()
            let decoded = try NBT.read(bytes).value
            let creature = try #require(Creature(decoded, dataVersion: Int(Int32.max)), "\(key): \(sample.id)")
            #expect(creature.id == "future:sample" && creature.owner == owner && creature.customName == "Visitor")
            #expect(creature.health == 9.25 && creature.x == 1.25 && creature.y == 64 && creature.z == -2.5)
            #expect(decoded.serialized() == bytes)
        }
    }

    @Test func missingAndNonnumericFlagsDoNotInventMembershipOrHideReadablePassengers() throws {
        let unavailable: [NBT?] = [nil, .string("false"), .string("0"), .string(""), .compound([:]),
            .list([]), .list([.int(0)]), .byteArray([0]), .intArray([0]), .longArray([0])]
        let child = mob(.double(0.5), suffix: "child")
        for key in keys {
            for value in unavailable {
                var fields = try #require(mob(.byte(0)).compound)
                fields[key] = value
                fields["NoAI"] = .byte(1)
                fields["Passengers"] = .list([child])
                let bytes = NBT.compound(fields).serialized(), decoded = try NBT.read(bytes).value
                #expect(Creature(decoded, dataVersion: Int(Int32.max)) == nil)
                let chunk = NBT.compound(["DataVersion": .int(Int32.max), "Entities": .list([decoded])])
                #expect(Creature.creatures(inEntityChunk: chunk).map(\.id) == ["future:child"])
                #expect(decoded.serialized() == bytes)
            }
        }
    }

    @Test func chunkRegionAndCachePathsRetainNumericMobRecordsAndRawEntities() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let mobs = SavedNumericSample.all.enumerated().map { mob($0.element.tag, suffix: "mob_\($0.offset)") }
        let vehicle = NBT.compound(["id": .string("minecraft:oak_boat"), "Passengers": .list(mobs)])
        let nonMob = NBT.compound(["id": .string("minecraft:item"), "Health": .float(5),
            "Owner": Fixtures.uuidInts(owner), "Pos": .list([.double(1), .double(64), .double(2)])])
        let input = NBT.compound(["DataVersion": .int(Int32.max), "Entities": .list([vehicle, nonMob])])
        let file = dimension.regionURL(.entities, at: .init(x: 0, z: 0))
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: input)]), to: file)
        let bytes = try Data(contentsOf: file)
        let expectedIDs = mobs.compactMap { $0["id"]?.string }
        let expected = Creature.creatures(inEntityChunk: input)
        #expect(expected.map(\.id) == expectedIDs && expected.count == SavedNumericSample.all.count)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == expected)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == expected)
        let raw = try dimension.entities(chunkX: 0, chunkZ: 0)
        #expect(raw.map { $0.serialized() } == ([vehicle] + mobs + [nonMob]).map { $0.serialized() })
        let facts = try dimension.scan(region: .init(x: 0, z: 0))
        #expect(facts.creatures == expected && facts.chunks.isEmpty)
        let archived = try JSONEncoder().encode(facts)
        #expect(try JSONDecoder().decode(RegionFacts.self, from: archived).creatures == expected)
        var previous = try #require(JSONSerialization.jsonObject(with: archived) as? [String: Any])
        var version = try #require(previous["version"] as? [String: Any])
        version["revision"] = 30 // The prior contract could omit mobs with readable floating flags.
        previous["version"] = version
        let stale = try JSONSerialization.data(withJSONObject: previous)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: stale) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func compressedPlayerShouldersAndVehicleUseTheSameFlagReader() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), level = root.appendingPathComponent("level.dat")
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Mob flags"), "DataVersion": .int(Int32.max)
        ])]), to: level)
        let left = mob(.float(0.5), suffix: "left"), right = mob(.double(-0.5), suffix: "right")
        let rider = mob(.double(.nan), suffix: "rider")
        let file = root.appendingPathComponent("players/data/\(id.uuidString.lowercased()).dat")
        try Fixtures.writeGzippedNBT(.compound([
            "DataVersion": .int(Int32.max), "Dimension": .string("minecraft:overworld"),
            "ShoulderEntityLeft": left, "ShoulderEntityRight": right,
            "RootVehicle": .compound(["Entity": .compound([
                "id": .string("minecraft:oak_boat"), "Passengers": .list([rider])
            ])])
        ]), to: file)
        let inputs = try [level: Data(contentsOf: level), file: Data(contentsOf: file)]
        let player = try #require(World(contentsOf: root).players().first)
        #expect(player.uuid == id && player.position == nil)
        #expect(player.shoulderPets.map(\.id) == ["future:left", "future:right"])
        #expect(player.rootVehicleCreatures.map(\.id) == ["future:rider"])
        for creature in player.shoulderPets + player.rootVehicleCreatures {
            #expect(creature.owner == owner && creature.health == 9.25)
            #expect(creature.x == 1.25 && creature.y == 64 && creature.z == -2.5)
        }
        for (url, bytes) in inputs { #expect(try Data(contentsOf: url) == bytes) }
    }
}
