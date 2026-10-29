import Foundation

public enum ChunkError: Error, Equatable {
    /// Numeric block storage has not yet been flattened into named palette entries.
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

    /// Minecraft's code flag used by its surface-height predicate, independently of the air tag.
    /// Unknown block code returns nil. Generated facts apply across save and game versions.
    public var isAir: Bool? {
        GeneratedAirBlocks.values[id] ?? Identifier(id).flatMap { GeneratedAirBlocks.values[$0.description] }
    }

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
        // Initialization validated the word count; the decoder emits exactly entryCount
        // values. Fill that storage once without append bookkeeping for every block.
        return Array(unsafeUninitializedCapacity: entryCount) { buffer, initializedCount in
            PackedLongs.forEachValue(in: data, entries: entryCount, bits: bitsPerEntry) { value in
                buffer.initializeElement(at: initializedCount, to: value)
                initializedCount += 1
            }
        }
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
    // An unreadable present tag must never acquire the omitted-layer default.
    let hasBlockLightTag: Bool

    /// True when biomes are stored per block (26.4+) rather than per 4×4×4 cell.
    public var hasPerBlockBiomes: Bool { biomes?.hasPerBlockBiomes == true }

    init(_ nbt: NBT) throws {
        guard let y = nbt["Y"]?.compoundByte else { throw ChunkError.missingField("sections[].Y") }
        self.y = Int(y)

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

        hasBlockLightTag = nbt["BlockLight"] != nil
        // Byte-for-byte reinterpretation; a per-element map over 4 KB per section was measurable.
        blockLight = nbt["BlockLight"]?.byteArray.map { $0.withUnsafeBytes { [UInt8]($0) } }
        skyLight = nbt["SkyLight"]?.byteArray.map { $0.withUnsafeBytes { [UInt8]($0) } }
    }

    /// Index within the section's 4096 blocks, including decoded palette-index arrays.
    /// Blocks are ordered YZX. Coordinates wrap to 0..<16, matching the section's block,
    /// per-block biome and light accessors; the result is always in 0..<4096.
    @inlinable @inline(__always)
    public static func blockIndex(x: Int, y: Int, z: Int) -> Int { (y & 15) << 8 | (z & 15) << 4 | (x & 15) }

    /// Block at section-local coordinates (each 0..<16).
    public func block(x: Int, y: Int, z: Int) -> BlockState? {
        blockStates?[Self.blockIndex(x: x, y: y, z: z)]
    }

    /// Biome at section-local block coordinates (each 0..<16).
    public func biome(x: Int, y: Int, z: Int) -> String? {
        biomes?.biome(x: x, y: y, z: z)
    }

    public func blockLight(x: Int, y: Int, z: Int) -> Int? { Self.nibble(blockLight, Self.blockIndex(x: x, y: y, z: z)) }
    public func skyLight(x: Int, y: Int, z: Int) -> Int? { Self.nibble(skyLight, Self.blockIndex(x: x, y: y, z: z)) }

    private static func nibble(_ array: [UInt8]?, _ i: Int) -> Int? {
        guard let array, array.count == 2048 else { return nil }
        return Int(i & 1 == 0 ? array[i >> 1] & 0x0F : array[i >> 1] >> 4)
    }
}

/// The saved identity and position of a block entity, including unfamiliar kinds.
public struct BlockEntity: Sendable, Equatable {
    /// The saved ID, without guessing a kind when it is missing or unreadable.
    public let id: String?
    /// Absolute block coordinates, or nil when any saved coordinate is unreadable.
    public let position: BlockPosition?

    init(nbt: NBT) {
        id = nbt["id"]?.string
        position = nbt.blockEntityPosition
    }
}

/// A decoded terrain chunk, including older Level-wrapped named palettes.
public struct Chunk: Sendable {
    /// Cache contract for terrain, biomes, heightmaps, saved-light fields and surface traversal. Bump the
    /// revision when these readers or their shared format/upgrade rules change meaning.
    public static let interpretationVersion = InterpretationVersion(
        domain: "terrain", revision: 2, generatedFacts: GeneratedInterpretationDigests.terrain,
        dependencies: [])

    /// Saved metadata, when present; structural decoding does not require a version label.
    public let dataVersion: Int?
    /// Absolute chunk coordinates.
    public let x: Int
    public let z: Int
    /// Lowest section Y (e.g. -4 for a default Overworld).
    public let minSectionY: Int
    /// Generation status, e.g. `minecraft:full`. Read from `status` (26.4+) or `Status`.
    public let status: String?
    public let lastUpdate: Int?
    public let inhabitedTime: Int?
    /// Whether the save marks its light data as valid. Missing or skipped flags are false;
    /// this says nothing about light in an omitted or malformed section array.
    public var isLightOn: Bool { nbt["isLightOn"]?.compoundBoolean ?? false }
    /// Sections sorted by Y.
    public let sections: [ChunkSection]
    /// An immutable view retaining only biome palettes and section heights, without blocks,
    /// light arrays or the chunk's NBT. Reuse it when neighboring terrain needs these biomes.
    public var biomeSnapshot: ChunkBiomeSnapshot { ChunkBiomeSnapshot(sections: sections) }
    /// Saved order is preserved, including entries with unavailable identity or position.
    public let blockEntities: [BlockEntity]
    /// Saved input retained for typed readers within the library.
    let nbt: NBT
    let structureStartsNBT: NBT?
    let embeddedEntityChunk: NBT?

