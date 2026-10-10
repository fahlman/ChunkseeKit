import Foundation

/// Data versions at which the chunk format changed in ways this parser cares about.
public enum DataVersion {
    /// 1.18 (21w43a): root-level `sections`, `block_states`/`biomes` paletted containers.
    public static let flatChunkRoot = 2844
    /// 26.3 Snapshot 7: block palette `Name`/`Properties` became `id`/`properties`, compact entries allowed.
    public static let lowercaseBlockPalette = 5009
    /// 26.4 Snapshot 1: biomes stored per block (4096 per section) instead of per 4×4×4 cell; `Status` → `status`.
    public static let perBlockBiomes = 5119
}

public enum ChunkError: Error, Equatable {
    /// Pre-1.18 chunks (with a `Level` wrapper) aren't supported.
    case unsupportedLegacyFormat(dataVersion: Int?)
    case missingField(String)
    case invalidPalette(String)
    case invalidPackedData(entries: Int, paletteSize: Int, longs: Int)
}

/// A block state: a namespaced ID plus property values.
///
/// Since 26.3, properties are omitted when a block is in its default state, so an empty
/// `properties` means "default state" (or a block with no properties), not "unknown".
public struct BlockState: Hashable, Sendable, CustomStringConvertible {
    public var id: String
    public var properties: [String: String]

    public init(_ id: String, properties: [String: String] = [:]) {
        self.id = id
        self.properties = properties
    }

    public var description: String {
        guard !properties.isEmpty else { return id }
        return id + "[" + properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") + "]"
    }

    public var isAir: Bool { id == "minecraft:air" || id == "minecraft:cave_air" || id == "minecraft:void_air" }

    /// Accepts every palette entry shape seen across versions:
    /// - `"minecraft:stone"` (26.3+, list-of-strings palette)
    /// - `{"": "minecraft:stone"}` (26.3+, compact entry in a compound palette)
    /// - `{id: ..., properties: {...}}` (26.3+)
    /// - `{Name: ..., Properties: {...}}` (1.18 – 26.2)
    init(paletteEntry entry: NBT) throws {
        if let s = entry.string {
            self.init(s)
            return
        }
        guard let c = entry.compound else { throw ChunkError.invalidPalette("block entry is \(entry.tagType)") }
        guard let id = (c["id"] ?? c["Name"] ?? c[""])?.string else {
            throw ChunkError.invalidPalette("block entry without id: \(c.keys.sorted())")
        }
        var props = [String: String]()
        for (k, v) in (c["properties"] ?? c["Properties"])?.compound ?? [:] {
            props[k] = v.string ?? v.int.map(String.init) ?? "\(v)"
        }
        self.init(id, properties: props)
    }
}

/// A palette plus packed indices, as used for `block_states` and `biomes`.
///
/// Indices are packed into 64-bit longs, lowest bits first, and never straddle two longs (1.16+).
public struct PalettedContainer<Element: Sendable>: Sendable {
    public let palette: [Element]
    public let entryCount: Int
    public let bitsPerEntry: Int
    private let data: [Int64]

    /// A container whose palette has a single entry (no `data` is stored).
    public var isUniform: Bool { bitsPerEntry == 0 }

    init(palette: [Element], data: [Int64]?, entryCount: Int, minimumBits: Int) throws {
        guard !palette.isEmpty else { throw ChunkError.invalidPalette("empty palette") }
        self.palette = palette
        self.entryCount = entryCount
        guard let data, !data.isEmpty else {
            guard palette.count == 1 else {
                throw ChunkError.invalidPackedData(entries: entryCount, paletteSize: palette.count, longs: 0)
            }
            self.bitsPerEntry = 0
            self.data = []
            return
        }
        // Use the width implied by the palette; fall back to the width implied by the data length
        // so files written by tools that don't follow vanilla's rounding still load.
        let expected = max(minimumBits, Self.bitsNeeded(palette.count))
        if Self.longsNeeded(entries: entryCount, bits: expected) == data.count {
            self.bitsPerEntry = expected
        } else if let inferred = (1...32).first(where: { Self.longsNeeded(entries: entryCount, bits: $0) == data.count }),
                  inferred >= Self.bitsNeeded(palette.count) {
            self.bitsPerEntry = inferred
        } else {
            throw ChunkError.invalidPackedData(entries: entryCount, paletteSize: palette.count, longs: data.count)
        }
        self.data = data
    }

    static func bitsNeeded(_ paletteSize: Int) -> Int {
        paletteSize <= 1 ? 0 : Int.bitWidth - (paletteSize - 1).leadingZeroBitCount
    }

