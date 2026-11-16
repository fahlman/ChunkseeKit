import Foundation
import ChunkseeKit

/// Builders for synthetic world files. Packing is implemented independently of the library's decoder.
public enum Fixtures {
    /// A mob record as written by Minecraft's Mob serializer. Supply its ID, position and
    /// other facts in fields; explicit fields can override the saved boolean defaults.
    public static func mob(_ fields: [String: NBT]) -> NBT {
        .compound(["CanPickUpLoot": NBT.byte(0), "PersistenceRequired": .byte(0), "LeftHanded": .byte(0)]
            .merging(fields) { $1 })
    }

    public static func pack(_ indices: [Int], bits: Int) -> [Int64] {
        let perLong = 64 / bits
        var longs = [UInt64](repeating: 0, count: (indices.count + perLong - 1) / perLong)
        for (i, v) in indices.enumerated() { longs[i / perLong] |= UInt64(v) << UInt64((i % perLong) * bits) }
        return longs.map { Int64(bitPattern: $0) }
    }

    public static func section(y: Int, palette: [NBT], indices: [Int]? = nil, bits: Int = 4,
                               biomes: [String] = ["minecraft:plains"], biomeIndices: [Int]? = nil, biomeBits: Int = 1) -> NBT {
        var states: [String: NBT] = ["palette": .list(palette)]
        if let indices { states["data"] = .longArray(pack(indices, bits: bits)) }
        var biome: [String: NBT] = ["palette": .list(biomes.map(NBT.string))]
        if let biomeIndices { biome["data"] = .longArray(pack(biomeIndices, bits: biomeBits)) }
        return .compound(["Y": .byte(Int8(y)), "block_states": .compound(states), "biomes": .compound(biome)])
    }

    /// The default matches the synthetic per-block-biome layout; tests of other layouts pass their version.
    public static func chunk(x: Int, z: Int, dataVersion: Int = 5119, sections: [NBT],
                             extra: [String: NBT] = [:]) -> NBT {
        var root: [String: NBT] = [
            "DataVersion": .int(Int32(dataVersion)), "xPos": .int(Int32(x)), "zPos": .int(Int32(z)), "yPos": .int(-4),
            "status": .string("minecraft:full"), "sections": .list(sections), "block_entities": .list(.compound, []),
        ]
        root.merge(extra) { $1 }
        return .compound(root)
    }

    public struct RegionChunk: Sendable {
        public var localX: Int, localZ: Int
        public var nbt: NBT
        public var compression: UInt8
        public var timestamp: UInt32

        /// Chunk coordinates are local to one region (0...31). Compression defaults to zlib.
        public init(localX: Int, localZ: Int, nbt: NBT, compression: UInt8 = 2,
                    timestamp: UInt32 = 1_700_000_000) {
            self.localX = localX
            self.localZ = localZ
            self.nbt = nbt
            self.compression = compression
            self.timestamp = timestamp
        }
    }

    /// Builds a region file; chunks with `compression & 0x80` are written as external `.mcc` stubs.
    public static func region(_ chunks: [RegionChunk]) throws -> [UInt8] {
        var file = [UInt8](repeating: 0, count: 8192)
        func putBE(_ v: UInt32, at i: Int) {
            file[i] = UInt8(v >> 24); file[i + 1] = UInt8((v >> 16) & 0xFF); file[i + 2] = UInt8((v >> 8) & 0xFF); file[i + 3] = UInt8(v & 0xFF)
        }
        for c in chunks {
            let payload: [UInt8] = c.compression & 0x80 != 0 ? [] : try encode(c.nbt.serialized(), compression: c.compression)
            var record = [UInt8]()
            let length = UInt32(payload.count + 1)
            record += [UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
            record.append(c.compression)
            record += payload
            let sectors = (record.count + 4095) / 4096
            let offset = file.count / 4096
            record += [UInt8](repeating: 0, count: sectors * 4096 - record.count)
            let index = 4 * (c.localX + c.localZ * 32)
            putBE(UInt32(offset) << 8 | UInt32(sectors), at: index)
            putBE(c.timestamp, at: 4096 + index)
            file += record
        }
        return file
    }

    public static func encode(_ raw: [UInt8], compression: UInt8) throws -> [UInt8] {
        switch compression & 0x7F {
        case 1: return try Compression.deflate(raw, gzip: true)
        case 2: return try Compression.deflate(raw)
        case 3: return raw
        case 4: return lz4BlockStream(stored: raw)
        default: fatalError("unsupported in fixtures")
        }
    }

    /// An lz4-java block stream using one "stored" block followed by the end marker.
    public static func lz4BlockStream(stored raw: [UInt8]) -> [UInt8] {
        lz4Block(method: 0x10, payload: raw, originalLength: raw.count) + lz4Block(method: 0x10, payload: [], originalLength: 0)
    }

    public static func lz4Block(method: UInt8, payload: [UInt8], originalLength: Int) -> [UInt8] {
        func le(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) } }
        return Array("LZ4Block".utf8) + [method] + le(payload.count) + le(originalLength) + le(0) + payload
    }

    /// A UUID as the four big-endian ints Minecraft stores.
    public static func uuidInts(_ uuid: UUID) -> NBT {
        let b = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        return .intArray((0..<4).map { i in Int32(bitPattern: b[i * 4..<i * 4 + 4].reduce(0) { $0 << 8 | UInt32($1) }) })
    }

    public static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChunkseeKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func write(_ bytes: [UInt8], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    public static func writeGzippedNBT(_ nbt: NBT, to url: URL) throws {
        try write(Compression.deflate(nbt.serialized(), gzip: true), to: url)
    }
}
