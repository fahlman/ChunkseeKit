import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct CreaturePassengerTests {
    private let playerID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let ownerID = UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!
    private let horseID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func entity(_ id: String, y: Double = 64, fields: [String: NBT] = [:], passengers: [NBT] = []) -> NBT {
        var values: [String: NBT] = ["id": .string(id),
            "Pos": .list([.double(-8.5), .double(y), .double(2.5)])]
        values.merge(fields) { $1 }
        if !passengers.isEmpty { values["Passengers"] = .list(passengers) }
        return .compound(values)
    }

    private func mob(_ id: String, y: Double = 64, fields: [String: NBT] = [:], passengers: [NBT] = []) -> NBT {
        Fixtures.mob(entity(id, y: y, fields: fields, passengers: passengers).compound!)
    }

    private func chunk(_ entities: [NBT], version: Int32 = 5023) -> NBT {
        .compound(["DataVersion": .int(version), "Entities": .list(entities)])
    }

    @Test func villagersPetsJockeysAndNestedRidersKeepSavedOrderAndPositions() {
        let roots = [
            entity("minecraft:minecart", passengers: [mob("minecraft:villager", y: 64.5)]),
            entity("minecraft:oak_boat", passengers: [mob("minecraft:cat", y: 64.25,
                fields: ["Owner": Fixtures.uuidInts(ownerID), "CustomName": .string("Boat cat")])]),
            mob("minecraft:chicken", passengers: [mob("minecraft:zombie", y: 65)]),
            mob("minecraft:pig", passengers: [entity("minecraft:oak_boat", y: 65,
                passengers: [mob("minecraft:husk", y: 66)])]),
        ]
        let creatures = Creature.creatures(inEntityChunk: chunk(roots))
        #expect(creatures.map(\.id) == ["minecraft:villager", "minecraft:cat", "minecraft:chicken",
                                       "minecraft:zombie", "minecraft:pig", "minecraft:husk"])
        #expect(creatures.map(\.y) == [64.5, 64.25, 64, 65, 64, 66])
        #expect(creatures[1].owner == ownerID && creatures[1].customName == "Boat cat")
        #expect(creatures[1].maxHealth == 10)
    }

    @Test func unreadableParentsAndMalformedSiblingsDoNotHideReadableRiders() {
        let unknownVehicle = entity("mymod:vehicle", passengers: [mob("minecraft:cat")])
        let missingID = NBT.compound(["Passengers": .list([.string("malformed"), mob("minecraft:wolf")])])
        let malformedList = mob("minecraft:pig", fields: ["Passengers": .string("malformed")])
        let unknownMob = entity("mymod:dragon", fields: ["CanPickUpLoot": .byte(0),
            "PersistenceRequired": .byte(0), "LeftHanded": .byte(0)])
        let creatures = Creature.creatures(inEntityChunk: chunk([unknownVehicle, missingID,
            malformedList, entity("minecraft:oak_boat", passengers: [unknownMob])]))
        #expect(creatures.map(\.id) == ["minecraft:cat", "minecraft:wolf", "minecraft:pig", "mymod:dragon"])
        #expect(creatures.last?.id == "mymod:dragon")
    }

    @Test func deeplyNestedEntityTreeRemainsReadable() {
        var root = mob("minecraft:cat", y: 200)
        for _ in 0..<200 { root = entity("minecraft:oak_boat", passengers: [root]) }
        let creatures = Creature.creatures(inEntityChunk: chunk([root]))
        #expect(creatures.map(\.id) == ["minecraft:cat"])
        #expect(creatures.first?.y == 200)
    }

    @Test func rawTypedRegionAndContainerReadsShareThePassengerWalk() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let donkey = mob("minecraft:donkey", y: 65, fields: [
            "Owner": Fixtures.uuidInts(ownerID), "Items": .list([.compound([
                "id": .string("minecraft:diamond"), "count": .int(3),
            ])]),
        ])
        let boat = entity("minecraft:oak_boat", passengers: [donkey])
        let nbt = chunk([boat])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]),
                           to: root.appendingPathComponent("dimensions/minecraft/overworld/entities/r.0.0.mca"))
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0) == [boat, donkey])
        let creatures = Creature.creatures(inEntityChunk: nbt)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == creatures)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == creatures)
        let facts = try dimension.scan(region: RegionPosition(x: 0, z: 0))
        #expect(facts.creatures == creatures && creatures.count == 1)
        #expect(facts.containers.count == 1 && facts.containers.first?.kind == "minecraft:donkey")
        #expect(facts.containers.first?.items.first?.count == 3)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.creatures == creatures && restored.containers == facts.containers)
    }

    @Test func playerVehicleTreeKeepsItsOwnPositionOwnerAndPlayerVersion() throws {
        let horse = mob("minecraft:horse", fields: ["UUID": Fixtures.uuidInts(horseID),
            "Owner": Fixtures.uuidInts(ownerID), "CustomName": .string("Mount"), "Health": .float(21)])
        let cat = mob("minecraft:cat", y: 66)
        let tree = entity("minecraft:oak_boat", passengers: [horse, cat])
        let player = PlayerInfo(uuid: playerID, nbt: .compound([
            "DataVersion": .int(5023), "Dimension": .string("minecraft:overworld"),
            "Pos": .list([.double(100), .double(67), .double(200)]),
            "RootVehicle": .compound(["Attach": Fixtures.uuidInts(horseID), "Entity": tree]),
        ]))
        let mobs = player.rootVehicleCreatures
        #expect(mobs.map(\.id) == ["minecraft:horse", "minecraft:cat"])
        let mount = try #require(mobs.first)
        #expect(mount.x == -8.5 && mount.y == 64 && mount.z == 2.5)
        #expect(mount.uuid == horseID && mount.owner == ownerID && mount.owner != playerID)
        #expect(mount.health == 21 && mount.customName == "Mount")
        #expect(mobs.last?.maxHealth == 10 && player.dimension == "minecraft:overworld")
    }

    @Test func incompletePlayerLocationOrAttachmentDoesNotDiscardSavedMobs() {
        let player = PlayerInfo(uuid: playerID, nbt: .compound([
            "Dimension": .string("minecraft:overworld"),
            "RootVehicle": .compound(["Attach": .string("not-a-uuid"), "Entity": mob("minecraft:cat")]),
        ]))
        #expect(player.position == nil && player.dimension == "minecraft:overworld")
        #expect(player.rootVehicleCreatures.first?.id == "minecraft:cat")
        #expect(player.rootVehicleCreatures.first?.maxHealth == nil)
        for rootVehicle in [NBT.compound([:]), .string("malformed"), .compound(["Entity": .list([])])] {
            #expect(PlayerInfo(uuid: playerID, nbt: .compound(["RootVehicle": rootVehicle])).rootVehicleCreatures.isEmpty)
        }
    }

    @Test func CLICombinesRidersVehiclesAndShouldersInTheirSavedDimension() throws {
        let root = try world()
        defer { try? FileManager.default.removeItem(at: root) }
        let rider = mob("minecraft:wolf", y: 65, fields: ["CustomName": .string("Boat wolf")])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0,
            nbt: chunk([entity("minecraft:oak_boat", passengers: [rider])]))]),
            to: root.appendingPathComponent("dimensions/minecraft/overworld/entities/r.0.0.mca"))
        let horse = mob("minecraft:horse", fields: ["Owner": Fixtures.uuidInts(ownerID)])
        try player(in: root, uuid: playerID, fields: ["Dimension": .string("minecraft:overworld"),
            "Pos": .list([.double(100), .double(67), .double(200)]),
            "ShoulderEntityLeft": mob("minecraft:parrot"),
            "RootVehicle": .compound(["Entity": horse]),
        ])
        let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        try player(in: root, uuid: second, fields: ["Dimension": .string("minecraft:the_nether"),
            "RootVehicle": .compound(["Entity": mob("minecraft:cat", fields: ["CustomName": .string("Nether mount")])]),
        ])
        let overworld = try Fixtures.runCLI(root, command: "creatures")
        #expect(overworld.status == 0)
        #expect(overworld.output.contains("minecraft:wolf \"Boat wolf\" at (-9, 65, 2)"))
        #expect(overworld.output.contains("minecraft:horse at (-9, 64, 2) owned by \(ownerID.uuidString.lowercased())"))
        #expect(overworld.output.contains("minecraft:parrot at (100, 67, 200) on shoulder of \(playerID.uuidString.lowercased())"))
        #expect(overworld.output.contains("1 minecraft:horse\n") && overworld.output.contains("1 minecraft:wolf\n"))
        #expect(!overworld.output.contains("Nether mount"))
        let nether = try Fixtures.runCLI(root, command: "creatures", arguments: ["the_nether"])
        #expect(nether.status == 0 && nether.output.contains("minecraft:cat \"Nether mount\" at (-9, 64, 2)"))
        #expect(!nether.output.contains("minecraft:horse") && !nether.output.contains("minecraft:parrot"))
    }

    private func player(in root: URL, uuid: UUID, fields: [String: NBT]) throws {
        try Fixtures.writeGzippedNBT(.compound(fields.merging(["DataVersion": .int(5023)]) { $1 }),
            to: root.appendingPathComponent("players/data/\(uuid.uuidString.lowercased()).dat"))
    }

    private func world() throws -> URL {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Passengers"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        for dimension in ["overworld", "the_nether"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/\(dimension)/region"),
                                                    withIntermediateDirectories: true)
        }
        return root
    }
}
