import ChunkseeIndex
import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct DimensionIndexTests {
    private let overworld = "minecraft:overworld"
    private let caves: Set<String> = ["minecraft:lush_caves"]
    private let a = RegionPosition(x: 0, z: 0)
    private let b = RegionPosition(x: 1, z: 0)

    @Test func firstPartialNotificationUsesTheCompleteReadSetButACompletedEmptyPassDoesNot() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2)
        try world.terrain(chunkX: 32, count: 5)
        let neverRead = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
        let available: Set<RegionPosition> = [a, b]
        #expect(neverRead.regionsToRead(available: available, selected: [a]) == available)
        #expect(neverRead.regionsToRead(available: available, selected: []) == available)
        let replacements = try neverRead.regionsToRead(available: available, selected: [a])
            .map { try world.scan($0, caves: caves) }
        let partial = neverRead.updating(available: available, selected: [a], replacements: replacements)
        let full = neverRead.updating(available: available, selected: nil, replacements: replacements)
        expectEquivalent(partial, full)
        #expect(partial.storage.first?.count == 7)
        #expect(partial.regionsToRead(available: available, selected: [a]) == [a])
        #expect(partial.regionsToRead(available: [b], selected: [a]) == [])
        let emptyPass = neverRead.updating(available: available, selected: nil, replacements: [])
        #expect(emptyPass.regions.isEmpty)
        #expect(emptyPass.regionsToRead(available: available, selected: [a]) == [a])
        #expect(emptyPass.regionsToRead(available: available, selected: []) == [])
    }

    @Test func completeDimensionJoinsBoundaryFactsAndRetainsCompactContributions() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2)
        try world.terrain(chunkX: 32, count: 5)
        try world.entities(chunkX: 31)
        try world.entities(chunkX: -33) // entity-only negative region
        try world.poi(x: 511)
        try world.poi(x: 512)
        let negative = RegionPosition(x: -2, z: 0)
        let parts = try [negative, a, b].map { try world.scan($0, caves: caves) }
        let index = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
            .updating(available: [negative, a, b], selected: nil, replacements: Array(parts.reversed()))
        #expect(index.regions.count == 3)
        #expect(index.containers.map(\.x) == [496, 512])
        #expect(index.storage.map(\.id) == ["minecraft:diamond"])
        #expect(index.storage.first?.count == 7 && index.storage.first?.containers == 2)
        #expect(index.signs.count == 2 && index.spawners.count == 2 && index.structures.count == 2)
        #expect(index.creatures.count == 2 && index.creatures.allSatisfy { $0.group == .pet })
        #expect(index.creatures.first?.creature.x == -528)
        #expect(index.regions[a]?.creatures.count == 1) // the ordinary sheep is discarded
        #expect(index.formats == .init(readable: 2, legacy: 0))
        #expect(index.blocks.map(\.deposit.count) == [5, 2])
        #expect(index.blocks.allSatisfy { $0.deposit.block == .diamond && $0.deposit.minY == 0 && $0.deposit.maxY == 15 })
        #expect(index.portals.count == 1 && index.portals.first?.blocks.count == 4)
        #expect(index.biomeAreas.count == 2)
        #expect(Set(index.biomeAreas.map(\.biomeID)) == ["minecraft:plains", "minecraft:lush_caves"])
        #expect(index.biomeAreas.allSatisfy { $0.chunkCount == 2 })
        #expect(index.biomes.count == 2 && index.caveBiomes.count == 2)
    }

    @Test func partialReplacementMatchesACompletePassAndLeavesOldSnapshotIntact() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2)
        try world.terrain(chunkX: 32, count: 5)
        try world.poi(x: 511)
        try world.poi(x: 512)
        let first = try world.scan(a, caves: caves), second = try world.scan(b, caves: caves)
        let empty = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
        let initial = empty.updating(available: [a, b], selected: nil, replacements: [first, second])
        try world.terrain(chunkX: 32, count: 7, biome: "minecraft:desert")
        try world.poi(x: 512, type: "minecraft:home")
        let replacement = try world.scan(b, caves: caves)
        let updated = initial.updating(available: [a, b], selected: [b], replacements: [replacement])
        let complete = empty.updating(available: [a, b], selected: nil,
                                      replacements: [try world.scan(a, caves: caves), replacement])
        expectEquivalent(updated, complete)
        #expect(initial.storage.first?.count == 7)
        #expect(initial.portals.first?.blocks.count == 4)
        #expect(updated.storage.first?.count == 9)
        #expect(updated.portals.first?.blocks.count == 2)
        #expect(updated.signs.contains { $0.front.contains("count 7") })
        #expect(updated.spawners.contains { $0.mob == "minecraft:skeleton" })
        #expect(updated.biomeAreas.filter { $0.biomeID != "minecraft:lush_caves" }.count == 2)
    }

    @Test func failedReadDeletionAndSuccessfulEmptyReplacementRemainDifferent() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2)
        try world.terrain(chunkX: 32, count: 5)
        let initial = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
            .updating(available: [a, b], selected: nil,
                      replacements: [try world.scan(a, caves: caves), try world.scan(b, caves: caves)])
        let selections: [Set<RegionPosition>?] = [nil, [a]]
        for selection in selections {
            let failed = initial.updating(available: [a, b], selected: selection, replacements: [])
            expectEquivalent(failed, initial)
        }
        // A partial notification must not remove another region, even when its file is absent.
        let partial = initial.updating(available: [a], selected: [a], replacements: [])
        expectEquivalent(partial, initial)
        let deleted = initial.updating(available: [a], selected: [b], replacements: [])
        #expect(Set(deleted.regions.keys) == [a] && deleted.storage.first?.count == 2)
        let broad = initial.updating(available: [a], selected: nil, replacements: [])
        expectEquivalent(deleted, broad)
        try world.empty(a)
        let cleared = initial.updating(available: [a, b], selected: [a],
                                       replacements: [try world.scan(a, caves: caves)])
        #expect(cleared.regions.count == 2 && cleared.regions[a]?.containers.isEmpty == true)
        #expect(cleared.storage.first?.count == 5 && cleared.formats.readable == 1)
        let gone = cleared.updating(available: [], selected: nil, replacements: [])
        #expect(gone.regions.isEmpty && gone.containers.isEmpty && gone.blocks.isEmpty && gone.biomeAreas.isEmpty)
    }

    @Test func replacementsOutsideThePassOrWithDifferentIdentityOrPolicyAreIgnored() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2)
        try world.terrain(chunkX: 32, count: 5)
        try world.terrain(chunkX: 31, count: 9, dimension: "the_nether")
        let first = try world.scan(a, caves: caves), second = try world.scan(b, caves: caves)
        let initial = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
            .updating(available: [a], selected: nil, replacements: [first])
        let foreign = try world.scan(a, caves: caves, dimension: "the_nether")
        let otherPolicy = try world.scan(a, caves: [])
        expectEquivalent(initial.updating(available: [a, b], selected: [a],
                                           replacements: [second, foreign, otherPolicy]), initial)
        expectEquivalent(initial.updating(available: [a, b], selected: [], replacements: [second]), initial)
        expectEquivalent(initial.updating(available: [a], selected: nil, replacements: [second]), initial)
        let added = initial.updating(available: [a, b], selected: [b], replacements: [second])
        #expect(added.regions.count == 2 && added.storage.first?.count == 7)
    }

    @Test func explicitCavePolicyAvoidsDuplicatingSurfaceMembershipAndFormatsIncludeLegacy() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2, biome: "minecraft:lush_caves")
        let legacyRegion = RegionPosition(x: 2, z: 0)
        let dimension = try world.dimension()
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([
            "Level": .compound(["xPos": .int(64), "zPos": .int(0), "Sections": .list([
                .compound(["Y": .byte(0), "Blocks": .byteArray([Int8](repeating: 1, count: 4096))]),
            ])])
        ]))]), to: dimension.regionURL(at: legacyRegion))
        let legacy = try world.scan(legacyRegion, caves: caves)
        let empty = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
        let legacyOnly = empty.updating(available: [legacyRegion], selected: nil, replacements: [legacy])
        #expect(legacyOnly.formats.isOnlyLegacy && legacyOnly.formats.legacy == 1)
        let combined = legacyOnly.updating(available: [a, legacyRegion], selected: [a],
                                          replacements: [try world.scan(a, caves: caves)])
        #expect(combined.formats == .init(readable: 1, legacy: 1) && !combined.formats.isOnlyLegacy)
        #expect(combined.biomeAreas.count == 1 && combined.biomeAreas.first?.chunkCount == 1)
        #expect(combined.biomes[.init(x: 31, z: 0)] == "minecraft:lush_caves")
        let surfaceOnly = DimensionIndex(dimension: overworld, caveBiomeIDs: [], notableBlocks: world.catalog)
            .updating(available: [a], selected: nil, replacements: [try world.scan(a, caves: [])])
        #expect(surfaceOnly.caveBiomes.isEmpty && surfaceOnly.biomeAreas.count == 1)
    }

    @Test func paletteCatalogTracksRetainedRegionsWithoutBecomingNotableDeposits() throws {
        let world = try SavedWorld()
        defer { world.remove() }
        try world.terrain(chunkX: 31, count: 2, unusedBlockID: "minecraft:oak_leaves")
        try world.terrain(chunkX: 32, count: 5, unusedBlockID: "example:ruby_block")
        let empty = DimensionIndex(dimension: overworld, caveBiomeIDs: caves, notableBlocks: world.catalog)
        let initial = empty.updating(available: [a, b], selected: nil,
                                    replacements: [try world.scan(a, caves: caves), try world.scan(b, caves: caves)])
        let common: Set<String> = ["minecraft:air", "minecraft:stone", "minecraft:diamond_ore"]
        #expect(initial.paletteBlockIDs == common.union(["minecraft:oak_leaves", "example:ruby_block"]))
        #expect(initial.regions[a]?.paletteBlockIDs == common.union(["minecraft:oak_leaves"]))
        #expect(initial.blocks.map(\.deposit.count) == [5, 2])
        let failed = initial.updating(available: [a, b], selected: [b], replacements: [])
        #expect(failed.paletteBlockIDs == initial.paletteBlockIDs)

        try world.terrain(chunkX: 32, count: 7, unusedBlockID: "minecraft:farmland")
        let replacement = try world.scan(b, caves: caves)
        let changed = initial.updating(available: [a, b], selected: [b], replacements: [replacement])
        #expect(changed.paletteBlockIDs == common.union(["minecraft:oak_leaves", "minecraft:farmland"]))
        #expect(initial.paletteBlockIDs.contains("example:ruby_block"))
        expectEquivalent(changed, empty.updating(available: [a, b], selected: nil,
                                                replacements: [try world.scan(a, caves: caves), replacement]))

        let deleted = changed.updating(available: [b], selected: [a], replacements: [])
        #expect(deleted.paletteBlockIDs == common.union(["minecraft:farmland"]))
        try world.empty(b)
        let cleared = deleted.updating(available: [b], selected: [b], replacements: [try world.scan(b, caves: caves)])
        #expect(cleared.paletteBlockIDs.isEmpty && cleared.regions.count == 1)
        #expect(deleted.updating(available: [], selected: nil, replacements: []).paletteBlockIDs.isEmpty)
    }

    private func expectEquivalent(_ a: DimensionIndex, _ b: DimensionIndex) {
        #expect(Set(a.regions.keys) == Set(b.regions.keys))
        #expect(a.containers == b.containers && a.storage == b.storage && a.signs == b.signs)
        #expect(a.spawners == b.spawners && a.structures == b.structures && a.creatures == b.creatures)
        #expect(a.pointsOfInterest == b.pointsOfInterest && a.portals == b.portals)
        #expect(a.biomes == b.biomes && a.caveBiomes == b.caveBiomes && a.formats == b.formats)
        #expect(a.blocks == b.blocks)
        #expect(a.paletteBlockIDs == b.paletteBlockIDs)
        #expect(Set(a.biomeAreas.map(\.id)) == Set(b.biomeAreas.map(\.id)))
        #expect(a.biomeAreas.map(\.chunkCount).sorted() == b.biomeAreas.map(\.chunkCount).sorted())
    }

    private struct SavedWorld {
        let root: URL
        let catalog: NotableBlock.Catalog
        init() throws {
            catalog = try NotableBlockFixtures.catalog()
            root = try Fixtures.tempDirectory()
            try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
                "LevelName": .string("Shared index"), "DataVersion": .int(5023)
            ])]), to: root.appendingPathComponent("level.dat"))
            for id in ["overworld", "the_nether"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent("dimensions/minecraft/\(id)/region"),
                                                        withIntermediateDirectories: true)
            }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func dimension(_ id: String = "overworld") throws -> ChunkseeKit.Dimension {
            try #require(try World(contentsOf: root).dimension(id))
        }
        func scan(_ region: RegionPosition, caves: Set<String>, dimension id: String = "overworld") throws -> RegionIndex {
            RegionIndex(try dimension(id).scan(region: region,
                options: .init(blockIDs: catalog.blockIDs)), caveBiomeIDs: caves, notableBlocks: catalog)
        }
        func terrain(chunkX: Int, count: Int, biome: String = "minecraft:plains", dimension id: String = "overworld",
                     unusedBlockID: String? = nil) throws {
            var indices = [Int](repeating: 0, count: 4096)
            for i in 0..<count { indices[i] = 1 }
            let palette = ["minecraft:stone", "minecraft:diamond_ore"] + (unusedBlockID.map { [$0] } ?? [])
            let section = Fixtures.section(y: 0, palette: palette.map {
                .compound(["Name": .string($0)])
            }, indices: indices, biomes: [biome])
            let cave = Fixtures.section(y: -1, palette: [.compound(["Name": .string("minecraft:air")])],
                                        biomes: ["minecraft:lush_caves"])
            let x = Int32(chunkX * 16)
            let entities: [NBT] = [
                .compound(["id": .string("minecraft:chest"), "x": .int(x), "y": .int(64), "z": .int(0),
                           "Items": .list([.compound(["id": .string("minecraft:diamond"), "count": .int(Int32(count))])])]),
                .compound(["id": .string("minecraft:sign"), "x": .int(x), "y": .int(65), "z": .int(0),
                           "front_text": .compound(["messages": .list([.string("count \(count)")])])]),
                .compound(["id": .string("minecraft:mob_spawner"), "x": .int(x), "y": .int(66), "z": .int(0),
                           "SpawnData": .compound(["entity": .compound(["id": .string(count == 7 ? "minecraft:skeleton" : "minecraft:zombie")])])]),
            ]
            let structure: NBT = .compound(["starts": .compound(["minecraft:stronghold": .compound([
                "id": .string("minecraft:stronghold"), "ChunkX": .int(Int32(chunkX)), "ChunkZ": .int(0),
                "Children": .list([.compound(["id": .string("minecraft:shstart"), "BB": .intArray([x, 64, 0, x + 9, 73, 9])])])
            ])])])
            let chunk = Fixtures.chunk(x: chunkX, z: 0, dataVersion: 5023, sections: [cave, section],
                                       extra: ["block_entities": .list(entities), "structures": structure])
            try write(chunk, chunkX: chunkX, folder: .terrain, dimension: id)
        }
        func entities(chunkX: Int) throws {
            let values: [NBT] = [
                Fixtures.mob(["id": .string("minecraft:wolf"), "UUID": .intArray([1, 2, 3, Int32(chunkX)]),
                           "Owner": .intArray([5, 6, 7, 8]), "Health": .float(8),
                           "Pos": .list([.double(Double(chunkX * 16)), .double(64), .double(0)])]),
                Fixtures.mob(["id": .string("minecraft:sheep"), "Health": .float(8),
                           "Pos": .list([.double(Double(chunkX * 16)), .double(64), .double(1)])]),
            ]
            try write(.compound(["DataVersion": .int(5023), "Entities": .list(values)]),
                      chunkX: chunkX, folder: .entities)
        }
        func poi(x: Int, type: String = "minecraft:nether_portal") throws {
            let records: [NBT] = [64, 65].map { y in
                .compound(["type": .string(type), "pos": .intArray([Int32(x), Int32(y), 0]), "free_tickets": .int(0)])
            }
            let nbt: NBT = .compound(["DataVersion": .int(5023), "Sections": .compound([
                "4": .compound(["Valid": .byte(1), "Records": .list(records)])
            ])])
            try write(nbt, chunkX: x >> 4, folder: .pointsOfInterest)
        }
        func empty(_ region: RegionPosition) throws {
            let dimension = try dimension()
            for folder in ChunkseeKit.Dimension.Folder.allCases {
                let url = dimension.regionURL(folder, at: region)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            try Fixtures.write(try Fixtures.region([]), to: dimension.regionURL(at: region))
        }
        private func write(_ nbt: NBT, chunkX: Int, folder: ChunkseeKit.Dimension.Folder,
                           dimension id: String = "overworld") throws {
            let position = ChunkPosition(x: chunkX, z: 0)
            try Fixtures.write(try Fixtures.region([.init(localX: chunkX & 31, localZ: 0, nbt: nbt)]),
                               to: dimension(id).regionURL(folder, at: position.region))
        }
    }
}
