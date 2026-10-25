import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct CreatureClassificationTests {
    private let owner = UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!
    private let mobFields: [String: NBT] = [
        "CanPickUpLoot": .byte(0), "PersistenceRequired": .byte(0), "LeftHanded": .byte(0),
    ]

    private func entity(_ id: String, fields: [String: NBT] = [:]) -> NBT {
        .compound(["id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)])]
            .merging(fields) { $1 })
    }

    @Test(arguments: ["item", "experience_orb", "armor_stand", "player", "oak_boat",
                      "item_frame", "arrow", "interaction", "wolf", "mymod:unknown"])
    func healthOwnershipAndNamesAloneDoNotEstablishMobRecords(_ type: String) {
        let nbt = entity(type, fields: [
            "Health": .float(20), "Owner": Fixtures.uuidInts(owner), "CustomName": .string("False pet"),
        ])
        #expect(Creature(nbt) == nil)
        #expect(Creature(nbt, dataVersion: 5023) == nil)
    }

    @Test(arguments: ["sheep", "villager", "ender_dragon", "giant", "illusioner", "frostbite",
                      "mymod:dragon", "future:never_seen_before"])
    func mobFormatSupportsAnyTypeWithoutHealthOrATypeList(_ type: String) throws {
        let creature = try #require(Creature(entity(typeID(type), fields: mobFields)))
        #expect(creature.id == typeID(type))
        #expect(creature.health == nil && creature.maxHealth == nil)
    }

    private func typeID(_ type: String) -> String { type.contains(":") ? type : "minecraft:" + type }

    @Test func savedMobFormatDoesNotRequireAKnownVersion() throws {
        let versions: [Int?] = [nil, 5023, 5125, 999999]
        for version in versions {
            let nbt = entity("future:new_mob", fields: mobFields.merging(["Health": .float(7)]) { $1 })
            let creature = try #require(Creature(nbt, dataVersion: version))
            #expect(creature.id == "future:new_mob" && creature.health == 7 && creature.maxHealth == nil)
        }
        #expect(Creature(entity("minecraft:cat", fields: mobFields), dataVersion: 5023)?.maxHealth == 10)
        #expect(Creature(entity("minecraft:cat", fields: mobFields), dataVersion: 999999)?.maxHealth == nil)
    }

    @Test func incompleteOrMalformedMobFieldsDoNotInventMembership() {
        for key in mobFields.keys {
            var missing = mobFields
            missing.removeValue(forKey: key)
            #expect(Creature(entity("mymod:dragon", fields: missing)) == nil)
            var malformed = mobFields
            malformed[key] = .string("false")
            #expect(Creature(entity("mymod:dragon", fields: malformed)) == nil)
        }
        #expect(Creature(entity("mymod:dragon", fields: ["Health": .float(20),
            "Owner": Fixtures.uuidInts(owner), "NoAI": .byte(1)])) == nil)
    }

    @Test func identifiersUseTheGameNamespaceAndValidation() throws {
        for id in ["wolf", ":wolf", "minecraft:wolf"] {
            let creature = try #require(Creature(entity(id,
                fields: mobFields.merging(["Owner": Fixtures.uuidInts(owner)]) { $1 })))
            #expect(creature.id == "minecraft:wolf" && creature.owner == owner)
        }
        for id in ["", "minecraft:", "Minecraft:wolf", "minecraft:WOLF"] {
            #expect(Creature(entity(id, fields: mobFields)) == nil)
        }
    }

    @Test func newTypeFactsSurviveDecodingAndCaching() throws {
        let creature = try #require(Creature(entity("mymod:dragon", fields: mobFields.merging([
            "Health": .float(12.5), "CustomName": .string("§aVisitor"), "UUID": Fixtures.uuidInts(owner),
        ]) { $1 }), dataVersion: 999999))
        #expect(creature.id == "mymod:dragon")
        #expect(creature.x == 1 && creature.y == 64 && creature.z == 2)
        #expect(creature.customName == "Visitor" && creature.health == 12.5 && creature.uuid == owner)
        #expect(creature.maxHealth == nil)
        #expect(try JSONDecoder().decode(Creature.self, from: JSONEncoder().encode(creature)) == creature)
    }

    @Test func sharedReadsAndCLIKeepEverySavedMobAndExcludeFalsePets() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Mob records"), "DataVersion": .int(5023),
        ])]), to: root.appendingPathComponent("level.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("region"), withIntermediateDirectories: true)
        let entities = [
            entity("minecraft:item", fields: ["Health": .short(5), "Owner": Fixtures.uuidInts(owner),
                                               "CustomName": .string("False pet")]),
            entity("minecraft:experience_orb", fields: ["Health": .short(5)]),
            entity("minecraft:armor_stand", fields: ["Health": .float(20)]),
            entity("minecraft:wolf", fields: mobFields.merging(["Health": .float(8), "Owner": Fixtures.uuidInts(owner)]) { $1 }),
            entity("minecraft:sheep", fields: mobFields),
            entity("mymod:dragon", fields: mobFields.merging(["CustomName": .string("Visitor")]) { $1 }),
        ]
        let nbt = NBT.compound(["DataVersion": .int(5023), "Entities": .list(entities)])
        try Fixtures.write(Fixtures.region([.init(localX: 0, localZ: 0, nbt: nbt)]),
                           to: root.appendingPathComponent("entities/r.0.0.mca"))
        let dimension = try #require(World(contentsOf: root).dimension("overworld"))
        let expected = ["minecraft:wolf", "minecraft:sheep", "mymod:dragon"]
        #expect(try dimension.entities(chunkX: 0, chunkZ: 0) == entities)
        let creatures = Creature.creatures(inEntityChunk: nbt)
        #expect(creatures.map(\.id) == expected)
        #expect(try dimension.creatures(chunkX: 0, chunkZ: 0) == creatures)
        #expect(try dimension.creatures(regionX: 0, regionZ: 0) == creatures)
        let facts = try dimension.scan(region: RegionPosition(x: 0, z: 0))
        #expect(facts.creatures == creatures)
        let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(restored.creatures == creatures)
        let cli = try Fixtures.runCLI(root, command: "creatures")
        #expect(cli.status == 0)
        #expect(cli.output.contains("1 minecraft:wolf") && cli.output.contains("1 minecraft:sheep"))
        #expect(!cli.output.contains("False pet") && !cli.output.contains("minecraft:item"))
        #expect(!cli.output.contains("minecraft:experience_orb") && !cli.output.contains("minecraft:armor_stand"))
        #expect(cli.output.contains("1 mymod:dragon"))
        #expect(cli.output.contains("mymod:dragon \"Visitor\" at (1, 64, 2)"))
        #expect(!cli.output.contains("unrecognized"))
    }
}
