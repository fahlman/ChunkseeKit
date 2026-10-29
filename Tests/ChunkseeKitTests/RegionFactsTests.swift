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

    @Test func oneResultMatchesTheExistingReadersAndCountsOnlyUsedBiomesAndBlocks() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:overworld", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        try write(entityChunk, in: .entities, dimension: dimension)
        try write(poiChunk, in: .pointsOfInterest, dimension: dimension)
        let facts = try dimension.scan(region: region, options: .init(blockIDs: ["minecraft:diamond_ore", "minecraft:gold_ore"]))
        let old = try dimension.contents(regionX: region.x, regionZ: region.z)
        #expect(facts.dimension == dimension.id && facts.region == region)
        #expect(facts.containers == old.containers && facts.signs == old.signs && facts.spawners == old.spawners)
        #expect(facts.containers.count == 2 && facts.signs.count == 1 && facts.spawners.count == 1)
        #expect(facts.containers.first(where: \.isEntity)?.uuid == UUID(uuidString: "00000001-0000-0002-0000-000300000004"))
        #expect(facts.creatures == Creature.creatures(inEntityChunk: entityChunk))
        #expect(facts.creatures.first?.health == 6 && facts.creatures.first?.maxHealth != nil)
        #expect(facts.pointsOfInterest == PointOfInterest.records(inChunk: poiChunk))
        #expect(facts.inhabitedTimes == (try dimension.inhabitedTimes(regionX: region.x, regionZ: region.z)))
        #expect(facts.structures == (try Chunk(nbt: terrain())).structureStarts)
        let chunk = try #require(facts.chunks.first)
        #expect(chunk.position == ChunkPosition(x: -1, z: 0))
        #expect(chunk.biomes == ["minecraft:lush_caves", "minecraft:plains"])
        #expect(chunk.sampledBiome == "minecraft:plains")
        #expect(chunk.heightmaps["WORLD_SURFACE"] == [Int](repeating: 64, count: 256))
        #expect(chunk.blockDeposits == [BlockDeposit(id: "minecraft:diamond_ore", count: 128, minY: 48, maxY: 63)])
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 0)

        let encoder = JSONEncoder(), decoder = JSONDecoder()
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
        #expect(facts.formats.readable == 1 && facts.formats.legacy == 1 && facts.formats.unreadableTerrain == 1)
        #expect(facts.inhabitedTimes[1] == 7200 && facts.inhabitedTimes[3] == 0)
        #expect(facts.chunks.first?.isFullyGenerated == false)
        #expect(facts.chunks.first?.sampledBiome == nil && facts.chunks.first?.biomes.isEmpty == true)
        #expect(facts.chunks.first?.blockDeposits.isEmpty == true && facts.structures.isEmpty)
        #expect(facts.paletteBlockIDs.isEmpty)
        #expect(facts.containers.count == 1) // metadata still reads without claiming structures were built
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
        #expect(try dimension.scan(region: region).formats.unreadableTerrain == 1)
        try Fixtures.write([0, 1], to: dimension.regionURL(at: region))
        #expect(throws: RegionError.truncatedHeader) { try dimension.scan(region: region) }
    }

    @Test func samplingAndCountingChoicesAreExplicitAndPersisted() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "minecraft:the_nether", url: root)
        try write(terrain(), in: .terrain, dimension: dimension)
        let facts = try dimension.scan(region: region, options: .init(blockIDs: [], biomeSampleY: 48, height: 384))
        #expect(facts.chunks.first?.sampledBiome == "minecraft:lush_caves")
        #expect(facts.chunks.first?.blockDeposits.isEmpty == true)
        #expect(facts.options.biomeSampleY == 48 && facts.options.height == 384)
        let all = try dimension.scan(region: region)
        #expect(Set(all.chunks.first?.blockDeposits.map(\.id) ?? []) == ["minecraft:air", "minecraft:diamond_ore"])
        #expect(throws: RegionScanError.invalidHeight(0)) { try dimension.scan(region: region, options: .init(height: 0)) }
        #expect(throws: RegionScanError.invalidRegion(.init(x: Int.max, z: 0))) {
            try dimension.scan(region: .init(x: Int.max, z: 0))
        }
    }

    @Test func staleInterpretationsAndMalformedGridSizesCannotBeLoaded() throws {
        let facts = RegionFacts(dimension: "minecraft:overworld", region: region, options: .init())
        let data = try JSONEncoder().encode(facts)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let currentVersion = object["version"]
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

    @Test func paletteCatalogKeepsUnusedAndModdedNamesRegardlessOfCountingChoices() throws {
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
        let choices: [Set<String>?] = [nil, [], ["minecraft:diamond_ore"]]
        for selected in choices {
            let facts = try dimension.scan(region: region, options: .init(blockIDs: selected))
            #expect(facts.paletteBlockIDs == ["minecraft:stone", "minecraft:oak_leaves", "example:glowing_brick"])
            let deposits = try #require(facts.chunks.first).blockDeposits
            #expect(deposits.map(\.id) == (selected == nil ? ["minecraft:stone"] : []))
            let restored = try JSONDecoder().decode(RegionFacts.self, from: JSONEncoder().encode(facts))
            #expect(restored.paletteBlockIDs == facts.paletteBlockIDs)
        }
    }
}