    /// Chunk entries that terrain readers (blocks, biomes, heightmaps) don't use: ticks, light,
    /// structures, entities and generation bookkeeping. Pass to `RegionFile.chunkNBT(localX:localZ:skipping:)`
    /// to decode faster; the resulting `Chunk` has no light data, block entities or proto-chunk data.
    public static let keysNotNeededForTerrain: Set<String> = [
        "block_ticks", "fluid_ticks", "PostProcessing", "structures", "blending_data", "block_entities",
        "BlockLight", "SkyLight", "entities", "CarvingMasks", "Lights", "UpgradeData", "isLightOn",
        "Entities", "TileEntities", "TileTicks", "LiquidTicks", "LiquidsToBeTicked", "ToBeTicked",
    ]

    /// Opt-in terrain read retaining the saved light channels and their validity flag.
    /// Ordinary terrain readers keep using keysNotNeededForTerrain without this extra data.
    public static let keysNotNeededForTerrainAndLight: Set<String> = keysNotNeededForTerrain
        .subtracting(["BlockLight", "SkyLight", "isLightOn"])

    /// Opt-in biome read omitting block palettes and heightmaps as well as terrain's unused
    /// entries. Construct a Chunk from the result and retain its biomeSnapshot. Skipped block
    /// data is not validated; biome palettes, section heights and chunk identity still are.
    public static let keysNotNeededForBiomes: Set<String> = keysNotNeededForTerrain
        .union(["block_states", "Heightmaps"])

    public var isFullyGenerated: Bool { status == "minecraft:full" || status == "full" }

    /// Saved block light at chunk-local X/Z and absolute Y, only when marked valid. Missing
    /// sections/arrays stay unknown; no light propagation or inference from neighboring data.
    public func blockLight(x: Int, y: Int, z: Int) -> Int? {
        guard isLightOn else { return nil }
        return section(atBlockY: y)?.blockLight(x: x, y: y, z: z)
    }

    /// Valid block light, including the generated game default for an omitted layer.
    /// X/Z must be chunk-local (0..<16), and absolute Y must fit the game's Int32.
    /// Stale light and malformed present arrays remain unknown.
    /// Read all light fields, or use keysNotNeededForTerrainAndLight: selectively skipping
    /// BlockLight while retaining isLightOn is indistinguishable from an omitted saved layer.
    /// The raw blockLight accessors keep their stored-array meaning. No propagation is run.
    public func resolvedBlockLight(x: Int, y: Int, z: Int) -> Int? {
        guard isLightOn, (0..<16).contains(x), (0..<16).contains(z), Int32(exactly: y) != nil else { return nil }
        let section = section(atBlockY: y)
        if section?.hasBlockLightTag == true { return section?.blockLight(x: x, y: y, z: z) }
        return GeneratedLightStorage.absentBlockLight
    }

    /// Saved sky light with the same validity and missing-data rules as blockLight(x:y:z:).
    public func skyLight(x: Int, y: Int, z: Int) -> Int? {
        guard isLightOn else { return nil }
        return section(atBlockY: y)?.skyLight(x: x, y: y, z: z)
    }

    public init(nbt: NBT) throws {
        try self.init(input: TerrainChunkInput(nbt))
    }

    init(input: TerrainChunkInput) throws {
        let nbt = input.nbt
        let dataVersion = nbt["DataVersion"]?.int
        // Supported wrapped palettes have already been normalized. Remaining wrapped sections
        // use a different storage format; a vestigial Level.Structures alone is harmless.
        guard nbt["Level"]?["Sections"] == nil else {
            throw ChunkError.unsupportedLegacyFormat(dataVersion: dataVersion)
        }
        guard let x = nbt["xPos"]?.compoundInt, let z = nbt["zPos"]?.compoundInt else {
            throw ChunkError.missingField("xPos/zPos")
        }
        self.dataVersion = dataVersion
        self.x = Int(x)
        self.z = Int(z)
        self.status = (nbt["status"] ?? nbt["Status"])?.string
        self.lastUpdate = (nbt["LastUpdate"]?.compoundLong).map(Int.init)
        self.inhabitedTime = input.inhabitedTime
        self.sections = try (nbt["sections"]?.list ?? []).map(ChunkSection.init).sorted { $0.y < $1.y }
        self.minSectionY = nbt["yPos"]?.int ?? sections.first?.y ?? 0
        self.nbt = nbt
        self.blockEntities = input.blockEntities
        self.structureStartsNBT = input.structureStarts
        self.embeddedEntityChunk = input.embeddedEntityChunk
    }

    public func section(atBlockY y: Int) -> ChunkSection? {
        sectionAtBlockY(y, in: sections, sectionY: { $0.y })
    }

    /// Block at chunk-local x/z (0..<16) and absolute y. Missing sections read as `nil`.
    public func block(x: Int, y: Int, z: Int) -> BlockState? {
        section(atBlockY: y)?.block(x: x & 15, y: y & 15, z: z & 15)
    }

    /// Biome at chunk-local x/z (0..<16) and absolute y.
    public func biome(x: Int, y: Int, z: Int) -> String? {
        section(atBlockY: y)?.biome(x: x & 15, y: y & 15, z: z & 15)
    }

    /// The first block entity at chunk-local x/z and absolute y, if any.
    public func blockEntity(x: Int, y: Int, z: Int) -> BlockEntity? {
        blockEntities.first {
            guard let position = $0.position else { return false }
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
        guard let bits = Self.heightmapBitWidth(for: height), let longs = nbt["Heightmaps"]?[name]?.longArray,
              PackedLongs.wordCount(entries: 256, bits: bits) == longs.count else { return nil }
        return decodedHeightmap(longs, bits: bits, maximum: height)
    }

    static func heightmapBitWidth(for height: Int) -> Int? {
        guard height > 0 else { return nil }
        let bits = Int.bitWidth - height.leadingZeroBitCount
        return bits <= 32 ? bits : nil
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
