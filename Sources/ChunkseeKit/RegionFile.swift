import Foundation

public enum RegionError: Error, Equatable {
    case invalidFileName(String)
    case truncatedHeader
    case chunkOutOfBounds(localX: Int, localZ: Int)
    case invalidChunkLength
    case unknownCompression(UInt8)
    case unsupportedCustomCompression(String)
    case missingExternalChunk(String)
}

/// How a chunk's payload is compressed (the byte after its length prefix).
public enum ChunkCompression: UInt8, Sendable {
    case gzip = 1
    case zlib = 2
    case none = 3
    case lz4 = 4
    /// A third-party algorithm, named by a string at the start of the payload.
    case custom = 127
}

/// An Anvil region file (`r.<x>.<z>.mca`): 32×32 chunks in 4 KiB sectors.
/// The same container is used for the `region`, `entities`, and `poi` folders.
public struct RegionFile: Sendable {
    public static let sectorSize = 4096

    public let url: URL
    /// Region coordinates parsed from the file name.
    public let x: Int
    public let z: Int
    private let bytes: [UInt8]

    public init(contentsOf url: URL) throws {
        guard let (x, z) = Self.parseCoordinates(url.lastPathComponent) else {
            throw RegionError.invalidFileName(url.lastPathComponent)
        }
        self.url = url
        self.x = x
        self.z = z
        self.bytes = [UInt8](try Data(contentsOf: url))
        // A zero-length file is a region with no chunks; anything else needs the full header.
        guard bytes.isEmpty || bytes.count >= 2 * Self.sectorSize else { throw RegionError.truncatedHeader }
    }

    /// Parses `r.<x>.<z>.mca` into region coordinates.
    public static func parseCoordinates(_ name: String) -> (x: Int, z: Int)? {
        let parts = name.split(separator: ".")
        guard parts.count == 4, parts[0] == "r", parts[3] == "mca",
              let x = Int(parts[1]), let z = Int(parts[2]) else { return nil }
        return (x, z)
    }

    private func headerInt(_ offset: Int) -> UInt32 {
        guard !bytes.isEmpty else { return 0 }
        return Self.headerInt(bytes, at: offset)
    }

