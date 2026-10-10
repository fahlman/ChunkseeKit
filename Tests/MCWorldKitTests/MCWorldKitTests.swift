import Foundation
import Testing
@testable import MCWorldKit

@Suite struct NBTTests {
    @Test func readsSpecExample() throws {
        // "hello world" example from the NBT specification.
        let bytes: [UInt8] = [0x0A, 0x00, 0x0B] + Array("hello world".utf8)
            + [0x08, 0x00, 0x04] + Array("name".utf8) + [0x00, 0x09] + Array("Bananrama".utf8) + [0x00]
        let (name, value) = try NBT.read(bytes)
        #expect(name == "hello world")
        #expect(value["name"]?.string == "Bananrama")
    }

    @Test func roundTripsEveryTagType() throws {
        let value = NBT.compound([
            "b": .byte(-5), "s": .short(-300), "i": .int(70000), "l": .long(.min), "f": .float(1.5), "d": .double(-2.25),
            "ba": .byteArray([1, -1]), "str": .string("héllo"), "ia": .intArray([1, -2]), "la": .longArray([.max, 0]),
            "emptyList": .list(.compound, []), "list": .list([.int(1), .int(2)]),
            "nested": .compound(["x": .list([.compound(["y": .string("z")])])]),
        ])
        let (name, decoded) = try NBT.read(value.serialized(rootName: "root"))
        #expect(name == "root")
        #expect(decoded == value)
    }

    @Test func modifiedUTF8() throws {
        let tricky = "a\u{0}b ⛏ 🌍"
        let encoded = ModifiedUTF8.encode(tricky)
        #expect(!encoded.contains(0))  // NUL is C0 80
        #expect(encoded.contains(0xED))  // surrogate halves encoded separately
        #expect(try ModifiedUTF8.decode(encoded[...]) == tricky)
    }

    @Test func rejectsTruncatedData() {
        let bytes = NBT.compound(["x": .longArray([1, 2, 3])]).serialized()
        #expect(throws: NBTError.unexpectedEndOfData) { try NBT.read(Array(bytes.dropLast(5))) }
    }

    @Test func skippingLeavesOutNamedEntriesAtAnyDepth() throws {
        let value = NBT.compound([
            "keep": .int(1),
            "drop": .list([.compound(["deep": .longArray([1, 2, 3]), "s": .string("x")])]),
            "nested": .compound(["drop": .byteArray([1, 2]), "kept": .string("yes")]),
            "after": .longArray([.max]),
        ])
        let (_, decoded) = try NBT.read(value.serialized(), skipping: ["drop"])
        #expect(decoded == .compound(["keep": .int(1), "nested": .compound(["kept": .string("yes")]), "after": .longArray([.max])]))
        #expect(try NBT.read(value.serialized(), skipping: []).value == value)
    }

    @Test func skippingStillDetectsTruncation() {
        let bytes = NBT.compound(["drop": .longArray([1, 2, 3, 4]), "keep": .int(1)]).serialized()
        #expect(throws: NBTError.unexpectedEndOfData) { try NBT.read(Array(bytes.prefix(20)), skipping: ["drop"]) }
    }

    @Test func uuidFromIntArray() {
        let uuid = NBT.intArray([0x01234567, -0x7654_3211, 0x0, 0x1]).uuid
        #expect(uuid?.uuidString == "01234567-89AB-CDEF-0000-000000000001")
    }
}

@Suite struct CompressionTests {
    @Test func gzipAndZlibRoundTrip() throws {
        let data = Array(repeating: Array("minecraft:stone".utf8), count: 500).flatMap { $0 }
        #expect(try Compression.inflate(Compression.deflate(data)) == data)
        #expect(try Compression.inflate(Compression.deflate(data, gzip: true)) == data)
    }

    @Test func lz4BlockWithOverlappingMatch() throws {
        // Literal "abc", then a 9-byte match at offset 3 (overlaps its own output).
        let block: [UInt8] = [0x35] + Array("abc".utf8) + [0x03, 0x00]
        #expect(try Compression.decompressLZ4Block(block[...], originalSize: 12) == Array("abcabcabcabc".utf8))
    }

    @Test func lz4LongLiteralRun() throws {
        let text = [UInt8](repeating: 0x41, count: 300)
        // 300 literals = 15 + 255 + 30.
        let block: [UInt8] = [0xF0, 255, 30] + text
        #expect(try Compression.decompressLZ4Block(block[...], originalSize: 300) == text)
    }

    @Test func lz4BlockStreamFraming() throws {
        let compressed: [UInt8] = [0x35] + Array("xyz".utf8) + [0x03, 0x00]
        let stream = Fixtures.lz4Block(method: 0x20, payload: compressed, originalLength: 12)
            + Fixtures.lz4Block(method: 0x10, payload: Array("!!".utf8), originalLength: 2)
            + Fixtures.lz4Block(method: 0x10, payload: [], originalLength: 0)
        #expect(try Compression.decodeLZ4BlockStream(stream) == Array("xyzxyzxyzxyz!!".utf8))
    }

