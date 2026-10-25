import Foundation
import ChunkseeKitTestSupport
import Testing
import ChunkseeKit

@Suite struct RegionVisitTests {
    @Test func aCombinedVisitRetainsTimeAndContentsAndSkipsOnlyTheBrokenChunk() throws {
        let (root, dimension) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var positions: [String] = [], times = [Int](repeating: 0, count: 1024)
        var containers: [ItemContainer] = [], supported = 0
        let skipping = Chunk.keysNotNeededForTerrain.subtracting(["structures", "block_entities"])
        try dimension.forEachChunk(regionX: -1, regionZ: -1, skipping: skipping) { x, z, nbt in
            positions.append("\(x),\(z)")
            times[z * 32 + x] = Chunk.inhabitedTime(in: nbt) ?? 0
            containers += ItemContainer.containers(inChunk: nbt)
            if let chunk = try? Chunk(nbt: nbt) {
                supported += 1
                #expect(chunk.inhabitedTime == 72_000)
                #expect(chunk.block(x: 0, y: 64, z: 0)?.id == "minecraft:stone")
            }
        }
        #expect(positions == ["0,0", "31,30"])
        #expect(times[0] == 5 && times[30 * 32 + 31] == 72_000)
        #expect(times == (try dimension.inhabitedTimes(regionX: -1, regionZ: -1)))
        #expect(containers.count == 1 && containers.first?.items.first?.id == "minecraft:diamond")
        #expect(supported == 1) // legacy metadata remains readable without a terrain decoder
    }

    @Test func callersCanOmitSectionsWithoutLosingCurrentOrLegacyMetadata() throws {
        let (root, dimension) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var times: [Int] = []
        try dimension.forEachChunk(regionX: -1, regionZ: -1, skipping: Chunk.keysNotNeededForInhabitedTime) { _, _, nbt in
            #expect(nbt["sections"] == nil && nbt["block_entities"] == nil)
            if let ticks = Chunk.inhabitedTime(in: nbt) { times.append(ticks) }
        }
        #expect(times == [5, 72_000])
    }

    @Test func everyFolderUsesTheCanonicalURLAndItsOwnChunks() throws {
        let (root, dimension) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for (folder, name) in [(ChunkseeKit.Dimension.Folder.terrain, "region"), (.entities, "entities"), (.pointsOfInterest, "poi")] {
            #expect(dimension.regionURL(folder, x: -1, z: -1) == dimension.url.appendingPathComponent("\(name)/r.-1.-1.mca"))
        }
        let mob = Fixtures.mob(["id": .string("minecraft:wolf"), "Health": .float(8),
                               "Pos": .list([.double(-1), .double(64), .double(-1)])])
        try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 31, nbt: .compound([
            "DataVersion": .int(5023), "Entities": .list([mob]),
        ]))]), to: dimension.regionURL(.entities, x: -1, z: -1))
        var creatures: [Creature] = []
        try dimension.forEachChunk(.entities, regionX: -1, regionZ: -1) { x, z, nbt in
            #expect(x == 31 && z == 31)
            creatures += Creature.creatures(inEntityChunk: nbt)
        }
        #expect(creatures == (try dimension.creatures(regionX: -1, regionZ: -1)))
        #expect(creatures.map(\.id) == ["minecraft:wolf"])
        try Fixtures.write(try Fixtures.region([.init(localX: 1, localZ: 2, nbt: .compound(["sentinel": .string("POI")]))]),
                           to: dimension.regionURL(.pointsOfInterest, x: -1, z: -1))
        var poiVisits = 0
        try dimension.forEachChunk(.pointsOfInterest, regionX: -1, regionZ: -1) { x, z, nbt in
            poiVisits += 1
            #expect(x == 1 && z == 2 && nbt["sentinel"]?.string == "POI")
        }
        #expect(poiVisits == 1)
    }

    @Test func callbackCancellationPropagatesAndStopsBeforeTheNextChunk() throws {
        let (root, dimension) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var visits = 0
        #expect(throws: CancellationError.self) {
            try dimension.forEachChunk(regionX: -1, regionZ: -1) { _, _, _ in
                visits += 1
                throw CancellationError()
            }
        }
        #expect(visits == 1)
    }

    @Test func missingRegionsAreEmptyAndOpeningErrorsPropagate() throws {
        let (root, dimension) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var visits = 0
        try dimension.forEachChunk(regionX: 8, regionZ: 9) { _, _, _ in visits += 1 }
        #expect(visits == 0)
        try Fixtures.write([1], to: dimension.regionURL(x: 8, z: 9))
        #expect(throws: RegionError.truncatedHeader) {
            try dimension.forEachChunk(regionX: 8, regionZ: 9) { _, _, _ in visits += 1 }
        }
        #expect(visits == 0)
    }

    private func fixture() throws -> (URL, ChunkseeKit.Dimension) {
        let root = try Fixtures.tempDirectory()
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Streamed region")])]),
                                    to: root.appendingPathComponent("level.dat"))
        let chest = NBT.compound(["id": .string("minecraft:chest"), "x": .int(-1), "y": .int(64), "z": .int(-17),
                                  "Items": .list([.compound(["id": .string("minecraft:diamond"), "count": .int(2)])])])
        let modern = Fixtures.chunk(x: -1, z: -2, dataVersion: 5023,
                                    sections: [Fixtures.section(y: 4, palette: [.string("minecraft:stone")])],
                                    extra: ["InhabitedTime": .long(72_000), "block_entities": .list([chest])])
        let legacy = NBT.compound(["DataVersion": .int(1343), "Level": .compound(["InhabitedTime": .long(5)])])
        var bytes = try Fixtures.region([.init(localX: 0, localZ: 0, nbt: legacy),
                                         .init(localX: 31, localZ: 30, nbt: modern),
                                         .init(localX: 2, localZ: 0, nbt: .compound([:]))])
        let badSector = bytes[8..<11].reduce(0) { $0 * 256 + Int($1) }
        bytes[badSector * 4096 + 4] = 99 // one unreadable chunk must not hide either valid one
        try Fixtures.write(bytes, to: root.appendingPathComponent("dimensions/minecraft/overworld/region/r.-1.-1.mca"))
        return (root, try #require(try World(contentsOf: root).dimension("overworld")))
    }
}
