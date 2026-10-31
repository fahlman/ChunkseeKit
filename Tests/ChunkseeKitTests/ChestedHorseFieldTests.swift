import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct ChestedHorseFieldTests {
    private func item(_ id: String) -> NBT { .compound(["id": .string(id), "count": .int(1)]) }

    private func carrier(_ flag: NBT?, id: String = "example:carrier", equipment: NBT? = nil) -> NBT {
        var fields: [String: NBT] = [
            "id": .string(id), "Pos": .list([.double(1.25), .double(64), .double(-2.5)]),
            "Health": .float(7), "CustomName": .string("Carrier"),
        ]
        fields["ChestedHorse"] = flag
        fields["equipment"] = equipment
        return Fixtures.mob(fields)
    }

    @Test(arguments: SavedNumericSample.all)
    func attachedChestUsesTheCapturedGameBoolean(_ sample: SavedNumericSample) throws {
        for id in ["minecraft:llama", "example:carrier"] {
            let bytes = carrier(sample.tag, id: id, equipment: .compound([
                "example:back": item("example:pack"),
            ])).serialized()
            let saved = try NBT.read(bytes).value
            let creature = try #require(Creature(saved, dataVersion: Int(Int32.max)))
            var expected = ["example:back": "example:pack"]
            if sample.booleanValue { expected["storage"] = "minecraft:chest" }
            #expect(creature.equipment?.mapValues(\.id) == expected, "\(sample.id)")
            #expect(creature.id == id && creature.customName == "Carrier" && creature.health == 7)
            #expect(creature.x == 1.25 && creature.y == 64 && creature.z == -2.5)
            #expect(saved.serialized() == bytes)
        }
    }

    @Test func invalidFlagsAddNothingAndExplicitStorageAlwaysWins() throws {
        let invalid: [NBT?] = [nil, .string("true"), .string("1"), .string(""), .compound([:]),
            .list([]), .list([.byte(1)]), .byteArray([1]), .intArray([1]), .longArray([1])]
        for flag in invalid {
            let empty = try #require(Creature(carrier(flag), dataVersion: Int(Int32.max)))
            #expect(empty.equipment == [:])
            let malformed = try #require(Creature(carrier(flag, equipment: .string("unreadable")),
                                                 dataVersion: Int(Int32.max)))
            #expect(malformed.equipment == nil && malformed.health == 7)
        }
        for flag in invalid + SavedNumericSample.all.map({ Optional($0.tag) }) {
            let stored = try #require(Creature(carrier(flag, equipment: .compound([
                "storage": item("example:stored_chest"), "head": item("minecraft:iron_helmet"),
            ])), dataVersion: Int(Int32.max)))
            #expect(stored.equipment?.mapValues(\.id) == [
                "storage": "example:stored_chest", "head": "minecraft:iron_helmet",
            ])
        }
    }

    @Test func passengerRegionAndCachePathsKeepTheSameDescriptiveEquipment() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Attached chest"), "DataVersion": .int(Int32.max),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"),
                                                withIntermediateDirectories: true)
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let mobs = SavedNumericSample.all.enumerated().map {
            carrier($0.element.tag, id: "example:carrier_\($0.offset)")
        }
        let vehicle = NBT.compound(["id": .string("minecraft:oak_boat"), "Passengers": .list(mobs)])
        let input = NBT.compound(["DataVersion": .int(Int32.max), "Entities": .list([vehicle])])
        let region = RegionPosition(x: 0, z: 0)
        let file = dimension.regionURL(.entities, at: region)
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: input)]), to: file)
        let bytes = try Data(contentsOf: file)
        let creatures = Creature.creatures(inEntityChunk: input)
        #expect(creatures.count == SavedNumericSample.all.count)
        for (creature, sample) in zip(creatures, SavedNumericSample.all) {
            #expect(creature.equipment?["storage"]?.id == (sample.booleanValue ? "minecraft:chest" : nil),
                    "\(sample.id)")
        }
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == creatures)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == creatures)
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0).map { $0.serialized() }
                == ([vehicle] + mobs).map { $0.serialized() })
        let facts = try dimension.scan(region: region)
        #expect(facts.creatures == creatures && facts.containers.isEmpty && facts.chunks.isEmpty)
        let archive = try JSONEncoder().encode(facts)
        #expect(try JSONDecoder().decode(RegionFacts.self, from: archive).creatures == creatures)
        var stale = try #require(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        var version = try #require(stale["version"] as? [String: Any])
        version["revision"] = 31 // This contract could invent or omit the descriptive attached chest.
        stale["version"] = version
        let oldArchive = try JSONSerialization.data(withJSONObject: stale)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: oldArchive) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func compressedPlayerCarriedCreaturesUseTheSameChestFlag() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), level = root.appendingPathComponent("level.dat")
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Attached chest"), "DataVersion": .int(Int32.max),
        ])]), to: level)
        let file = root.appendingPathComponent("players/data/\(id.uuidString.lowercased()).dat")
        try Fixtures.writeGzippedNBT(.compound([
            "DataVersion": .int(Int32.max), "Dimension": .string("minecraft:overworld"),
            "ShoulderEntityLeft": carrier(.double(-0.5)),
            "ShoulderEntityRight": carrier(.int(256)),
            "RootVehicle": .compound(["Entity": .compound([
                "id": .string("minecraft:oak_boat"), "Passengers": .list([carrier(.float(.infinity))]),
            ])]),
        ]), to: file)
        let inputs = try [level: Data(contentsOf: level), file: Data(contentsOf: file)]
        let player = try #require(World(contentsOf: root).players().first)
        #expect(player.uuid == id)
        #expect(player.shoulderPets.map { $0.equipment?["storage"]?.id } == ["minecraft:chest", nil])
        #expect(player.rootVehicleCreatures.map { $0.equipment?["storage"]?.id } == ["minecraft:chest"])
        for (url, bytes) in inputs { #expect(try Data(contentsOf: url) == bytes) }
    }
}
