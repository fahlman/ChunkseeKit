import ChunkseeKitTestSupport
import Foundation
import Testing
@testable import ChunkseeKit

/// These fixture outputs are the persisted reader contract, not a second implementation.
/// A changed output requires a new reviewed contract and baseline; retain earlier entries.
/// Unexercised behavior still needs review of the owning interpretation version.
@Suite struct InterpretationOutputTests {
    // Freeze the complete published contract rather than looking up today's generated constants.
    // A generated/dependent identity change needs a new baseline, not a copied reader counter.
    private let terrain1 = InterpretationVersion(domain: "terrain", revision: 1,
        generatedFacts: "ecf3d4cb262728a6dc1418c48cb262fa32d4415dcdb64287ea520c87ba1b8702", dependencies: [])
    private let terrain2 = InterpretationVersion(domain: "terrain", revision: 2,
        generatedFacts: "ecf3d4cb262728a6dc1418c48cb262fa32d4415dcdb64287ea520c87ba1b8702", dependencies: [])
    private let assets1 = InterpretationVersion(domain: "assets", revision: 1,
        generatedFacts: "ef1322bcbb857bc0cbf1cba79338b436fa18acb2bc11c88f95287a16fb361d7c", dependencies: [])
    private var light1: InterpretationVersion {
        .init(domain: "light", revision: 1,
            generatedFacts: "e665beb8560af59ac4835d84dcd2a21b455e44c097d2e82853c5fb88bc626ccc", dependencies: [terrain1])
    }
    private var light1Terrain2: InterpretationVersion {
        .init(domain: "light", revision: 1,
            generatedFacts: "e665beb8560af59ac4835d84dcd2a21b455e44c097d2e82853c5fb88bc626ccc", dependencies: [terrain2])
    }
    private var regionFacts29: InterpretationVersion {
        .init(domain: "regionFacts", revision: 29,
            generatedFacts: "1f879b3155b000dd66139087f8ee3d12bcff5d3dd6f649e13508aab0676064c7", dependencies: [terrain1])
    }
    private var regionFacts30: InterpretationVersion {
        .init(domain: "regionFacts", revision: 30,
            generatedFacts: "1f879b3155b000dd66139087f8ee3d12bcff5d3dd6f649e13508aab0676064c7", dependencies: [terrain2])
    }