    @Test func lz4RejectsBadOffset() {
        let block: [UInt8] = [0x15, 0x61, 0x09, 0x00]
        #expect(throws: CompressionError.invalidLZ4) { try Compression.decompressLZ4Block(block[...], originalSize: 10) }
    }
}

@Suite struct ChunkTests {
    let air = NBT.string("minecraft:air")

    @Test func stringPalette() throws {
        // 26.3+: a list of strings when every entry is a default state.
        let palette: [NBT] = [.string("minecraft:air"), .string("minecraft:stone")]
        let raw = Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: 0, palette: palette, indices: (0..<4096).map { $0 % 2 })])
        let chunk = try Chunk(nbt: NBT.read(raw.serialized()).value)
        #expect(chunk.block(x: 1, y: 0, z: 0) == BlockState("minecraft:stone"))
    }

    @Test func acceptsEveryCompoundPaletteEntryShape() throws {
        let palette: [NBT] = [
            .compound(["": .string("minecraft:air")]),
            .compound(["": .string("minecraft:stone")]),
            .compound(["id": .string("minecraft:oak_stairs"), "properties": .compound(["facing": .string("east")])]),
            .compound(["Name": .string("minecraft:chest"), "Properties": .compound(["type": .string("left")])]),
        ]
        let indices = (0..<4096).map { $0 % 4 }
        let raw = Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: 0, palette: palette, indices: indices)])
        let chunk = try Chunk(nbt: NBT.read(raw.serialized()).value)
        #expect(chunk.block(x: 0, y: 0, z: 0)?.isAir == true)
        #expect(chunk.block(x: 1, y: 0, z: 0) == BlockState("minecraft:stone"))
        #expect(chunk.block(x: 2, y: 0, z: 0) == BlockState("minecraft:oak_stairs", properties: ["facing": "east"]))
        #expect(chunk.block(x: 3, y: 0, z: 0)?.description == "minecraft:chest[type=left]")
    }

    @Test func packedIndicesDoNotStraddleLongs() throws {
        // 17 entries → 5 bits → 12 per long with 4 padding bits.
        let palette = (0..<17).map { NBT.string("minecraft:block_\($0)") }
        let indices = (0..<4096).map { ($0 * 7) % 17 }
        let section = try ChunkSection(Fixtures.section(y: 2, palette: palette, indices: indices, bits: 5))
        #expect(section.blockStates?.bitsPerEntry == 5)
        #expect(section.blockStates?.allPaletteIndices() == indices)
        for (x, y, z) in [(0, 0, 0), (11, 0, 0), (12, 0, 0), (15, 15, 15), (3, 9, 7)] {
            let i = y * 256 + z * 16 + x
            #expect(section.block(x: x, y: y, z: z)?.id == "minecraft:block_\(indices[i])")
        }
    }

    @Test func minimumBlockBitsIsFour() throws {
        let indices = (0..<4096).map { $0 % 2 }
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air, .string("minecraft:dirt")], indices: indices, bits: 4))
        #expect(section.blockStates?.bitsPerEntry == 4)
        #expect(section.block(x: 1, y: 0, z: 0)?.id == "minecraft:dirt")
    }

    @Test func uniformSectionHasNoData() throws {
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [Fixtures.section(y: -4, palette: [.string("minecraft:bedrock")])]))
        #expect(chunk.block(x: 5, y: -60, z: 9)?.id == "minecraft:bedrock")
        #expect(chunk.block(x: 5, y: 100, z: 9) == nil)
    }

    @Test func cellBiomes() throws {
        // Pre-26.4: 64 entries, one per 4×4×4 cell.
        let biomes = ["minecraft:plains", "minecraft:desert"]
        let cells = (0..<64).map { $0 == 21 ? 1 : 0 }  // cell (x1, y1, z1)
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air], biomes: biomes, biomeIndices: cells, biomeBits: 1))
        #expect(!section.hasPerBlockBiomes)
        #expect(section.biome(x: 4, y: 4, z: 4) == "minecraft:desert")
        #expect(section.biome(x: 7, y: 7, z: 7) == "minecraft:desert")
        #expect(section.biome(x: 8, y: 4, z: 4) == "minecraft:plains")
    }

    @Test func perBlockBiomes() throws {
        // 26.4+: 4096 entries in YZX order, like blocks.
        let biomes = ["minecraft:plains", "minecraft:sulfur_caves", "minecraft:river"]
        let perBlock = (0..<4096).map { $0 % 3 }
        let section = try ChunkSection(Fixtures.section(y: 0, palette: [air], biomes: biomes, biomeIndices: perBlock, biomeBits: 2))
        #expect(section.hasPerBlockBiomes)
        #expect(section.biome(x: 1, y: 0, z: 0) == "minecraft:sulfur_caves")
        #expect(section.biome(x: 2, y: 0, z: 0) == "minecraft:river")
        #expect(section.biome(x: 0, y: 1, z: 0) == biomes[256 % 3])
    }

    @Test func statusFieldEitherCase() throws {
        let old = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, dataVersion: 4671, sections: [],
                                                extra: ["status": .string("x"), "Status": .string("minecraft:features")]))
        #expect(old.status == "x")  // lowercase wins when both are present
        var fields = Fixtures.chunk(x: 0, z: 0, dataVersion: 4671, sections: []).compound!
        fields["status"] = nil
        fields["Status"] = .string("minecraft:features")
        #expect(try Chunk(nbt: .compound(fields)).status == "minecraft:features")
    }

    @Test func rejectsLegacyLevelWrapper() {
        let legacy = NBT.compound(["DataVersion": .int(2586), "Level": .compound([:])])
        #expect(throws: ChunkError.unsupportedLegacyFormat(dataVersion: 2586)) { try Chunk(nbt: legacy) }
    }

    @Test func toleratesVestigialLevelCompound() throws {
        // Upgraded pre-1.18 chunks keep `Level: {Structures: ...}` next to the modern fields.
        let nbt = Fixtures.chunk(x: 3, z: 4, dataVersion: 5023, sections: [], extra: ["Level": .compound(["Structures": .compound([:])])])
        #expect(try Chunk(nbt: nbt).x == 3)
    }

    @Test func heightmap() throws {
        let heights = (0..<256).map { $0 % 384 + 1 }
        let chunk = try Chunk(nbt: Fixtures.chunk(x: 0, z: 0, sections: [],
                                                  extra: ["Heightmaps": .compound(["WORLD_SURFACE": .longArray(Fixtures.pack(heights, bits: 9))])]))
        #expect(chunk.heightmap("WORLD_SURFACE")?.first == 1 - 64)
        #expect(chunk.heightmap("WORLD_SURFACE")?[255] == 256 - 64)
    }
}

