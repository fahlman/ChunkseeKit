import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct SpawnEggTests {
    private func assets(_ items: [String], version: Int = 5023) throws -> GameAssets {
        var entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"fixture\",\"world_version\":\(version)}"),
            .init(path: "assets/pack/models/item/picture.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"pack:item/picture"}}"#)
        ]
        for name in items {
            let id = try #require(Identifier(name))
            entries.append(.init(path: "assets/\(id.namespace)/items/\(id.path).json",
                                 text: #"{"model":{"type":"model","model":"pack:item/picture"}}"#))
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    @Test func gameRelationshipSuppliesAnItemUsableByTheExistingModelReader() throws {
        let reader = try assets(["minecraft:wolf_spawn_egg"])
        for name in ["wolf", ":wolf", "minecraft:wolf"] {
            let egg = try #require(reader.spawnEggItemID(for: name))
            #expect(egg.description == "minecraft:wolf_spawn_egg")
            let model = try #require(reader.defaultItemModel(egg.description))
            #expect(model.parts.count == 1)
            guard case .layers(let layers) = model.parts[0].model.geometry else { Issue.record("Expected generated item layers"); return }
            #expect(layers.first?.material.texture.description == "pack:item/picture")
        }
    }

    @Test func namesAndPicturesCannotInventAMissingOrCustomRelationship() throws {
        let reader = try assets(["minecraft:giant_spawn_egg", "minecraft:illusioner_spawn_egg",
                                 "pack:wolf_spawn_egg", "pack:custom_spawn_egg", "minecraft:wolf_spawn_egg"])
        for name in ["giant", "illusioner", "pack:wolf", "pack:custom", "unknown", "", "../wolf"] {
            #expect(reader.spawnEggItemID(for: name) == nil)
        }
        #expect(reader.defaultItemModel("pack:custom_spawn_egg") != nil)
    }

    @Test func missingResourcesStayUnavailableWithoutHidingOtherFacts() throws {
        let reader = try assets(["minecraft:cat_spawn_egg"])
        #expect(reader.spawnEggItemID(for: "wolf") == nil)
        #expect(reader.spawnEggItemID(for: "cat")?.description == "minecraft:cat_spawn_egg")
    }

    @Test func parseableAssetVersionsRetainTheKnownRelationship() throws {
        for version in [0, Int(Int32.max)] {
            let reader = try assets(["minecraft:wolf_spawn_egg"], version: version)
            #expect(reader.spawnEggItemID(for: "wolf")?.description == "minecraft:wolf_spawn_egg")
        }
    }
}
