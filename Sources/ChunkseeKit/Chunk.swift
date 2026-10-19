import Foundation

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
        PackedLongs.wordCount(entries: entries, bits: bits)
    }

    /// The palette index stored at `index`.
    public func paletteIndex(at index: Int) -> Int {
        guard bitsPerEntry > 0 else { return 0 }
        return PackedLongs.value(at: index, in: data, bits: bitsPerEntry)
    }

    /// The element at `index`. Out-of-range palette references return `nil`.
    public subscript(index: Int) -> Element? {
        let i = paletteIndex(at: index)
        return i < palette.count ? palette[i] : nil
    }

    /// How many entries use each palette index, counted in one pass over the packed data:
    /// `counts[i]` is the number of entries whose palette index is `i`. Much faster than reading
    /// every entry when only totals are needed, such as counting ores. Indices past the palette
    /// (malformed data) aren't counted.
    public func paletteCounts() -> [Int] {
        var counts = [Int](repeating: 0, count: palette.count)
        guard bitsPerEntry > 0 else {
            counts[0] = entryCount
            return counts
        }
        counts.withUnsafeMutableBufferPointer { counts in
            PackedLongs.forEachValue(in: data, entries: entryCount, bits: bitsPerEntry) { i in
                if i < counts.count { counts[i] += 1 }
            }
        }
        return counts
    }

    /// All palette indices, decoded in one pass.
    public func allPaletteIndices() -> [Int] {
        guard bitsPerEntry > 0 else { return Array(repeating: 0, count: entryCount) }
        var out = [Int]()
        out.reserveCapacity(entryCount)
        PackedLongs.forEachValue(in: data, entries: entryCount, bits: bitsPerEntry) { out.append($0) }
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

        // Byte-for-byte reinterpretation; a per-element map over 4 KB per section was measurable.
        blockLight = nbt["BlockLight"]?.byteArray.map { $0.withUnsafeBytes { [UInt8]($0) } }
        skyLight = nbt["SkyLight"]?.byteArray.map { $0.withUnsafeBytes { [UInt8]($0) } }
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

    /// Chunk entries that terrain readers (blocks, biomes, heightmaps) don't use: ticks, light,
    /// structures, entities and generation bookkeeping. Pass to `RegionFile.chunkNBT(localX:localZ:skipping:)`
    /// to decode faster; the resulting `Chunk` has no light data, block entities or proto-chunk data.
    public static let keysNotNeededForTerrain: Set<String> = [
        "block_ticks", "fluid_ticks", "PostProcessing", "structures", "blending_data", "block_entities",
        "BlockLight", "SkyLight", "entities", "CarvingMasks", "Lights", "UpgradeData", "isLightOn",
    ]

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
        self.inhabitedTime = Self.inhabitedTime(in: nbt)
        self.sections = try (nbt["sections"]?.list ?? []).map(ChunkSection.init).sorted { $0.y < $1.y }
        self.minSectionY = nbt["yPos"]?.int ?? sections.first?.y ?? 0
        self.blockEntities = Self.blockEntities(in: nbt)
        self.nbt = nbt
    }

    public func section(atBlockY y: Int) -> ChunkSection? {
        let sy = y >> 4
        // Sections are normally contiguous from minSectionY, so try direct indexing first.
        let guess = sy.subtractingReportingOverflow(sections.first?.y ?? 0)
        if !guess.overflow, sections.indices.contains(guess.partialValue), sections[guess.partialValue].y == sy {
            return sections[guess.partialValue]
        }
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

    /// Modern chunk block entities. This does not opt legacy terrain into modern decoding.
    static func blockEntities(in nbt: NBT) -> [NBT] { nbt["block_entities"]?.list ?? [] }

    /// The block entity at chunk-local x/z and absolute y, if any.
    public func blockEntity(x: Int, y: Int, z: Int) -> NBT? {
        blockEntities.first {
            guard let position = $0.blockEntityPosition else { return false }
            return position.x & 15 == x & 15 && position.y == y && position.z & 15 == z & 15
        }
    }

    /// Heightmap names present (e.g. `MOTION_BLOCKING`, `WORLD_SURFACE`).
    public var heightmapNames: [String] { nbt["Heightmaps"]?.compound.map { $0.keys.sorted() } ?? [] }

    /// Decodes a heightmap into 256 absolute Y values (index = `z * 16 + x`).
    /// Each entry is the Y of the first free block above the highest matching block.
    /// Returns nil when the packed length permits several widths; use the height overload when
    /// the dimension's build height is known. Vanilla 128/256/384-block heights are unambiguous.
    public func heightmap(_ name: String) -> [Int]? {
        guard let longs = nbt["Heightmaps"]?[name]?.longArray, !longs.isEmpty else { return nil }
        let widths = (1...32).filter { PackedLongs.wordCount(entries: 256, bits: $0) == longs.count }
        guard widths.count == 1, let bits = widths.first else { return nil }
        return decodedHeightmap(longs, bits: bits, maximum: nil)
    }

    /// Decodes using the dimension's actual build height (number of blocks, not its maximum Y).
    /// Minecraft stores ceil(log2(height + 1)) bits per entry. Inconsistent data is unavailable.
    public func heightmap(_ name: String, height: Int) -> [Int]? {
        guard height > 0 else { return nil }
        let bits = Int.bitWidth - height.leadingZeroBitCount
        guard bits <= 32, let longs = nbt["Heightmaps"]?[name]?.longArray,
              PackedLongs.wordCount(entries: 256, bits: bits) == longs.count else { return nil }
        return decodedHeightmap(longs, bits: bits, maximum: height)
    }

    private func decodedHeightmap(_ longs: [Int64], bits: Int, maximum: Int?) -> [Int]? {
        let (baseY, overflow) = minSectionY.multipliedReportingOverflow(by: 16)
        guard !overflow else { return nil }
        var result: [Int] = []
        result.reserveCapacity(256)
        var valid = true
        PackedLongs.forEachValue(in: longs, entries: 256, bits: bits) { value in
            if let maximum, value > maximum { valid = false }
            let (y, overflow) = baseY.addingReportingOverflow(value)
            if overflow { valid = false }
            else { result.append(y) }
        }
        return valid ? result : nil
    }
}