    private static func headerInt(_ bytes: [UInt8], at offset: Int = 0) -> UInt32 {
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func headerIndex(_ localX: Int, _ localZ: Int) throws -> Int {
        guard (0..<32).contains(localX), (0..<32).contains(localZ) else {
            throw RegionError.chunkOutOfBounds(localX: localX, localZ: localZ)
        }
        return 4 * (localX + localZ * 32)
    }

    /// Whether the chunk at region-local coordinates has been generated.
    public func containsChunk(localX: Int, localZ: Int) -> Bool {
        guard let i = try? Self.headerIndex(localX, localZ) else { return false }
        return headerInt(i) != 0
    }

    /// Region-local coordinates of every chunk present in the file.
    public var chunkCoordinates: [(localX: Int, localZ: Int)] {
        var result = [(localX: Int, localZ: Int)]()
        for z in 0..<32 { for x in 0..<32 where containsChunk(localX: x, localZ: z) { result.append((x, z)) } }
        return result
    }

    /// When the chunk was last saved.
    public func timestamp(localX: Int, localZ: Int) throws -> Date? {
        let seconds = headerInt(Self.sectorSize + (try Self.headerIndex(localX, localZ)))
        return seconds == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Reads the decompressed NBT for a chunk, or `nil` if it hasn't been generated.
    /// Coordinates are region-local (0..<32); use `chunkX & 31` for absolute chunk coordinates.
    public func chunkNBT(localX: Int, localZ: Int) throws -> NBT? {
        try chunkNBT(localX: localX, localZ: localZ, skipping: [])
    }

    /// Like `chunkNBT(localX:localZ:)`, leaving out compound entries named in `skipping` (see
    /// `NBT.read(_:skipping:)` and `Chunk.keysNotNeededForTerrain`).
    public func chunkNBT(localX: Int, localZ: Int, skipping: Set<String>) throws -> NBT? {
        guard let payload = try chunkPayload(localX: localX, localZ: localZ) else { return nil }
        return try NBT.read(payload, skipping: skipping).value
    }

    /// A standalone query needs only its header entry and payload, not a copy of every chunk
    /// in the region. Bulk readers keep the ordinary RegionFile snapshot and reuse its bytes.
    static func chunkNBT(contentsOf url: URL, localX: Int, localZ: Int,
                         skipping: Set<String> = []) throws -> NBT? {
        guard let (x, z) = parseCoordinates(url.lastPathComponent) else {
            throw RegionError.invalidFileName(url.lastPathComponent)
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let size = Int(exactly: try file.seekToEnd()) else { throw RegionError.invalidChunkLength }
        guard size == 0 || size >= 2 * sectorSize else { throw RegionError.truncatedHeader }
        let index = try headerIndex(localX, localZ)
        guard size != 0 else { return nil }
        func read(_ range: Range<Int>) throws -> [UInt8] {
            try file.seek(toOffset: UInt64(range.lowerBound))
            var result: [UInt8] = []
            result.reserveCapacity(range.count)
            while result.count < range.count {
                guard let bytes = try file.read(upToCount: range.count - result.count), !bytes.isEmpty else {
                    throw RegionError.invalidChunkLength
                }
                result.append(contentsOf: bytes)
            }
            return result
        }
        let location = headerInt(try read(index..<(index + 4)))
        guard let payload = try chunkPayload(location: location, size: size, url: url,
            region: RegionPosition(x: x, z: z), localX: localX, localZ: localZ, read: read) else { return nil }
        return try NBT.read(payload, skipping: skipping).value
    }

    /// The decompressed (raw NBT) bytes for a chunk.
    public func chunkPayload(localX: Int, localZ: Int) throws -> [UInt8]? {
        let location = headerInt(try Self.headerIndex(localX, localZ))
        return try Self.chunkPayload(location: location, size: bytes.count, url: url,
            region: RegionPosition(x: x, z: z), localX: localX, localZ: localZ) { Array(bytes[$0]) }
    }

    /// Both access paths share bounds, external-file and compression interpretation.
    private static func chunkPayload(location: UInt32, size: Int, url: URL,
                                     region: RegionPosition, localX: Int, localZ: Int,
                                     read: (Range<Int>) throws -> [UInt8]) throws -> [UInt8]? {
        guard location != 0 else { return nil }
        let start = Int(location >> 8) * sectorSize
        let sectorCount = Int(location & 0xFF)

        guard start + 5 <= size else { throw RegionError.invalidChunkLength }
        let prefix = try read(start..<(start + 5))
        let length = Int(Int32(bitPattern: headerInt(prefix)))
        guard length >= 1, start + 4 + length <= size,
              sectorCount == 0 || 4 + length <= sectorCount * sectorSize else {
            throw RegionError.invalidChunkLength
        }
        let typeByte = prefix[4]

        // A set high bit means the chunk was too large (>1020 KiB) and lives in c.<x>.<z>.mcc.
        let data: [UInt8]
        if typeByte & 0x80 != 0 {
            let name = "c.\(region.x * 32 + localX).\(region.z * 32 + localZ).mcc"
            let external = url.deletingLastPathComponent().appendingPathComponent(name)
            guard let contents = try? Data(contentsOf: external) else { throw RegionError.missingExternalChunk(name) }
            data = [UInt8](contents)
        } else {
            data = try read((start + 5)..<(start + 4 + length))
        }

        guard let compression = ChunkCompression(rawValue: typeByte & 0x7F) else {
            throw RegionError.unknownCompression(typeByte)
        }
        switch compression {
        case .gzip, .zlib: return try Compression.inflate(data)
        case .none: return data
        case .lz4: return try Compression.decodeLZ4BlockStream(data)
        case .custom:
            // Payload starts with the algorithm's name as a u16-length-prefixed string.
            var name = "unknown"
            if data.count >= 2 {
                let n = Int(data[0]) << 8 | Int(data[1])
                if data.count >= 2 + n { name = String(decoding: data[2..<2 + n], as: UTF8.self) }
            }
            throw RegionError.unsupportedCustomCompression(name)
        }
    }
}