    static func longsNeeded(entries: Int, bits: Int) -> Int {
        let perLong = 64 / bits
        return (entries + perLong - 1) / perLong
    }

    /// The palette index stored at `index`.
    public func paletteIndex(at index: Int) -> Int {
        guard bitsPerEntry > 0 else { return 0 }
        let perLong = 64 / bitsPerEntry
        let word = UInt64(bitPattern: data[index / perLong])
        let shift = (index % perLong) * bitsPerEntry
        return Int((word >> UInt64(shift)) & ((1 << UInt64(bitsPerEntry)) - 1))
    }

    /// The element at `index`. Out-of-range palette references return `nil`.
    public subscript(index: Int) -> Element? {
        let i = paletteIndex(at: index)
        return i < palette.count ? palette[i] : nil
    }

    /// All palette indices, decoded in one pass.
    public func allPaletteIndices() -> [Int] {
        guard bitsPerEntry > 0 else { return Array(repeating: 0, count: entryCount) }
        var out = [Int]()
        out.reserveCapacity(entryCount)
        let perLong = 64 / bitsPerEntry
        let mask = (UInt64(1) << UInt64(bitsPerEntry)) - 1
        for word in data {
            var w = UInt64(bitPattern: word)
            for _ in 0..<perLong where out.count < entryCount {
                out.append(Int(w & mask))
                w >>= UInt64(bitsPerEntry)
            }
        }
        return out
    }
}

/// A 16×16×16 slice of a chunk.
public struct ChunkSection: Sendable {
    /// Section Y index (block Y = `y * 16 ..< y * 16 + 16`).
    public let y: Int
    /// `nil` for sections that only carry light data.
    public let blockStates: PalettedContainer<BlockState>?
    public let biomes: PalettedContainer<String>?
    /// 2048-byte nibble arrays, or `nil` when omitted.
    public let blockLight: [UInt8]?
    public let skyLight: [UInt8]?

    /// True when biomes are stored per block (26.4+) rather than per 4×4×4 cell.
    public var hasPerBlockBiomes: Bool { biomes?.entryCount == 4096 }

    init(_ nbt: NBT) throws {
        guard let y = nbt["Y"]?.int else { throw ChunkError.missingField("sections[].Y") }
        self.y = y

        if let states = nbt["block_states"], let palette = states["palette"]?.list {
            blockStates = try PalettedContainer(palette: palette.map(BlockState.init(paletteEntry:)),
                                                data: states["data"]?.longArray, entryCount: 4096, minimumBits: 4)
        } else {
            blockStates = nil
        }

        if let biomeNBT = nbt["biomes"], let palette = biomeNBT["palette"]?.list {
            let names = try palette.map { entry -> String in
                guard let name = entry.string ?? (entry["id"] ?? entry["Name"])?.string else {
                    throw ChunkError.invalidPalette("biome entry is \(entry.tagType)")
                }
                return name
            }
            let data = biomeNBT["data"]?.longArray
            // 64 cell entries pack into at most 32 longs (at 32 bits each); 4096 per-block entries
            // need at least 64, so the layout is unambiguous from the data length alone.
            let perBlock = (data?.count ?? 0) >= 64
            biomes = try PalettedContainer(palette: names, data: data, entryCount: perBlock ? 4096 : 64, minimumBits: 1)
        } else {
            biomes = nil
        }

        blockLight = nbt["BlockLight"]?.byteArray.map { $0.map { UInt8(bitPattern: $0) } }
        skyLight = nbt["SkyLight"]?.byteArray.map { $0.map { UInt8(bitPattern: $0) } }
    }

    /// Index within the section's 4096 blocks; blocks are ordered YZX.
    @inline(__always) static func blockIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { (y & 15) << 8 | (z & 15) << 4 | (x & 15) }

    /// Block at section-local coordinates (each 0..<16).
    public func block(x: Int, y: Int, z: Int) -> BlockState? {
        blockStates?[Self.blockIndex(x, y, z)]
    }

    /// Biome at section-local block coordinates (each 0..<16).
    public func biome(x: Int, y: Int, z: Int) -> String? {
        guard let biomes else { return nil }
        if biomes.entryCount == 4096 { return biomes[Self.blockIndex(x, y, z)] }
        return biomes[((y & 15) >> 2) << 4 | ((z & 15) >> 2) << 2 | ((x & 15) >> 2)]
    }

    public func blockLight(x: Int, y: Int, z: Int) -> Int? { Self.nibble(blockLight, Self.blockIndex(x, y, z)) }
    public func skyLight(x: Int, y: Int, z: Int) -> Int? { Self.nibble(skyLight, Self.blockIndex(x, y, z)) }

