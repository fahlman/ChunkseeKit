import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct RegionFactsTests {
    let region = RegionPosition(x: -1, z: 0)

    func terrain(full: Bool = true) -> NBT {
        var blocks = [Int](repeating: 0, count: 4096)
        for i in 0..<128 { blocks[i] = 1 }
        var biomes = [Int](repeating: 0, count: 64)
        for i in 0..<16 { biomes[i] = 1 }
        let section = Fixtures.section(y: 3, palette: [.string("minecraft:air"), .string("minecraft:diamond_ore"),
                                                     .string("minecraft:gold_ore")], indices: blocks,
                                       biomes: ["minecraft:plains", "minecraft:lush_caves", "minecraft:deep_dark"],
                                       biomeIndices: biomes, biomeBits: 2)
        return Fixtures.chunk(x: -1, z: 0, dataVersion: 5023, sections: [section], extra: [
            "status": .string(full ? "minecraft:full" : "minecraft:biomes"), "InhabitedTime": .long(2400),
            "Heightmaps": .compound(["WORLD_SURFACE": .longArray(Fixtures.pack([Int](repeating: 128, count: 256), bits: 9))]),
            "block_entities": .list([
                .compound(["id": .string("minecraft:chest"), "x": .int(-1), "y": .int(63), "z": .int(0),
                           "Items": .list([.compound(["id": .string("minecraft:diamond"), "count": .int(3)])])]),
                .compound(["id": .string("minecraft:oak_sign"), "x": .int(-2), "y": .int(63), "z": .int(0),
                           "front_text": .compound(["messages": .list([.string("Hello")])])]),
                .compound(["id": .string("minecraft:mob_spawner"), "x": .int(-3), "y": .int(20), "z": .int(0),
                           "SpawnData": .compound(["entity": .compound(["id": .string("minecraft:zombie")])])]),
            ]),
            "structures": .compound(["starts": .compound(["minecraft:jungle_pyramid": .compound([
                "id": .string("minecraft:jungle_pyramid"), "ChunkX": .int(-1), "ChunkZ": .int(0),
                "Children": .list([.compound(["id": .string("minecraft:tejp"), "HPos": .int(63),
                                             "BB": .intArray([-16, 63, 0, -4, 75, 12])])]),
            ])])]),
        ])
    }

    var entityChunk: NBT {
        .compound(["DataVersion": .int(5023), "Entities": .list([
            Fixtures.mob(["id": .string("minecraft:wolf"), "Health": .float(6),
                       "Owner": Fixtures.uuidInts(UUID(uuidString: "06D119DA-BC79-410F-8F7B-062CE442A86D")!),
                       "Pos": .list([.double(-4), .double(63), .double(0)])]),
            .compound(["id": .string("minecraft:chest_minecart"), "Pos": .list([.double(-2.5), .double(30), .double(0)]),
                       "UUID": .intArray([1, 2, 3, 4]),
                       "Items": .list([.compound(["id": .string("minecraft:rail"), "count": .int(16)])])]),
        ])])
    }

    var poiChunk: NBT {
        .compound(["Sections": .compound(["3": .compound([
            "Valid": .byte(1), "Records": .list([.compound([
                "type": .string("minecraft:home"), "pos": .intArray([-1, 63, 0]), "free_tickets": .int(0),
            ])]),
        ])])])
    }

    func write(_ nbt: NBT, in folder: ChunkseeKit.Dimension.Folder, dimension: ChunkseeKit.Dimension) throws {
        try Fixtures.write(Fixtures.region([.init(localX: 31, localZ: 0, nbt: nbt)]),
                           to: dimension.regionURL(folder, at: region))
    }

    @Test func oneResultMatchesTheExistingReadersAndRetainsOnlyUsedBiomes() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        try write(entityChunk, in: .entities, dimension: dimension)
        try write(poiChunk, in: .pointsOfInterest, dimension: dimension)
        let facts = try dimension.scan(region: region)
        let old = try dimension.contents(regionX: region.x, regionZ: region.z)
        #expect(facts.dimension == dimension.id && facts.region == region)
        #expect(facts.containers == old.containers && facts.signs == old.signs && facts.spawners == old.spawners)
        #expect(facts.containers.count == 2 && facts.signs.count == 1 && facts.spawners.count == 1)
        #expect(facts.containers.first(where: \.isEntity)?.uuid == UUID(uuidString: "00000001-0000-0002-0000-000300000004"))
        #expect(facts.creatures == Creature.creatures(inEntityChunk: entityChunk))
        #expect(facts.creatures.first?.health == 6 && facts.creatures.first?.maximumHealth(enchantments: [:]) != nil)
        #expect(facts.pointsOfInterest == PointOfInterest.records(inChunk: poiChunk))
        #expect(facts.inhabitedTimes == (try dimension.inhabitedTimes(regionX: region.x, regionZ: region.z)))
        #expect(facts.structures == (try Chunk(nbt: terrain())).structureStarts.map { StructureFacts($0, pieceIDs: nil) })
        let chunk = try #require(facts.chunks.first)
        #expect(chunk.position == ChunkPosition(x: -1, z: 0))
        #expect(chunk.biomes == ["minecraft:lush_caves", "minecraft:plains"])
        #expect(chunk.sampledBiome == "minecraft:plains")
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 0)

        let encoder = PropertyListEncoder(), decoder = PropertyListDecoder()
        encoder.outputFormat = .binary
        let decoded = try decoder.decode(RegionFacts.self, from: encoder.encode(facts))
        #expect(decoded.options == facts.options && decoded.chunks == facts.chunks)
        #expect(decoded.containers == facts.containers && decoded.signs == facts.signs && decoded.spawners == facts.spawners)
        #expect(decoded.structures == facts.structures && decoded.creatures == facts.creatures)
        #expect(decoded.pointsOfInterest == facts.pointsOfInterest && decoded.inhabitedTimes == facts.inhabitedTimes)
        #expect(decoded.formats == facts.formats)
        #expect(decoded.paletteBlockIDs == facts.paletteBlockIDs)
    }

    @Test func partialAndLegacyChunksDoNotBecomeBuiltTerrainFacts() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let legacy = NBT.compound(["DataVersion": .int(1343), "Level": .compound([
            "Sections": .list([.compound(["Y": .byte(0), "Blocks": .byteArray([Int8](repeating: 1, count: 4096))])]),
            "InhabitedTime": .long(7200),
        ])])
        try Fixtures.write(Fixtures.region([
            .init(localX: 0, localZ: 0, nbt: terrain(full: false)),
            .init(localX: 1, localZ: 0, nbt: legacy),
            .init(localX: 2, localZ: 0, nbt: .compound(["DataVersion": .int(5023)])),
        ]), to: dimension.regionURL(at: region))
        let facts = try dimension.scan(region: region)
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 1)
        #expect(facts.inhabitedTimes[0] == 2400 && facts.inhabitedTimes[1] == 7200 && facts.inhabitedTimes[3] == 0)
        #expect(facts.chunks.isEmpty && facts.structures.isEmpty)
        #expect(facts.paletteBlockIDs.isEmpty)
        #expect(facts.containers.count == 1 && facts.signs.count == 1 && facts.spawners.count == 1)
    }

    @Test func missingTerrainDoesNotHideEntityOrPOIOnlyRegionsAndBrokenFilesAreExplicit() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let empty = try dimension.scan(region: region)
        #expect(empty.chunks.isEmpty && empty.containers.isEmpty)
        try write(entityChunk, in: .entities, dimension: dimension)
        try write(poiChunk, in: .pointsOfInterest, dimension: dimension)
        let facts = try dimension.scan(region: region)
        #expect(facts.chunks.isEmpty && !facts.creatures.isEmpty && !facts.pointsOfInterest.isEmpty)
        #expect(facts.paletteBlockIDs.isEmpty)
        var broken = try Fixtures.region([.init(localX: 0, localZ: 0, nbt: terrain())])
        broken[8192 + 4] = 99 // an unreadable chunk, beside independently readable entity/POI files
        try Fixtures.write(broken, to: dimension.regionURL(at: region))
        let skipped = try dimension.scan(region: region)
        #expect(skipped.chunks.isEmpty && skipped.formats.readable == 0)
        #expect(skipped.containers == facts.containers && skipped.creatures == facts.creatures)
        #expect(skipped.pointsOfInterest == facts.pointsOfInterest)
        try Fixtures.write([0, 1], to: dimension.regionURL(at: region))
        #expect(throws: RegionError.truncatedHeader) { try dimension.scan(region: region) }
    }

    @Test func samplingChoicesAreExplicitAndPersisted() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:the_nether", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        let facts = try dimension.scan(region: region, options: .init(biomeSampleY: 48, height: 384))
        #expect(facts.chunks.first?.sampledBiome == "minecraft:lush_caves")
        #expect(facts.options.biomeSampleY == 48 && facts.options.height == 384)
        #expect(throws: RegionScanError.invalidHeight(0)) { try dimension.scan(region: region, options: .init(height: 0)) }
        #expect(throws: RegionScanError.invalidRegion(.init(x: Int.max, z: 0))) {
            try dimension.scan(region: .init(x: Int.max, z: 0))
        }
    }

    @Test func retainedBiomeMembershipDoesNotChangeTheSurfaceSample() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        let selections: [Set<String>?] = [nil, [], ["minecraft:lush_caves", "minecraft:deep_dark"]]
        for selection in selections {
            let options = RegionScanOptions(biomeIDs: selection, height: 384)
            let facts = try dimension.scan(region: region, options: options)
            let chunk = try #require(facts.chunks.first)
            #expect(chunk.sampledBiome == "minecraft:plains")
            let used: Set<String> = ["minecraft:lush_caves", "minecraft:plains"]
            #expect(chunk.biomes == (selection.map { used.intersection($0) } ?? used).sorted())
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let restored = try PropertyListDecoder().decode(RegionFacts.self, from: encoder.encode(facts))
            #expect(restored.options == options && restored.chunks == facts.chunks)
        }
    }

    @Test func compactStructuresKeepCompleteBoundsAndOnlyRequestedPieces() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        var fields = try #require(terrain().compound)
        fields["structures"] = .compound(["starts": .compound(["example:ruin": .compound([
            "id": .string("example:ruin"), "ChunkX": .int(-1), "ChunkZ": .int(0),
            "Children": .list([
                .compound(["id": .string("example:wall"), "BB": .intArray([-32, 20, -20, 20, 90, 30])]),
                .compound(["id": .string("example:door"), "BB": .intArray([-2, 60, 0, 0, 63, 1])]),
            ]),
        ])])])
        let saved = NBT.compound(fields)
        let raw = try #require(Chunk(nbt: saved).structureStarts.first)
        try write(saved, in: .terrain, dimension: dimension)
        let selections: [Set<String>?] = [nil, [], ["example:door"]]
        for selection in selections {
            let facts = try dimension.scan(region: region, options: .init(structurePieceIDs: selection))
            let compact = try #require(facts.structures.first)
            #expect(compact.id == raw.id && compact.chunkX == raw.chunkX && compact.chunkZ == raw.chunkZ)
            #expect(compact.bounds == raw.bounds)
            #expect(compact.pieces == raw.pieces.filter { selection?.contains($0.id) ?? true })
            let restored = try PropertyListDecoder().decode(RegionFacts.self, from: PropertyListEncoder().encode(facts))
            #expect(restored.structures == facts.structures && restored.options == facts.options)
        }
        #expect(try Chunk(nbt: saved).structureStarts == [raw])
    }

    @Test func compactScanPreservesSurfaceSamplingWithMissingOrMalformedHeightmaps() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let maps: [NBT?] = [terrain()["Heightmaps"], nil,
                           .compound(["WORLD_SURFACE": .longArray([0]), "OTHER": .longArray([0])])]
        for map in maps {
            var fields = try #require(terrain().compound)
            fields["Heightmaps"] = map
            let saved = NBT.compound(fields), raw = try Chunk(nbt: saved)
            try write(saved, in: .terrain, dimension: dimension)
            for height in [nil, 384] as [Int?] {
                let facts = try dimension.scan(region: region, options: .init(biomeIDs: [], height: height))
                let expected = raw.surfaceY(x: 8, z: 8, height: height).flatMap { raw.biome(x: 8, y: $0, z: 8) }
                #expect(facts.chunks.first?.sampledBiome == expected)
                #expect(facts.chunks.first?.biomes.isEmpty == true)
            }
        }
    }

    @Test func staleInterpretationsAndMalformedGridSizesCannotBeLoaded() throws {
        let facts = RegionFacts(dimension: "minecraft:overworld", region: region, options: .init())
        let data = try JSONEncoder().encode(facts)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let currentVersion = object["version"]
        var resolvedHealthArchive = object
        var previousVersion = try #require(currentVersion as? [String: Any])
        previousVersion["revision"] = 34
        resolvedHealthArchive["version"] = previousVersion
        resolvedHealthArchive["enchantments"] = [String: Any]()
        resolvedHealthArchive["creatures"] = [["id": "minecraft:cat", "x": 0, "y": 64, "z": 0,
                                               "health": 6, "maxHealth": 10] as [String: Any]]
        let previous = try JSONSerialization.data(withJSONObject: resolvedHealthArchive)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: previous) }
        object["version"] = RegionFacts.interpretationVersion.revision
        let stale = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: stale) }
        var beforeCatalog = object
        beforeCatalog["version"] = 6
        beforeCatalog.removeValue(forKey: "paletteBlockIDs")
        let oldShape = try JSONSerialization.data(withJSONObject: beforeCatalog)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: oldShape) }
        object["version"] = currentVersion
        object["inhabitedTimes"] = [0]
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegionFacts.self, from: malformed) }
    }

    @Test func cancellationThrowsInsteadOfReturningCacheablePartialFacts() async throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try dimension.scan(region: region)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func extremeSavedSectionCoordinatesNarrowBeforeSharedBiomeLookup() throws {
        let narrowed = NBT.compound(["Y": .long(Int64.min)])
        let valid = Fixtures.section(y: 4, palette: [.string("minecraft:stone")])
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [narrowed, valid]))
        #expect(chunk.sections.map(\.y) == [0, 4])
        #expect(chunk.biome(x: 8, y: 64, z: 8) == "minecraft:plains")
        var paletteBlockIDs = Set<String>()
        let facts = try TerrainChunkFacts(chunk, at: .init(x: 0, z: 0), options: .init(biomeSampleY: 64),
                                          paletteBlockIDs: &paletteBlockIDs)
        #expect(facts.sampledBiome == "minecraft:plains")
    }

    @Test func paletteCatalogKeepsUnusedAndModdedNamesWithoutCounting() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        let section = Fixtures.section(y: 0, palette: [
            .compound(["Name": .string("minecraft:stone")]),
            .compound(["Name": .string("minecraft:oak_leaves"), "Properties": .compound(["persistent": .string("true")])]),
            .compound(["Name": .string("minecraft:oak_leaves"), "Properties": .compound(["persistent": .string("false")])]),
            .compound(["Name": .string("example:glowing_brick")])
        ], indices: [Int](repeating: 0, count: 4096))
        let duplicate = Fixtures.section(y: 1, palette: [.string("minecraft:stone")])
        let partial = Fixtures.chunk(x: -31, z: 0, dataVersion: 5023,
            sections: [Fixtures.section(y: 0, palette: [.string("example:unfinished")])],
            extra: ["status": .string("minecraft:biomes")])
        try Fixtures.write(Fixtures.region([
            .init(localX: 0, localZ: 0, nbt: Fixtures.chunk(x: -32, z: 0, dataVersion: 5023, sections: [section, duplicate])),
            .init(localX: 1, localZ: 0, nbt: partial)
        ]), to: dimension.regionURL(at: region))
        let facts = try dimension.scan(region: region)
        #expect(facts.paletteBlockIDs == ["minecraft:stone", "minecraft:oak_leaves", "example:glowing_brick"])
        let restored = try PropertyListDecoder().decode(RegionFacts.self, from: PropertyListEncoder().encode(facts))
        #expect(restored.paletteBlockIDs == facts.paletteBlockIDs)
    }
}
