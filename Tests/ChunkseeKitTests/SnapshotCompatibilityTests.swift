import ChunkseeKit
import Foundation
import Testing

@Suite struct SnapshotCompatibilityTests {
    private let snapshot = SaveVersion.java26_4Snapshot5

    private func assets(_ entries: [TestZIP.Entry], version: Int, id: String = "26.4-snapshot-5") throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(id)\",\"world_version\":\(version)}")
        ] + entries))))
    }

    @Test func compactNewBlocksAndJukeboxUseSnapshotRegistryDefaults() throws {
        // Expected saved defaults were extracted from the official Snapshot 5 registry.
        let cases = [
            ("packed_ice_brick_slab", "type=bottom,waterlogged=false"),
            ("packed_ice_brick_stairs", "facing=north,half=bottom,shape=straight,waterlogged=false"),
            ("packed_ice_brick_wall", "east=none,north=none,south=none,up=true,waterlogged=false,west=none"),
            ("brittle_ice", "age=0"),
            ("ice_crystal", "facing=up,waterlogged=false"),
            ("icicle", "attached=false,thickness=tip,vertical_direction=up,waterlogged=false"),
            ("jukebox", "has_record=false,playlist_mode=false")
        ]
        for (id, predicate) in cases {
            let entries: [TestZIP.Entry] = [
                .init(path: "assets/minecraft/blockstates/\(id).json",
                      text: "{\"variants\":{\"\(predicate)\":{\"model\":\"block/expected\"}}}"),
                .init(path: "assets/minecraft/models/block/expected.json", text: "{}")
            ]
            let state = BlockState("minecraft:" + id)
            let model = try #require(assets(entries, version: snapshot).blockModel(for: state))
            #expect(model.parts.first?.alternatives.first?.modelID.path == "block/expected")
            #expect(state.properties.isEmpty)
            for version in [SaveVersion.java26_3, snapshot - 1, snapshot + 1] {
                #expect(try assets(entries, version: version).blockModel(for: state) == nil)
            }
        }
    }

    @Test func snapshotWorldsCanSampleOlderChunksWithoutEnablingUnknownVersions() throws {
        let point = BlockPosition(blockX: -17, blockY: 64, blockZ: 31)
        let original = BiomeSampler(seed: -8378843).cellOrigin(at: point)
        for version in [SaveVersion.java26_3, snapshot] {
            let sampler = try #require(BiomeSampler(seed: -8378843, dataVersion: version))
            #expect(sampler.cellOrigin(at: point) == original)
        }
        for version: Int? in [nil, snapshot - 1, snapshot + 1] {
            #expect(BiomeSampler(seed: -8378843, dataVersion: version) == nil)
        }
    }

    @Test func explicitSnapshotPropertiesOverrideTheNewDefaults() throws {
        let entries: [TestZIP.Entry] = [
            .init(path: "assets/minecraft/blockstates/jukebox.json", text: #"{"variants":{"playlist_mode=false":{"model":"block/ordinary"},"playlist_mode=true":{"model":"block/playlist"}}}"#),
            .init(path: "assets/minecraft/models/block/ordinary.json", text: "{}"),
            .init(path: "assets/minecraft/models/block/playlist.json", text: "{}")
        ]
        let reader = try assets(entries, version: snapshot)
        let state = BlockState("minecraft:jukebox", properties: ["playlist_mode": "true"])
        #expect(reader.blockModel(for: state)?.parts.first?.alternatives.first?.modelID.path == "block/playlist")
    }

    @Test func snapshotFreezingPotionsDoNotAppearInOtherVersions() {
        for id in ["freezing", "long_freezing"] {
            let item = ItemStack(id: "minecraft:potion", components: .compound([
                "minecraft:potion_contents": .string("minecraft:" + id)
            ]))
            #expect(item.potionColor(gameDataVersion: Int32(snapshot), defaultColor: 0) == 0x9eeeee)
            for version in [SaveVersion.java26_3, snapshot - 1, snapshot + 1] {
                #expect(item.potionColor(gameDataVersion: Int32(version), defaultColor: 0) == nil)
            }
        }
        let custom = ItemStack(id: "minecraft:potion", components: .compound([
            "minecraft:potion_contents": .compound([
                "custom_effects": .list([.compound(["id": .string("minecraft:freezing")])])
            ])
        ]))
        #expect(custom.potionColor(gameDataVersion: Int32(snapshot), defaultColor: 0) == 0x9eeeee)
        #expect(custom.potionColor(gameDataVersion: Int32(SaveVersion.java26_3), defaultColor: 0) == nil)
    }

    @Test func existingColorsWorkInBothVerifiedVersionsOnly() throws {
        let entries: [TestZIP.Entry] = [.init(path: "data/minecraft/worldgen/biome/ice_caves.json",
            text: ##"{"temperature":0.0,"downfall":0.0,"effects":{"water_color":"#14559b"}}"##)]
        let healing = ItemStack(id: "minecraft:potion", components: .compound([
            "minecraft:potion_contents": .string("minecraft:healing")
        ]))
        for version in [SaveVersion.java26_3, snapshot, snapshot - 1, snapshot + 1] {
            let verified = version == SaveVersion.java26_3 || version == snapshot
            #expect(try assets(entries, version: version).biomeDefinition("ice_caves")?.waterColor == (verified ? 0x14559b : nil))
            #expect(healing.potionColor(gameDataVersion: Int32(version), defaultColor: 0) == (verified ? 0xf82423 : nil))
            #expect(BlockState("minecraft:grass_block").tintSource(at: 0, gameDataVersion: Int32(version))
                    == (verified ? .biome(.grass, yOffset: 0) : nil))
        }
    }

    @Test func savedHealthAndStatisticsKeepExactVersionBoundaries() throws {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        for version in [SaveVersion.java26_3, snapshot, snapshot - 1, snapshot + 1] {
            let verified = version == SaveVersion.java26_3 || version == snapshot
            let player = PlayerInfo(uuid: uuid, nbt: .compound(["DataVersion": .int(Int32(version))]))
            #expect(player.maxHealth == (verified ? 20 : nil))
            let pet = try #require(Creature(.compound([
                "id": .string("minecraft:cat"), "Health": .float(10),
                "Pos": .list([.double(0), .double(64), .double(0)])
            ]), dataVersion: version))
            #expect(pet.maxHealth == (verified ? 10 : nil))
            let stats = PlayerStatistics(dataVersion: version, values: [:])
            #expect(stats.unit(of: "damage_taken") == (verified ? .tenthsOfDamagePoint : nil))
        }
    }

    @Test func specialModelsRequireTheMatchingSnapshotIdentity() throws {
        let entries: [TestZIP.Entry] = [
            .init(path: "assets/minecraft/items/chest.json", text: #"{"model":{"type":"special","base":"item/chest","model":{"type":"chest","texture":"normal"}}}"#),
            .init(path: "assets/minecraft/models/item/chest.json", text: "{}")
        ]
        for (id, version, supported) in [("26.3", SaveVersion.java26_3, true),
                                         ("26.4-snapshot-5", snapshot, true),
                                         ("26.4-snapshot-4", snapshot, false),
                                         ("26.3", snapshot, false),
                                         ("26.4-snapshot-5", SaveVersion.java26_3, false),
                                         ("26.4-snapshot-5", snapshot + 1, false)] {
            let reader = try assets(entries, version: version, id: id)
            #expect((reader.defaultItemModel("chest") != nil) == supported)
        }
    }
}
