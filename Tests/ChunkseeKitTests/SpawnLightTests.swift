import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct SpawnLightTests {
    private func lightChunk(flag: NBT?, block: [Int8]?, sky: [Int8]?) throws -> Chunk {
        var section: [String: NBT] = ["Y": .byte(-1)]
        section["BlockLight"] = block.map(NBT.byteArray)
        section["SkyLight"] = sky.map(NBT.byteArray)
        var fields = Fixtures.chunk(x: 0, z: 0, sections: [.compound(section)]).compound!
        fields["isLightOn"] = flag
        return try Chunk(nbt: .compound(fields))
    }

    @Test func chunkLightRequiresValidityAndKeepsMissingArraysUnknown() throws {
        let zero = [Int8](repeating: 0, count: 2048)
        let flags: [NBT?] = [nil, .byte(0), .string("true"), .compound([:])]
        for flag in flags {
            let chunk = try lightChunk(flag: flag, block: zero, sky: zero)
            #expect(!chunk.isLightOn)
            #expect(chunk.blockLight(x: 0, y: -16, z: 0) == nil)
            #expect(chunk.skyLight(x: 0, y: -16, z: 0) == nil)
            #expect(chunk.sections[0].blockLight(x: 0, y: 0, z: 0) == 0) // Raw bytes remain readable.
        }
        let invalidArrays: [[Int8]?] = [nil, [], [0], Array(repeating: 0, count: 2049)]
        for invalid in invalidArrays {
            let chunk = try lightChunk(flag: .byte(1), block: invalid, sky: zero)
            #expect(chunk.isLightOn)
            #expect(chunk.blockLight(x: 0, y: -16, z: 0) == nil)
            #expect(chunk.skyLight(x: 0, y: -16, z: 0) == 0)
        }
    }

    @Test func validLightUsesSectionYAndTheExistingNibbleOrdering() throws {
        var block = [Int8](repeating: 0, count: 2048)
        block[0] = Int8(bitPattern: 0xE3)
        block[2047] = Int8(bitPattern: 0xF2)
        let chunk = try lightChunk(flag: .byte(1), block: block, sky: Array(repeating: -1, count: 2048))
        #expect(chunk.blockLight(x: 0, y: -16, z: 0) == 3)
        #expect(chunk.blockLight(x: 1, y: -16, z: 0) == 14)
        #expect(chunk.blockLight(x: -1, y: -1, z: -1) == 15)
        #expect(chunk.blockLight(x: 14, y: -1, z: 15) == 2)
        #expect(chunk.skyLight(x: 3, y: -10, z: 8) == 15)
        #expect(chunk.blockLight(x: 0, y: 0, z: 0) == nil)
        #expect(chunk.skyLight(x: 0, y: Int.min, z: 0) == nil)
    }

    @Test func terrainSkippingCannotTurnUnloadedLightIntoDarkness() throws {
        let section = NBT.compound(["Y": .byte(0), "BlockLight": .byteArray(Array(repeating: 0, count: 2048)),
                                    "SkyLight": .byteArray(Array(repeating: -1, count: 2048))])
        let saved = Fixtures.chunk(x: 0, z: 0, sections: [section], extra: ["isLightOn": .byte(1)]).serialized()
        let full = try Chunk(nbt: NBT.read(saved).value)
        let terrain = try Chunk(nbt: NBT.read(saved, skipping: Chunk.keysNotNeededForTerrain).value)
        #expect(full.isLightOn && full.blockLight(x: 0, y: 0, z: 0) == 0)
        #expect(!terrain.isLightOn && terrain.sections[0].blockLight == nil)
        #expect(terrain.blockLight(x: 0, y: 0, z: 0) == nil && terrain.skyLight(x: 0, y: 0, z: 0) == nil)
    }

    private func type(limit: NBT? = nil, provider: NBT? = nil) -> NBT {
        var fields: [String: NBT] = ["min_y": .int(-64), "height": .int(384), "logical_height": .int(384), "has_ceiling": .byte(0)]
        fields["monster_spawn_block_light_limit"] = limit
        fields["monster_spawn_light_level"] = provider
        return .compound(fields)
    }

    private func world(at root: URL, types: [String: NBT], packs: [String] = ["vanilla"], version: Int32 = 5023) throws -> World {
        let settings = NBT.compound(["dimensions": .compound(types.mapValues { .compound(["type": $0]) })])
        let data = NBT.compound(["LevelName": .string("Light Metadata"), "DataVersion": .int(version), "WorldGenSettings": settings,
                                 "DataPacks": .compound(["Enabled": .list(.string, packs.map(NBT.string))])])
        try Fixtures.writeGzippedNBT(.compound(["Data": data]), to: root.appendingPathComponent("level.dat"))
        return try World(contentsOf: root)
    }

    @Test func resourceSpawnLightFollowsTheSavedTypeRatherThanTheFolderName() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let world = try world(at: root, types: ["minecraft:overworld": .string("the_nether"),
            "example:sky": .string("overworld"), "example:caves": .string("overworld_caves"), "example:void": .string("the_end")])
        let before = try Data(contentsOf: root.appendingPathComponent("level.dat"))
        let values: [(String, Int, ClosedRange<Int>)] = [
            ("the_nether", 15, 7...7), ("overworld", 0, 0...7),
            ("overworld_caves", 0, 0...7), ("the_end", 0, 15...15)
        ]
        let entries = try values.map { id, limit, range in
            let json: [String: Any] = ["min_y": -64, "height": 384, "logical_height": 384, "has_ceiling": false,
                "monster_spawn_block_light_limit": limit, "monster_spawn_light_level": ["type": "uniform",
                    "min_inclusive": range.lowerBound, "max_inclusive": range.upperBound]]
            return TestZIP.Entry(path: "data/minecraft/dimension_type/\(id).json", text: "",
                                 data: try JSONSerialization.data(withJSONObject: json))
        }
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"fixture","world_version":1}"#)
        ] + entries))))
        #expect(try world.dimensionTypes().isEmpty)
        let types = try world.dimensionTypes(assets: assets)
        #expect(types["minecraft:overworld"]?.monsterSpawnBlockLightLimit == 15)
        #expect(types["minecraft:overworld"]?.monsterSpawnLightLevel == 7...7)
        for id in ["example:sky", "example:caves"] {
            #expect(types[id]?.monsterSpawnBlockLightLimit == 0)
            #expect(types[id]?.monsterSpawnLightLevel == 0...7)
        }
        #expect(types["example:void"]?.monsterSpawnBlockLightLimit == 0)
        #expect(types["example:void"]?.monsterSpawnLightLevel == 15...15)
        #expect(try Data(contentsOf: root.appendingPathComponent("level.dat")) == before)
    }

    @Test func inlineLightFieldsAreIndependentAndNeverAcquireGuessedDefaults() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let uniform = NBT.compound(["type": .string("uniform"), "min_inclusive": .int(2), "max_inclusive": .int(10)])
        let constant = NBT.compound(["type": .string("minecraft:constant"), "value": .int(4)])
        let unknown = NBT.compound(["type": .string("minecraft:clamped"), "min_inclusive": .int(0), "max_inclusive": .int(7)])
        let world = try world(at: root, types: ["example:missing": type(), "example:uniform": type(limit: .int(6), provider: uniform),
            "example:constant": type(limit: .int(3), provider: constant), "example:scalar": type(limit: .int(15), provider: .int(0)),
            "example:badlimit": type(limit: .int(16), provider: .int(7)), "example:unknown": type(limit: .int(1), provider: unknown),
            "example:unverified": .string("overworld")], version: 9999)
        let types = try world.dimensionTypes()
        #expect(types.count == 6)
        #expect(types["example:missing"]?.monsterSpawnBlockLightLimit == nil)
        #expect(types["example:missing"]?.monsterSpawnLightLevel == nil)
        #expect(types["example:uniform"]?.monsterSpawnBlockLightLimit == 6)
        #expect(types["example:uniform"]?.monsterSpawnLightLevel == 2...10)
        #expect(types["example:constant"]?.monsterSpawnLightLevel == 4...4)
        #expect(types["example:scalar"]?.monsterSpawnLightLevel == 0...0)
        #expect(types["example:badlimit"]?.monsterSpawnBlockLightLimit == nil)
        #expect(types["example:badlimit"]?.monsterSpawnLightLevel == 7...7)
        #expect(types["example:unknown"]?.monsterSpawnBlockLightLimit == 1)
        #expect(types["example:unknown"]?.monsterSpawnLightLevel == nil)
        #expect(types.values.allSatisfy { $0.buildRange == -64...319 })
    }

    @Test func invalidInlineProvidersDoNotHideValidBuildLimits() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providers: [NBT] = [.int(-1), .int(16), .string("7"), .double(7.5), .compound(["value": .int(7)]),
            .compound(["type": .string("uniform"), "min_inclusive": .int(9), "max_inclusive": .int(8)]),
            .compound(["type": .string("uniform"), "min_inclusive": .int(0)]),
            .compound(["type": .string("mod:uniform"), "min_inclusive": .int(0), "max_inclusive": .int(7)])]
        let definitions = Dictionary(uniqueKeysWithValues: providers.enumerated().map {
            ("example:bad\($0.offset)", type(limit: .int(2), provider: $0.element))
        })
        let types = try world(at: root, types: definitions).dimensionTypes()
        #expect(types.count == providers.count)
        #expect(types.values.allSatisfy { $0.monsterSpawnLightLevel == nil && $0.monsterSpawnBlockLightLimit == 2 && $0.height == 384 })
    }

    @Test func packJSONLightOverridesStayIndependentOfVanillaAndBuildBounds() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = root.appendingPathComponent("datapacks/Light")
        try Fixtures.write(Array(#"{"pack":{"min_format":121,"max_format":121,"description":"Light fixture"}}"#.utf8),
                           to: pack.appendingPathComponent("pack.mcmeta"))
        let file = pack.appendingPathComponent("data/minecraft/dimension_type/overworld.json")
        let world = try world(at: root, types: ["example:remapped": .string("overworld")], packs: ["vanilla", "file/Light"])
        let cases: [(String, String, Int?, ClosedRange<Int>?)] = [
            ("4", #"{"type":"uniform","min_inclusive":3,"max_inclusive":11}"#, 4, 3...11),
            ("15", "7", 15, 7...7), ("0", #"{"type":"constant","value":12}"#, 0, 12...12),
            ("true", "7", nil, 7...7), ("-1", "7", nil, 7...7), ("4.5", "7", nil, 7...7),
            ("0", "true", 0, nil), ("0", "7.5", 0, nil), ("0", "16", 0, nil),
            ("0", #"{"type":"uniform","min_inclusive":8,"max_inclusive":7}"#, 0, nil),
            ("0", #"{"type":"mod:uniform","min_inclusive":0,"max_inclusive":7}"#, 0, nil)
        ]
        for (limit, provider, expectedLimit, expectedRange) in cases {
            let json = "{\"min_y\":0,\"height\":128,\"logical_height\":128,\"has_ceiling\":false,\"monster_spawn_block_light_limit\":\(limit),\"monster_spawn_light_level\":\(provider)}"
            try Fixtures.write(Array(json.utf8), to: file)
            let result = try #require(try world.dimensionTypes()["example:remapped"])
            #expect(result.buildRange == 0...127)
            #expect(result.monsterSpawnBlockLightLimit == expectedLimit)
            #expect(result.monsterSpawnLightLevel == expectedRange)
            #expect(try Data(contentsOf: file) == Data(json.utf8))
        }
    }
}
