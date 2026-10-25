import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct CreatureClassificationTests {
    private let owner = UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!

    private func entity(_ id: String, fields: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)])]
            .merging(fields) { $1 })
    }

    @Test(arguments: ["item", "experience_orb", "armor_stand", "player", "oak_boat",
                      "item_frame", "arrow", "interaction"])
    func nonMobsCannotBecomeCreaturesThroughMobLikeFields(_ type: String) {
        let nbt = entity("minecraft:" + type, fields: [
            "Health": .float(20), "Owner": Fixtures.uuidInts(owner), "CustomName": .string("False pet"),
            "CanPickUpLoot": .byte(1), "PersistenceRequired": .byte(1), "LeftHanded": .byte(0),
        ])
        #expect(Creature(nbt) == nil)
        for version in [4786, 4788, 4790, 4903, 5023, 5125] {
            #expect(Creature(nbt, dataVersion: version) == nil)
        }
    }

    @Test(arguments: ["sheep", "axolotl", "villager", "wandering_trader", "ender_dragon",
                      "giant", "illusioner", "creaking", "sulfur_cube"])
    func mobIdentityDoesNotRequireHealthOrAIFields(_ type: String) throws {
        let creature = try #require(Creature(entity("minecraft:" + type)))
        #expect(creature.id == "minecraft:" + type)
        #expect(creature.health == nil && creature.maxHealth == nil)
    }

    @Test func versionsSelectActualRegistriesAndPreserveTheApprovedFallback() {
        for version in [4786, 4788, 4790] {
            #expect(Creature(entity("minecraft:sulfur_cube"), dataVersion: version) == nil)
        }
        for version in [4903, 5023, 5125] {
            #expect(Creature(entity("minecraft:sulfur_cube"), dataVersion: version) != nil)
        }
        #expect(Creature(entity("minecraft:frostbite"), dataVersion: 5125) != nil)
        let withoutFrostbite: [Int?] = [nil, 4786, 4903, 5023, 5124, 5126, 9999]
        for version in withoutFrostbite {
            #expect(Creature(entity("minecraft:frostbite"), dataVersion: version) == nil)
        }
        let unverified: [Int?] = [nil, 4787, 5124, 5126, 9999]
        for version in unverified {
            #expect(Creature(entity("minecraft:sulfur_cube"), dataVersion: version) != nil)
            #expect(Creature(entity("minecraft:cat"), dataVersion: version)?.maxHealth == nil)
        }
    }

    @Test func identifiersUseTheGameNamespaceAndNeverGuessUnknownTypes() throws {
        for id in ["wolf", ":wolf", "minecraft:wolf"] {
            let creature = try #require(Creature(entity(id, fields: ["Owner": Fixtures.uuidInts(owner)])))
            #expect(creature.id == "minecraft:wolf" && creature.owner == owner)
        }
        for id in ["", "minecraft:", "Minecraft:wolf", "minecraft:WOLF", "example:wolf", "minecraft:unknown_mob"] {
            #expect(Creature(entity(id, fields: ["Health": .float(20), "CanPickUpLoot": .byte(1)])) == nil)
        }
    }

    @Test func sharedReadsAndCLIDiscardFalsePetsButKeepRealMobs() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Mob identity"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let entities = [
            entity("minecraft:item", fields: ["Health": .short(5), "Owner": Fixtures.uuidInts(owner),
                                               "CustomName": .string("False pet")]),
            entity("minecraft:experience_orb", fields: ["Health": .short(5)]),
            entity("minecraft:armor_stand", fields: ["Health": .float(20)]),
            entity("minecraft:wolf", fields: ["Health": .float(8), "Owner": Fixtures.uuidInts(owner)]),
            entity("minecraft:sheep"),
        ]
        let nbt = NBT.compound(["DataVersion": .int(5023), "Entities": .list(entities)])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]),
                           to: root.appendingPathComponent("entities/r.0.0.mca"))
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let expected = ["minecraft:wolf", "minecraft:sheep"]
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0) == entities)
        #expect(Creature.creatures(inEntityChunk: nbt).map(\.id) == expected)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0).map(\.id) == expected)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0).map(\.id) == expected)
        #expect(try dimension.scan(region: RegionPosition(x: 0, z: 0)).creatures.map(\.id) == expected)
        let cli = try Fixtures.runCLI(root, command: "creatures")
        #expect(cli.status == 0)
        #expect(cli.output.contains("1 minecraft:wolf") && cli.output.contains("1 minecraft:sheep"))
        #expect(!cli.output.contains("False pet") && !cli.output.contains("minecraft:item"))
        #expect(!cli.output.contains("minecraft:experience_orb") && !cli.output.contains("minecraft:armor_stand"))
    }
}
