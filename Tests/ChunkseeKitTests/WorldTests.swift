import Foundation
import ChunkseeKitTestSupport
import Testing
@testable import ChunkseeKit

@Suite struct WorldTests {
    let playerUUID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

    func uuidInts(_ uuid: UUID) -> NBT { Fixtures.uuidInts(uuid) }

    @Test func modernLayout() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("New World"),
            "DataVersion": .int(5119),
            "Version": .compound(["Id": .int(5119), "Name": .string("26.4-snapshot-1"), "Snapshot": .byte(1)]),
            "version_history": .list([.int(4790), .int(5009), .int(5119)]),
            "difficulty_settings": .compound(["difficulty": .string("hard"), "hardcore": .byte(0), "locked": .byte(1)]),
            "singleplayer_uuid": uuidInts(playerUUID),
            "spawn": .compound(["dimension": .string("minecraft:overworld"), "pos": .intArray([10, 70, -20])]),
            "LastPlayed": .long(1_790_000_000_000),
        ])]), to: dir.appendingPathComponent("level.dat"))
        try Fixtures.writeGzippedNBT(.compound(["DataVersion": .int(5119), "data": .compound(["seed": .long(-42)])]),
                                     to: dir.appendingPathComponent("data/minecraft/world_gen_settings.dat"))
        try Fixtures.writeGzippedNBT(.compound(["Health": .float(20)]),
                                     to: dir.appendingPathComponent("players/data/\(playerUUID.uuidString.lowercased()).dat"))
        try Fixtures.write(Array("{}".utf8), to: dir.appendingPathComponent("players/stats/\(playerUUID.uuidString.lowercased()).json"))

        // Block (-5, 64, -3) is in chunk (-1, -1), region (-1, -1), local (31, 31), section 4.
        let palette: [NBT] = [.compound(["": .string("minecraft:air")]), .compound(["id": .string("minecraft:diamond_ore")])]
        var indices = [Int](repeating: 0, count: 4096)
        indices[0 * 256 + 13 * 16 + 11] = 1
        let chunk = Fixtures.chunk(x: -1, z: -1, sections: [Fixtures.section(y: 4, palette: palette, indices: indices)])
        try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 31, nbt: chunk)]),
                           to: dir.appendingPathComponent("dimensions/minecraft/overworld/region/r.-1.-1.mca"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/minecraft/the_nether/region"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dimensions/mymod/deep/mines/region"),
                                                withIntermediateDirectories: true)

        let world = try World(contentsOf: dir)
        #expect(world.usesDimensionsFolderForVanilla)
        #expect(world.level.name == "New World")
        #expect(world.level.versionHistory == [4790, 5009, 5119])
        #expect(world.level.difficulty == "hard")
        #expect(world.level.difficultyLocked == true)
        #expect(world.level.singleplayerUUID == playerUUID)
        #expect(world.level.spawnPosition.map { [$0.x, $0.y, $0.z] } == [10, 70, -20])
        #expect(try world.seed() == -42)
        #expect(world.dimensions().map(\.id) == ["minecraft:overworld", "minecraft:the_nether", "mymod:deep/mines"])
        #expect(world.playerUUIDs() == [playerUUID])
        #expect(try world.playerData(playerUUID)?["Health"] == .float(20))
        #expect(world.playerJSON(playerUUID, kind: "stats") != nil)

        let overworld = try #require(world.dimension("overworld"))
        #expect(try overworld.block(x: -5, y: 64, z: -3)?.id == "minecraft:diamond_ore")
        #expect(try overworld.block(x: -6, y: 64, z: -3)?.isAir == true)
        #expect(try overworld.chunk(x: 0, z: 0) == nil)
    }

    @Test func legacyLayout() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound([
            "LevelName": .string("Old World"),
            "DataVersion": .int(3955),
            "Difficulty": .byte(1),
            "hardcore": .byte(1),
            "SpawnX": .int(1), "SpawnY": .int(2), "SpawnZ": .int(3),
            "WorldGenSettings": .compound(["seed": .long(12345)]),
            "Player": .compound(["UUID": uuidInts(playerUUID), "Health": .float(7)]),
        ])]), to: dir.appendingPathComponent("level.dat"))
        for sub in ["region", "DIM-1/region", "DIM1/region"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }

        let world = try World(contentsOf: dir)
        #expect(!world.usesDimensionsFolderForVanilla)
        #expect(world.level.difficulty == "easy")
        #expect(world.level.isHardcore == true)
        #expect(world.level.singleplayerUUID == playerUUID)
        #expect(try world.seed() == 12345)
        #expect(world.dimensions().map(\.id) == ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end"])
        #expect(world.dimension("the_nether")?.url.lastPathComponent == "DIM-1")
        #expect(try world.playerData(playerUUID)?["Health"] == .float(7))
    }

    @Test(arguments: [false, true]) func regionPathsReadEveryFolderInOldAndModernWorlds(modern: Bool) throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string("Paths")])]),
                                    to: root.appendingPathComponent("level.dat"))
        let paths = modern
            ? ["minecraft:overworld": "dimensions/minecraft/overworld", "minecraft:the_nether": "dimensions/minecraft/the_nether",
               "example:deep/mines": "dimensions/example/deep/mines"]
            : ["minecraft:overworld": "", "minecraft:the_nether": "DIM-1", "example:deep/mines": "dimensions/example/deep/mines"]
        for path in paths.values {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path).appendingPathComponent("region"),
                                                    withIntermediateDirectories: true)
        }
        let world = try World(contentsOf: root)
        for (id, path) in paths {
            let dimension = try #require(world.dimension(id))
            for (folder, directory, x, z) in [(Dimension.Folder.terrain, "region", -1, 2), (.entities, "entities", 0, -3),
                                               (.pointsOfInterest, "poi", 4, 0)] {
                let url = dimension.regionURL(folder, x: x, z: z)
                let base = path.isEmpty ? root : root.appendingPathComponent(path)
                let expected = base.appendingPathComponent(directory).appendingPathComponent("r.\(x).\(z).mca")
                #expect(url == expected)
                let payload = NBT.compound(["source": .string(id + "/" + directory)])
                try Fixtures.write(try Fixtures.region([.init(localX: 31, localZ: 0, nbt: payload)]), to: url)
                let region = try #require(try dimension.region(folder, x: x, z: z))
                #expect(region.url == url && region.x == x && region.z == z)
                #expect(try region.chunkNBT(localX: 31, localZ: 0) == payload)
                #expect(dimension.regionFiles(folder).map(\.url) == [url])
            }
        }
    }

    @Test func regionPathKeepsMissingAndUnreadableFilesDistinct() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dimension = Dimension(id: "example:uncreated", url: root.appendingPathComponent("Not Created"))
        let url = dimension.regionURL(x: -5, z: 9)
        #expect(!FileManager.default.fileExists(atPath: dimension.url.path))
        #expect(try dimension.region(x: -5, z: 9) == nil)
        try Fixtures.write([0], to: url)
        #expect(throws: RegionError.truncatedHeader) { try dimension.region(x: -5, z: 9) }
    }

    @Test func missingLevelDat() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: WorldError.missingLevelDat) { try World(contentsOf: dir) }
    }

    @Test func findsSavedWorldsInEveryGameFolderButNotBackups() throws {
        let root = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        func world(_ path: String) throws {
            try Fixtures.writeGzippedNBT(.compound(["Data": .compound(["LevelName": .string(path)])]),
                                         to: root.appendingPathComponent(path).appendingPathComponent("level.dat"))
        }
        try world("saves/Classic")
        try world("vanilla/release/saves/Ryan's Realm")
        try world("vanilla/aprilfools/blue/saves/blue")
        try world("vanilla/release/backups/Ryan's Realm-backup")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("vanilla/release/saves/Not a World"),
                                                withIntermediateDirectories: true)
        let prefix = root.resolvingSymlinksInPath().path.count + 1  // the temporary folder is reached through /private
        let found = World.saved(under: root).map { String($0.resolvingSymlinksInPath().path.dropFirst(prefix)) }
        #expect(found == ["saves/Classic", "vanilla/aprilfools/blue/saves/blue", "vanilla/release/saves/Ryan's Realm"])
        #expect(World.saved(under: root, depth: 1).count == 1)  // only saves/Classic is that shallow
        #expect(World.saved(under: root.appendingPathComponent("vanilla/release/saves")).map(\.lastPathComponent) == ["Ryan's Realm"])
    }

    @Test func eachVanillaDimensionListsTheBiomesItCanHave() {
        func biomes(_ id: String) -> [String] { Dimension(id: id, url: URL(fileURLWithPath: "/")).vanillaBiomes }
        #expect(biomes("minecraft:overworld").count == 56 && Set(biomes("minecraft:overworld")).count == 56)
        #expect(biomes("minecraft:overworld").contains("minecraft:mushroom_fields"))
        #expect(biomes("minecraft:overworld").contains("minecraft:dappled_forest"))   // new in 26.3
        #expect(Set(biomes("minecraft:the_nether")) == ["minecraft:nether_wastes", "minecraft:soul_sand_valley", "minecraft:crimson_forest",
                                                         "minecraft:warped_forest", "minecraft:basalt_deltas"])
        #expect(biomes("minecraft:the_end").count == 5)
        #expect(biomes("mymod:skylands").isEmpty)
    }

    @Test func snapshotBiomeCatalogAddsIceCavesOnlyInItsOverworld() {
        for id in ["minecraft:overworld", "minecraft:the_nether", "minecraft:the_end", "mymod:skylands"] {
            let dimension = Dimension(id: id, url: URL(fileURLWithPath: "/"))
            let original = dimension.vanillaBiomes
            for version: Int? in [nil, SaveVersion.java26_3, 5124, SaveVersion.java26_4Snapshot5, 5126] {
                let expected = id == "minecraft:overworld" && version == SaveVersion.java26_4Snapshot5
                    ? original + ["minecraft:ice_caves"] : original
                #expect(dimension.vanillaBiomes(dataVersion: version) == expected)
            }
        }
    }
}