    private static func nibble(_ array: [UInt8]?, _ i: Int) -> Int? {
        guard let array, array.count == 2048 else { return nil }
        return Int(i & 1 == 0 ? array[i >> 1] & 0x0F : array[i >> 1] >> 4)
    }
}

/// A decoded terrain chunk (1.18+ format, including the 26.x changes).
public struct Chunk: Sendable {
    public let dataVersion: Int
    /// Absolute chunk coordinates.
    public let x: Int
    public let z: Int
    /// Lowest section Y (e.g. -4 for a default Overworld).
    public let minSectionY: Int
    /// Generation status, e.g. `minecraft:full`. Read from `status` (26.4+) or `Status`.
    public let status: String?
    public let lastUpdate: Int?
    public let inhabitedTime: Int?
    /// Sections sorted by Y.
    public let sections: [ChunkSection]
    public let blockEntities: [NBT]
    /// The undecoded NBT, for fields this type doesn't model.
    public let nbt: NBT

    public var isFullyGenerated: Bool { status == "minecraft:full" || status == "full" }

    public init(nbt: NBT) throws {
        let dataVersion = nbt["DataVersion"]?.int
        // Chunks upgraded from pre-1.18 worlds can keep a vestigial `Level: {Structures}` compound,
        // so detect the old format by version and by where `Sections` lives, not by `Level` existing.
        guard let dataVersion, dataVersion >= DataVersion.flatChunkRoot, nbt["Level"]?["Sections"] == nil else {
            throw ChunkError.unsupportedLegacyFormat(dataVersion: dataVersion)
        }
        guard let x = nbt["xPos"]?.int, let z = nbt["zPos"]?.int else { throw ChunkError.missingField("xPos/zPos") }
        self.dataVersion = dataVersion
        self.x = x
        self.z = z
        self.status = (nbt["status"] ?? nbt["Status"])?.string
        self.lastUpdate = nbt["LastUpdate"]?.int
        self.inhabitedTime = nbt["InhabitedTime"]?.int
        self.sections = try (nbt["sections"]?.list ?? []).map(ChunkSection.init).sorted { $0.y < $1.y }
        self.minSectionY = nbt["yPos"]?.int ?? sections.first?.y ?? 0
        self.blockEntities = nbt["block_entities"]?.list ?? []
        self.nbt = nbt
    }

    public func section(atBlockY y: Int) -> ChunkSection? {
        let sy = y >> 4
        // Sections are normally contiguous from minSectionY, so try direct indexing first.
        let guess = sy - (sections.first?.y ?? 0)
        if sections.indices.contains(guess), sections[guess].y == sy { return sections[guess] }
        return sections.first { $0.y == sy }
    }

    /// Block at chunk-local x/z (0..<16) and absolute y. Missing sections read as `nil`.
    public func block(x: Int, y: Int, z: Int) -> BlockState? {
        section(atBlockY: y)?.block(x: x & 15, y: y & 15, z: z & 15)
    }

    /// Biome at chunk-local x/z (0..<16) and absolute y.
    public func biome(x: Int, y: Int, z: Int) -> String? {
        section(atBlockY: y)?.biome(x: x & 15, y: y & 15, z: z & 15)
    }

    /// The block entity at chunk-local x/z and absolute y, if any.
    public func blockEntity(x: Int, y: Int, z: Int) -> NBT? {
        blockEntities.first {
            $0["x"]?.int.map { $0 & 15 } == x & 15 && $0["y"]?.int == y && $0["z"]?.int.map { $0 & 15 } == z & 15
        }
    }

    /// Heightmap names present (e.g. `MOTION_BLOCKING`, `WORLD_SURFACE`).
    public var heightmapNames: [String] { nbt["Heightmaps"]?.compound.map { $0.keys.sorted() } ?? [] }

    /// Decodes a heightmap into 256 absolute Y values (index = `z * 16 + x`).
    /// Each entry is the Y of the first free block above the highest matching block.
    public func heightmap(_ name: String) -> [Int]? {
        guard let longs = nbt["Heightmaps"]?[name]?.longArray, !longs.isEmpty else { return nil }
        // Width is ceil(log2(worldHeight + 1)) — 9 bits for 384 — recoverable from the array length.
        guard let bits = (1...32).first(where: { PalettedContainer<Int>.longsNeeded(entries: 256, bits: $0) == longs.count }) else {
            return nil
        }
        let perLong = 64 / bits
        let mask = (UInt64(1) << UInt64(bits)) - 1
        let baseY = minSectionY * 16
        return (0..<256).map { i in
            Int((UInt64(bitPattern: longs[i / perLong]) >> UInt64((i % perLong) * bits)) & mask) + baseY
        }
    }
}
