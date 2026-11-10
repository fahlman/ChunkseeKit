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
    private let assets2 = InterpretationVersion(domain: "assets", revision: 2,
        generatedFacts: "ef1322bcbb857bc0cbf1cba79338b436fa18acb2bc11c88f95287a16fb361d7c", dependencies: [])
    private let assets2VillagerDefaults = InterpretationVersion(domain: "assets", revision: 2,
        generatedFacts: "f3de48d22ee2c5331d70aa3384aa9bf309dec48627777ce616dd20f043adf115", dependencies: [])
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
    private var regionFacts31: InterpretationVersion {
        .init(domain: "regionFacts", revision: 31,
            generatedFacts: "1f879b3155b000dd66139087f8ee3d12bcff5d3dd6f649e13508aab0676064c7", dependencies: [terrain2])
    }
    private var regionFacts32: InterpretationVersion {
        .init(domain: "regionFacts", revision: 32,
            generatedFacts: "1f879b3155b000dd66139087f8ee3d12bcff5d3dd6f649e13508aab0676064c7", dependencies: [terrain2])
    }
    private var regionFacts33: InterpretationVersion {
        .init(domain: "regionFacts", revision: 33,
            generatedFacts: "6afb63a4e924041cd0ea6d94cd632680b32fa2cae558224f66fe6d62ac54b287", dependencies: [terrain2])
    }
    private var regionFacts34: InterpretationVersion {
        .init(domain: "regionFacts", revision: 34,
            generatedFacts: "5c5168ccdb0d4407fc19f2e7decc7178dd453dd4a3327b4136e9bf2a44c99574", dependencies: [terrain2])
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

    private func lightRules() throws -> [MonsterSpawnLight] {
        try [false, true].map { skylight in
            let type = try #require(DimensionType(.compound([
                "min_y": .int(-64), "height": .int(384), "logical_height": .int(384),
                "has_ceiling": .byte(0), "has_skylight": .byte(skylight ? 1 : 0),
                "monster_spawn_block_light_limit": .int(7), "monster_spawn_light_level": .int(7),
            ])))
            return try #require(MonsterSpawnLight(type: type, skyLightLevel: 11))
        }
    }

    @Test func lightOutputMatchesItsRevision() throws {
        let rules = try lightRules()
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
                              regionFacts30: "6653e5f8c3ae0d15d8cd7e85a909ea3b1c4d1bf048b68439fd37e5f7c2869957",
                              regionFacts31: "d5df7b6ccf913fa15ff32ad7078d5208c37f54fe0fc5d498354c9df686deb234",
                              regionFacts32: "7cbd924ddac97848c95b700aac28a5771da4e0997ae116e867831cd0de51fa5b",
                              // The archive embeds its complete interpretation identity.
                              regionFacts33: "0be1ca5326dd5ab8fb62e6e91aadc9ce562705873bd00483eb7ed1ecd3ae6520",
                              regionFacts34: "1771b2cce9e3308c4e5a00ced2b402e0a7e4efba6d230cc3491597fc7ea805f2"])
    }

    private struct NumericCase {
        let id: String
        let input: NBT
        /// Query the captured game section, so a changed section reader cannot move the probe too.
        let probeY: Int
    }

    /// These inputs extend the ordinary fixtures above without replacing their old baselines.
    /// The numeric oracle is SavedNumericSample; missing fields and layout precedence reuse #316.
    private func numericCases() throws -> [NumericCase] {
        let fixtures = ChunkPrimitiveFieldTests()
        var cases = try SavedNumericSample.all.map { sample in
            NumericCase(id: "numeric/" + sample.id, input: try fixtures.saved(sample), probeY: sample.byteValue * 16)
        }
        let one = try #require(SavedNumericSample.all.first { $0.id == "byte:1" })
        for field in ["xPos", "zPos", "Y", "LastUpdate", "InhabitedTime", "isLightOn"] {
            for (index, invalid) in fixtures.absentOrNonnumeric.enumerated() {
                var input = try #require(fixtures.saved(one).compound)
                if field == "Y" {
                    var section = try #require(input["sections"]?.list?.first?.compound)
                    section["Y"] = invalid
                    input["sections"] = .list([.compound(section)])
                } else { input[field] = invalid }
                cases.append(.init(id: "invalid/\(field)/\(index)", input: .compound(input), probeY: 16))
            }
        }
        let rootTimes = fixtures.absentOrNonnumeric + [.double(-0.5), .float(-0.5), .long(0)]
        for (index, time) in rootTimes.enumerated() {
            var input: [String: NBT] = [
                "xPos": .int(0), "zPos": .int(0), "sections": .list([.compound(["Y": .string("bad")])]),
                "Level": .compound(["InhabitedTime": .double(-1.5)]),
            ]
            input["InhabitedTime"] = time
            cases.append(.init(id: "fallback/\(index)", input: .compound(input), probeY: 0))
        }
        var section = try #require(Fixtures.section(y: 0, palette: [.string("minecraft:stone")]).compound)
        section["Y"] = .short(260)
        let wrapped = NBT.compound(["DataVersion": .int(Int32.max), "InhabitedTime": .double(-0.5), "Level": .compound([
            "xPos": .double(-0.5), "zPos": .long(4_294_967_297), "Status": .string("full"),
            "Sections": .list([.compound(section)]), "InhabitedTime": .float(-0.5), "LastUpdate": .double(-1.5),
            "isLightOn": .int(256),
        ])])
        cases.append(.init(id: "wrapped", input: wrapped, probeY: 64))
        for sample in SavedNumericSample.all {
            let legacy = NBT.compound(["DataVersion": .int(1343), "Level": .compound([
                "xPos": .int(0), "zPos": .int(0), "Status": .string("full"),
                "Sections": .list([.compound(["Y": .byte(0), "Blocks": .byteArray([Int8](repeating: 1, count: 4096))])]),
                "InhabitedTime": sample.tag,
            ])])
            cases.append(.init(id: "legacy/" + sample.id, input: legacy, probeY: 0))
        }
        return cases
    }

    private func numericText<Value: CustomStringConvertible>(_ value: Value?) -> String? {
        value?.description
    }

    @Test func numericTerrainOutputMatchesItsRevision() throws {
        var rows: [[String?]] = []
        for sample in try numericCases() {
            let bytes = sample.input.serialized(), input = try NBT.read(bytes).value
            let chunk = try? Chunk(nbt: input)
            // Include rejection and independent records: a terrain failure must not hide saved time.
            // The fixture's saved floor clips surface queries, even when direct block access succeeds.
            rows.append([
                sample.id, chunk == nil ? "unreadable" : "readable",
                numericText(chunk?.x), numericText(chunk?.z),
                chunk.map { $0.sections.map { String($0.y) }.joined(separator: ",") },
                numericText(chunk?.minSectionY), chunk?.status,
                numericText(chunk?.lastUpdate), numericText(chunk?.inhabitedTime), numericText(chunk?.isLightOn),
                numericText(chunk?.surfaceY(x: 0, z: 0)),
                chunk?.block(x: 0, y: sample.probeY, z: 0)?.description,
                chunk?.biomeSnapshot.biome(x: 0, y: sample.probeY, z: 0),
                numericText(Chunk.inhabitedTime(in: input)),
            ])
            #expect(input.serialized() == bytes)
        }
        #expect(rows.count == 434)
        try check(rows, version: Chunk.interpretationVersion,
                  baselines: [terrain2: "d04dd6272c3deabe0292f97923df3b080ede05e742fd85ec3ee651b9f82ca409"])
    }

    @Test func numericLightOutputMatchesItsRevision() throws {
        let rules = try lightRules()
        let profiles: [(String, Set<String>)] = [
            ("full", []), ("terrainAndLight", Chunk.keysNotNeededForTerrainAndLight),
            ("terrain", Chunk.keysNotNeededForTerrain), ("biomes", Chunk.keysNotNeededForBiomes),
        ]
        var rows: [[String?]] = []
        for sample in try numericCases() {
            let bytes = sample.input.serialized()
            for (profile, skipping) in profiles {
                let chunk = try? Chunk(nbt: NBT.read(bytes, skipping: skipping).value)
                rows.append([
                    sample.id, profile, numericText(chunk?.isLightOn),
                    numericText(chunk?.blockLight(x: 0, y: sample.probeY, z: 0)),
                    numericText(chunk?.resolvedBlockLight(x: 0, y: sample.probeY, z: 0)),
                    numericText(chunk?.skyLight(x: 0, y: sample.probeY, z: 0)),
                    numericText(chunk.flatMap { rules[0].canPass(in: $0, x: 0, y: sample.probeY, z: 0) }),
                    numericText(chunk.flatMap { rules[1].canPass(in: $0, x: 0, y: sample.probeY, z: 0) }),
                ])
            }
        }
        #expect(rows.count == 1736)
        try check(rows, version: MonsterSpawnLight.interpretationVersion,
                  baselines: [light1Terrain2: "19c9400af6529cb7162d22380b42b519fd3a80c0cef456e24be2334adbe2c5a8"])
    }

    @Test func numericRegionArchiveOutputMatchesItsRevision() throws {
        let cases = try numericCases()
        try #require(cases.count <= 1024)
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root), position = RegionPosition(x: 0, z: 0)
        let bytes = try Fixtures.region(cases.enumerated().map { index, sample in
            .init(localX: index % 32, localZ: index / 32, nbt: sample.input)
        })
        let url = dimension.regionURL(.terrain, at: position)
        try Fixtures.write(bytes, to: url)
        let scanned = try dimension.scan(region: position)
        let facts = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(scanned))
        #expect(try InterpretationKey.identity(of: facts) == InterpretationKey.identity(of: scanned))
        #expect(facts.inhabitedTimes == (try dimension.inhabitedTimes(regionX: 0, regionZ: 0)))
        #expect(try Data(contentsOf: url) == Data(bytes))
        let chunks = Dictionary(uniqueKeysWithValues: facts.chunks.map { ($0.position, $0) })
        var rows: [[String?]] = [[
            "formats", String(facts.formats.readable), String(facts.formats.legacy),
            String(facts.formats.unreadableTerrain), String(facts.formats.unreadableEntities),
            String(facts.formats.unreadablePointsOfInterest), facts.paletteBlockIDs.sorted().joined(separator: ","),
        ]]
        for (index, sample) in cases.enumerated() {
            let chunk = chunks[ChunkPosition(x: index % 32, z: index / 32)]
            let deposit = chunk?.blockDeposits.first
            rows.append([
                sample.id, chunk == nil ? "unreadable" : "readable", String(facts.inhabitedTimes[index]),
                numericText(chunk?.position.x), numericText(chunk?.position.z), chunk?.status,
                deposit?.id, numericText(deposit?.count), numericText(deposit?.minY), numericText(deposit?.maxY),
                chunk?.sampledBiome, chunk?.biomes.joined(separator: ","), numericText(chunk?.isFullyGenerated),
            ])
            #expect((chunk?.blockDeposits.count ?? 0) <= 1)
        }
        #expect(rows.count == 435)
        try check(rows, version: RegionFacts.interpretationVersion,
                  baselines: [regionFacts30: "1b92386b70f6cb06a87b809939cefe34a164592c22b53f8e11d0a9616eca2374",
                              regionFacts31: "1b92386b70f6cb06a87b809939cefe34a164592c22b53f8e11d0a9616eca2374",
                              regionFacts32: "1b92386b70f6cb06a87b809939cefe34a164592c22b53f8e11d0a9616eca2374",
                              regionFacts33: "1b92386b70f6cb06a87b809939cefe34a164592c22b53f8e11d0a9616eca2374",
                              regionFacts34: "1b92386b70f6cb06a87b809939cefe34a164592c22b53f8e11d0a9616eca2374"])
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
                  baselines: [assets1: "21b2a5cfcac1160d1035ff73771e624da71c7db8c44def3326cdb04657f8dae4",
                              assets2: "21b2a5cfcac1160d1035ff73771e624da71c7db8c44def3326cdb04657f8dae4",
                              assets2VillagerDefaults: "21b2a5cfcac1160d1035ff73771e624da71c7db8c44def3326cdb04657f8dae4"])
    }
}