    private func check(_ output: some Encodable, version: InterpretationVersion,
                       baselines: [InterpretationVersion: String]) throws {
        let actual = try InterpretationKey.identity(of: output)
        #expect(baselines[version] == actual,
                "\(version.domain) revision \(version.revision), output SHA-256: \(actual)")
    }

    private struct TerrainOutput: Encodable {
        let x: Int, z: Int, minSectionY: Int
        let status: String?
        let fullyGenerated: Bool
        let sectionY: [Int]
        let blocks: [[String?]]
        let biomes: [[String?]]
        let surface: [Int?]
        let heightmaps: [String: [Int]?]

        init(_ chunk: Chunk) {
            x = chunk.x; z = chunk.z; minSectionY = chunk.minSectionY
            status = chunk.status; fullyGenerated = chunk.isFullyGenerated
            sectionY = chunk.sections.map(\.y)
            blocks = chunk.sections.map { section in
                (0..<4096).map { section.blockStates?[$0]?.description }
            }
            biomes = chunk.sections.map { section in (0..<64).map { section.biomes?[$0] } }
            surface = chunk.surfaceHeights()
            heightmaps = Dictionary(uniqueKeysWithValues: chunk.heightmapNames.map { ($0, chunk.heightmap($0)) })
        }
    }

    @Test func terrainOutputMatchesItsRevision() throws {
        var blocks = [Int](repeating: 0, count: 4096)
        for column in 0..<256 { blocks[(column % 16) * 256 + column] = 1 + column % 2 }
        let negative = Fixtures.chunk(x: 2, z: -3, dataVersion: 5023, sections: [
            Fixtures.section(y: -1, palette: [.compound(["Name": .string("minecraft:air")]),
                .compound(["Name": .string("minecraft:water")]),
                .compound(["Name": .string("minecraft:oak_log"), "Properties": .compound(["axis": .string("x")])])],
                indices: blocks, biomes: ["minecraft:plains", "minecraft:desert"],
                biomeIndices: (0..<64).map { $0 % 2 }),
        ])
        let legacy = NBT.compound(["DataVersion": .int(2730), "Level": .compound([
            "xPos": .int(0), "zPos": .int(0), "Status": .string("full"),
            "Sections": .list([.compound(["Y": .byte(0),
                "Palette": .list([.compound(["Name": .string("minecraft:grass_path")])]),
                "BlockStates": .longArray([])])]),
            "Biomes": .intArray([Int32](repeating: 1, count: 1024)),
        ])])
        let inputs = [RegionFactsTests().terrain(), negative, legacy]
        let chunks = try inputs.map { try Chunk(nbt: NBT.read($0.serialized()).value) }
        try check(chunks.map(TerrainOutput.init), version: Chunk.interpretationVersion,
                  baselines: [terrain1: "ae9a3a62f0596f582fbb599d79c3e54c67561c96aba3cd644fa803883c5aeeff",
                              terrain2: "ae9a3a62f0596f582fbb599d79c3e54c67561c96aba3cd644fa803883c5aeeff"])
    }

    private struct LightOutput: Encodable {
        let block: [Int?], resolvedBlock: [Int?], sky: [Int?]
        let checks: [[Bool?]]
    }

    @Test func lightOutputMatchesItsRevision() throws {
        let rules = try [false, true].map { skylight in
            let type = try #require(DimensionType(.compound([
                "min_y": .int(-64), "height": .int(384), "logical_height": .int(384),
                "has_ceiling": .byte(0), "has_skylight": .byte(skylight ? 1 : 0),
                "monster_spawn_block_light_limit": .int(7), "monster_spawn_light_level": .int(7),
            ])))
            return try #require(MonsterSpawnLight(type: type, skyLightLevel: 11))
        }
        let points = [-17, -16, -1, 0, 15, 16, 32].flatMap { y in
            (0..<16).map { (x: $0, y: y, z: $0 % 2) }
        }
        let outputs = try [false, true].map { valid in
            let section = NBT.compound(["Y": .byte(-1),
                "BlockLight": .byteArray((0..<2048).map { Int8(truncatingIfNeeded: $0) }),
                "SkyLight": .byteArray((0..<2048).map { Int8(truncatingIfNeeded: 255 - $0) })])
            let input = Fixtures.chunk(x: 2, z: -3, dataVersion: 5023,
                sections: [section, .compound(["Y": .byte(0)])], extra: ["isLightOn": .byte(valid ? 1 : 0)])
            let chunk = try Chunk(nbt: NBT.read(input.serialized()).value)
            return LightOutput(
                block: points.map { chunk.blockLight(x: $0.x, y: $0.y, z: $0.z) },
                resolvedBlock: points.map { chunk.resolvedBlockLight(x: $0.x, y: $0.y, z: $0.z) },
                sky: points.map { chunk.skyLight(x: $0.x, y: $0.y, z: $0.z) },
                checks: rules.map { rule in points.map { rule.canPass(in: chunk, x: $0.x, y: $0.y, z: $0.z) } })
        }
        try check(outputs, version: MonsterSpawnLight.interpretationVersion,
                  baselines: [light1: "e2031b194a46173a4fdbb2fe315f70816af820d8081a54cf537b8726bb7ecefb",
                              light1Terrain2: "e2031b194a46173a4fdbb2fe315f70816af820d8081a54cf537b8726bb7ecefb"])
    }

    @Test func regionArchiveOutputMatchesItsRevision() throws {
        let fixture = RegionFactsTests()
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        try fixture.write(fixture.terrain(), in: .terrain, dimension: dimension)
        try fixture.write(fixture.entityChunk, in: .entities, dimension: dimension)
        try fixture.write(fixture.poiChunk, in: .pointsOfInterest, dimension: dimension)
        let facts = try dimension.scan(region: fixture.region,
            options: .init(blockIDs: ["minecraft:diamond_ore", "minecraft:gold_ore"]))
        let reopened = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
        #expect(try InterpretationKey.identity(of: reopened) == InterpretationKey.identity(of: facts))
        try check(facts, version: RegionFacts.interpretationVersion,
                  baselines: [regionFacts29: "c0e7507380146274ce8e2148ed89e1c5bf65dd0d7f3a0559690c482ee5019ec3",
                              regionFacts30: "6653e5f8c3ae0d15d8cd7e85a909ea3b1c4d1bf048b68439fd37e5f7c2869957"])
    }

    private struct MaterialOutput: Encodable {
        let texture: String
        let translucent: Bool
        let tint: Int?
        let uv: [Float]
        let faceRotation: Int
        let modelRotation: [Int]
        let uvLock: Bool
    }

    private struct AssetOutput: Encodable {
        let material: MaterialOutput
        let biome: BiomeDefinition
        let mapColors: [[UInt8]?]
    }

    @Test func assetOutputMatchesItsRevision() throws {
        let reader = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":5023}"#),
            .init(path: "assets/example/blockstates/test.json",
                  text: #"{"variants":{"axis=x":{"model":"example:block/child","y":450,"uvlock":true}}}"#),
            .init(path: "assets/example/models/block/base.json", text:
                ##"{"textures":{"top":"block/old"},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{"up":{"texture":"#top","tintindex":0,"uv":[1,2,13,14],"rotation":-90}}}]}"##),
            .init(path: "assets/example/models/block/child.json", text:
                #"{"parent":"example:block/base","textures":{"top":{"sprite":"example:block/new","force_translucent":true}}}"#),
            .init(path: "data/example/worldgen/biome/tinted.json", text:
                ##"{"temperature":0.8,"downfall":0.4,"effects":{"water_color":"#123456","grass_color":[0.1,0.5,1.0],"foliage_color":7654321,"grass_color_modifier":"dark_forest"}}"##),
        ]))))
        let block = try #require(reader.blockModel(for: .init("example:test", properties: ["axis": "x"])))
        let choice = try #require(block.parts.first?.alternatives.first)
        guard case .elements(let elements) = choice.model.geometry else {
            Issue.record("The fixed fixture must resolve model elements"); return
        }
        let face = try #require(elements.first?.faces[.up])
        let material = MaterialOutput(texture: face.material.texture.description,
            translucent: face.material.forceTranslucent, tint: face.tintIndex,
            uv: [face.uv.x, face.uv.y, face.uv.z, face.uv.w], faceRotation: face.rotation,
            modelRotation: [choice.rotation.x, choice.rotation.y, choice.rotation.z], uvLock: choice.uvLock)
        let biome = try #require(reader.biomeDefinition("example:tinted"))
        let colors = (0..<256).map { MapItem.rgb(forColor: UInt8($0)).map { [$0.red, $0.green, $0.blue] } }
        try check(AssetOutput(material: material, biome: biome, mapColors: colors),
                  version: GameAssets.interpretationVersion,
                  baselines: [assets1: "21b2a5cfcac1160d1035ff73771e624da71c7db8c44def3326cdb04657f8dae4"])
    }
}
