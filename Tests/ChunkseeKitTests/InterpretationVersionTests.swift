import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct InterpretationVersionTests {
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    @Test func publishedContractsSurviveReopeningAndRemainDistinct() throws {
        let versions = [Chunk.interpretationVersion, MonsterSpawnLight.interpretationVersion,
                        GameAssets.interpretationVersion, RegionFacts.interpretationVersion]
        let stored = try encoded(versions)
        let reopened = try JSONDecoder().decode([InterpretationVersion].self, from: stored)
        #expect(reopened == versions)
        #expect(try encoded(reopened) == stored)
        #expect(Set(reopened).count == 4)
        for version in reopened {
            #expect(version.generatedFacts.count == 64)
            #expect(version.generatedFacts.allSatisfy { "0123456789abcdef".contains($0) })
        }
    }

    @Test func regionArchiveRejectsChangedReaderGeneratedFactsAndDependency() throws {
        let facts = RegionFacts(dimension: "example:world", region: .init(x: 2, z: -3), options: .init())
        let bytes = try encoded(facts)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let current = try #require(original["version"] as? [String: Any])
        var changedRevision = current
        changedRevision["revision"] = RegionFacts.interpretationVersion.revision + 1
        var changedFacts = current
        changedFacts["generatedFacts"] = String(repeating: "0", count: 64)
        var changedDependency = current
        var dependencies = try #require(current["dependencies"] as? [[String: Any]])
        #expect(!dependencies.isEmpty)
        dependencies[0]["revision"] = Chunk.interpretationVersion.revision + 1
        changedDependency["dependencies"] = dependencies
        for stale in [changedRevision, changedFacts, changedDependency] {
            var archive = original
            archive["version"] = stale
            let data = try JSONSerialization.data(withJSONObject: archive)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: data) }
        }
        let reopened = try JSONDecoder().decode(RegionFacts.self, from: bytes)
        #expect(reopened.dimension == "example:world" && reopened.region == .init(x: 2, z: -3))
        #expect(reopened.inhabitedTimes == facts.inhabitedTimes)
        #expect(try encoded(reopened) == bytes)
    }

    @Test func wholeLightRulesDistinguishChangedMeaningAndReuseEqualReads() throws {
        func rule(_ threshold: Int32) throws -> MonsterSpawnLight {
            let type = try #require(DimensionType(.compound([
                "min_y": .int(0), "height": .int(256), "logical_height": .int(256),
                "has_ceiling": .byte(0), "has_skylight": .byte(0),
                "monster_spawn_block_light_limit": .int(15), "monster_spawn_light_level": .int(threshold),
            ])))
            return try #require(MonsterSpawnLight(type: type, skyLightLevel: nil))
        }
        let original = try rule(7), same = try rule(7), changed = try rule(6)
        let cache = [original: "cached light"]
        #expect(cache[same] == "cached light" && cache[changed] == nil)
        #expect(try encoded(original) == encoded(same))
        #expect(try encoded(original) != encoded(changed))
        let position = BlockPosition(blockX: 0, blockY: 0, blockZ: 0)
        #expect(original.canPass(blockLight: 7, skyLight: nil, at: position) == true)
        #expect(changed.canPass(blockLight: 7, skyLight: nil, at: position) == false)
    }

    @Test func wholeBiomeDefinitionsRetainUnknownModifiersAndChangedColors() throws {
        let source = #"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":1193046,"grass_color_modifier":"example:future"}}"#
        let original = try #require(BiomeDefinition(json: Data(source.utf8)))
        let same = try #require(BiomeDefinition(json: Data(source.utf8)))
        let changed = try #require(BiomeDefinition(json: Data(source.replacingOccurrences(of: "1193046", with: "1193047").utf8)))
        let cache = [original: "cached color"]
        #expect(cache[same] == "cached color" && cache[changed] == nil)
        #expect(try encoded(original) == encoded(same))
        #expect(try encoded(original) != encoded(changed))
        #expect(original.grassColorModifier == .unknown("example:future"))
        #expect(String(decoding: try encoded(original), as: UTF8.self).contains("example:future"))
    }

    @Test func savedMapContentChangesWithoutChangingItsItemID() throws {
        let original = try #require(MapItem(id: 4, nbt: .compound([
            "colors": .byteArray(Array(repeating: 0, count: MapItem.size * MapItem.size)),
        ])))
        var changed = original
        changed.colors[0] = 4
        let cache = [original: "cached image"]
        #expect(cache[original] == "cached image" && cache[changed] == nil)
        #expect(try encoded(original) != encoded(changed))
        #expect(original.id == changed.id && original.isBlank && !changed.isBlank)
        changed = original
        changed.banners = [.init(x: 1, y: 2, z: 3, color: "red", name: "Camp")]
        #expect(cache[changed] == nil)
        #expect(try encoded(original) != encoded(changed))
    }

    @Test func completeScanOptionsHaveStableUnorderedInputsAndDistinctDefinitions() throws {
        let first = try #require(EnchantmentDefinition(data: Data(#"{"max_level":1}"#.utf8)))
        let second = try #require(EnchantmentDefinition(data: Data(#"{"max_level":2}"#.utf8)))
        let original = RegionScanOptions(blockIDs: Set(["example:a", "example:b"]),
                                        enchantments: ["example:a": first, "example:b": second])
        let reordered = RegionScanOptions(blockIDs: Set(["example:b", "example:a"]),
                                         enchantments: ["example:b": second, "example:a": first])
        #expect(original == reordered)
        #expect(try encoded(original) == encoded(reordered))
        var changed = original
        changed.enchantments["example:a"] = second
        #expect(try encoded(original) != encoded(changed))
        #expect(try encoded(RegionScanOptions(blockIDs: nil)) != encoded(RegionScanOptions(blockIDs: [])))
    }
}
