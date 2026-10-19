import Foundation
@testable import ChunkseeKit

/// Builders for synthetic world files. Packing is implemented independently of the library's decoder.
enum Fixtures {
    static func pack(_ indices: [Int], bits: Int) -> [Int64] {
        let perLong = 64 / bits
        var longs = [UInt64](repeating: 0, count: (indices.count + perLong - 1) / perLong)
        for (i, v) in indices.enumerated() { longs[i / perLong] |= UInt64(v) << UInt64((i % perLong) * bits) }
        return longs.map { Int64(bitPattern: $0) }
    }

    static func section(y: Int, palette: [NBT], indices: [Int]? = nil, bits: Int = 4,
                        biomes: [String] = ["minecraft:plains"], biomeIndices: [Int]? = nil, biomeBits: Int = 1) -> NBT {
        var states: [String: NBT] = ["palette": .list(palette)]
        if let indices { states["data"] = .longArray(pack(indices, bits: bits)) }
        var biome: [String: NBT] = ["palette": .list(biomes.map(NBT.string))]
        if let biomeIndices { biome["data"] = .longArray(pack(biomeIndices, bits: biomeBits)) }
        return .compound(["Y": .byte(Int8(y)), "block_states": .compound(states), "biomes": .compound(biome)])
    }

    static func chunk(x: Int, z: Int, dataVersion: Int = DataVersion.perBlockBiomes, sections: [NBT],
                      extra: [String: NBT] = [:]) -> NBT {
        var root: [String: NBT] = [
            "DataVersion": .int(Int32(dataVersion)), "xPos": .int(Int32(x)), "zPos": .int(Int32(z)), "yPos": .int(-4),
            "status": .string("minecraft:full"), "sections": .list(sections), "block_entities": .list(.compound, []),
        ]
        root.merge(extra) { $1 }
        return .compound(root)
    }

    struct RegionChunk {
        var localX: Int, localZ: Int
        var nbt: NBT
        var compression: UInt8 = 2
        var timestamp: UInt32 = 1_700_000_000
    }

    /// Builds a region file; chunks with `compression & 0x80` are written as external `.mcc` stubs.
    static func region(_ chunks: [RegionChunk]) throws -> [UInt8] {
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

    static func encode(_ raw: [UInt8], compression: UInt8) throws -> [UInt8] {
        switch compression & 0x7F {
        case 1: return try Compression.deflate(raw, gzip: true)
        case 2: return try Compression.deflate(raw)
        case 3: return raw
        case 4: return lz4BlockStream(stored: raw)
        default: fatalError("unsupported in fixtures")
        }
    }

    /// An lz4-java block stream using one "stored" block followed by the end marker.
    static func lz4BlockStream(stored raw: [UInt8]) -> [UInt8] {
        lz4Block(method: 0x10, payload: raw, originalLength: raw.count) + lz4Block(method: 0x10, payload: [], originalLength: 0)
    }

    static func lz4Block(method: UInt8, payload: [UInt8], originalLength: Int) -> [UInt8] {
        func le(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) } }
        return Array("LZ4Block".utf8) + [method] + le(payload.count) + le(originalLength) + le(0) + payload
    }

    /// A UUID as the four big-endian ints Minecraft stores.
    static func uuidInts(_ uuid: UUID) -> NBT {
        let b = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        return .intArray((0..<4).map { i in Int32(bitPattern: b[i * 4..<i * 4 + 4].reduce(0) { $0 << 8 | UInt32($1) }) })
    }

    static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChunkseeKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ bytes: [UInt8], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: url)
    }

    static func writeGzippedNBT(_ nbt: NBT, to url: URL) throws {
        try write(Compression.deflate(nbt.serialized(), gzip: true), to: url)
    }
}

extension Fixtures {
    static func runCLI(_ world: URL, command: String, arguments: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        // SwiftPM places the tool beside this test bundle, including Release and --scratch-path builds.
        process.executableURL = Bundle(for: CLITestBundle.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("chunksee")
        process.arguments = [world.path, command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}

private final class CLITestBundle: NSObject {}