@Suite struct RegionTests {
    @Test func readsChunksWithEachCompression() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stone = [Fixtures.section(y: 0, palette: [.string("minecraft:stone")])]
        let chunks = [UInt8(1), 2, 3, 4].enumerated().map { i, c in
            Fixtures.RegionChunk(localX: i, localZ: 31, nbt: Fixtures.chunk(x: -32 + i, z: -1, sections: stone), compression: c)
        }
        let url = dir.appendingPathComponent("r.-1.-1.mca")
        try Fixtures.write(try Fixtures.region(chunks), to: url)

        let region = try RegionFile(contentsOf: url)
        #expect((region.x, region.z) == (-1, -1))
        #expect(region.chunkCoordinates.count == 4)
        #expect(try region.chunkNBT(localX: 10, localZ: 10) == nil)
        #expect(try region.timestamp(localX: 0, localZ: 31) == Date(timeIntervalSince1970: 1_700_000_000))
        for i in 0..<4 {
            let chunk = try Chunk(nbt: #require(try region.chunkNBT(localX: i, localZ: 31)))
            #expect(chunk.x == -32 + i)
            #expect(chunk.block(x: 0, y: 3, z: 0)?.id == "minecraft:stone")
        }
    }

    @Test func readsExternalChunk() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nbt = Fixtures.chunk(x: 33, z: 2, sections: [])
        try Fixtures.write(try Fixtures.region([.init(localX: 1, localZ: 2, nbt: nbt, compression: 0x82)]),
                           to: dir.appendingPathComponent("r.1.0.mca"))
        try Fixtures.write(try Compression.deflate(nbt.serialized()), to: dir.appendingPathComponent("c.33.2.mcc"))
        let region = try RegionFile(contentsOf: dir.appendingPathComponent("r.1.0.mca"))
        #expect(try region.chunkNBT(localX: 1, localZ: 2) == nbt)
    }

    @Test func reportsMissingExternalChunk() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write(try Fixtures.region([.init(localX: 0, localZ: 0, nbt: .compound([:]), compression: 0x82)]),
                           to: dir.appendingPathComponent("r.0.0.mca"))
        let region = try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca"))
        #expect(throws: RegionError.missingExternalChunk("c.0.0.mcc")) { try region.chunkNBT(localX: 0, localZ: 0) }
    }

    @Test func emptyRegionFile() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Fixtures.write([], to: dir.appendingPathComponent("r.0.0.mca"))
        #expect(try RegionFile(contentsOf: dir.appendingPathComponent("r.0.0.mca")).chunkCoordinates.isEmpty)
    }
}

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

    @Test func missingLevelDat() throws {
        let dir = try Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: WorldError.missingLevelDat) { try World(contentsOf: dir) }
    }
}
