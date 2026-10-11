/// An axis-aligned box of blocks, inclusive on both ends.
public struct BlockBox: Sendable, Equatable {
    public var minX: Int, minY: Int, minZ: Int
    public var maxX: Int, maxY: Int, maxZ: Int

    public init(minX: Int, minY: Int, minZ: Int, maxX: Int, maxY: Int, maxZ: Int) {
        self.minX = minX; self.minY = minY; self.minZ = minZ
        self.maxX = maxX; self.maxY = maxY; self.maxZ = maxZ
    }

    /// Reads the `[I; minX, minY, minZ, maxX, maxY, maxZ]` form used by structure pieces.
    init?(_ nbt: NBT?) {
        guard let v = nbt?.intArray, v.count == 6 else { return nil }
        self.init(minX: Int(v[0]), minY: Int(v[1]), minZ: Int(v[2]), maxX: Int(v[3]), maxY: Int(v[4]), maxZ: Int(v[5]))
    }

    public func union(_ other: BlockBox) -> BlockBox {
        BlockBox(minX: min(minX, other.minX), minY: min(minY, other.minY), minZ: min(minZ, other.minZ),
                 maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY), maxZ: max(maxZ, other.maxZ))
    }
}

/// A structure that begins in a chunk (`structures.starts`): a village, stronghold, fortress and so on.
///
/// Starts can be recorded before their blocks are placed, including leftovers in upgraded worlds.
public struct StructureStart: Sendable, Equatable {
    /// One building block of a structure, such as a stronghold's portal room (`minecraft:shpr`).
    public struct Piece: Sendable, Equatable {
        public var id: String
        public var box: BlockBox
    }

    /// Structure id, e.g. `minecraft:village_plains`.
    public var id: String
    /// The chunk the structure starts in.
    public var chunkX: Int
    public var chunkZ: Int
    public var pieces: [Piece]

    /// The box around every piece, or `nil` for a structure with no pieces.
    public var bounds: BlockBox? {
        pieces.dropFirst().reduce(pieces.first?.box) { $0?.union($1.box) }
    }

    /// The starts in a chunk's NBT. Invalid, empty and explicitly unplaced starts are left out.
    /// Other pieces don't have a universal placement flag, so missing evidence is not a reason to
    /// discard a structure. Callers showing explored terrain should also check the chunk's status.
    public static func starts(inChunk nbt: NBT) -> [StructureStart] {
        guard let starts = nbt["structures"]?["starts"]?.compound else { return [] }
        return starts.compactMap { key, start in
            let id = start["id"]?.string ?? key
            guard id != "INVALID", let chunkX = start["ChunkX"]?.int, let chunkZ = start["ChunkZ"]?.int else { return nil }
            let children = start["Children"]?.list ?? []
            let pieces = children.compactMap { child -> Piece? in
                guard let box = BlockBox(child["BB"]) else { return nil }
                return Piece(id: child["id"]?.string ?? "", box: box)
            }
            guard !pieces.isEmpty, !children.allSatisfy(isUnplacedScatteredFeature) else { return nil }
            return StructureStart(id: id, chunkX: chunkX, chunkZ: chunkZ, pieces: pieces)
        }.sorted { $0.id < $1.id }
    }

    /// Minecraft's ScatteredFeaturePiece starts at HPos = -1 and sets it when postProcess aligns
    /// the building with the ground, before placing blocks. Verified against the 26.3 game code
    /// and an upgraded chunk with an unplaced jungle pyramid. Scope the field to its known piece
    /// types: a data pack's unrelated HPos field does not establish placement.
    private static func isUnplacedScatteredFeature(_ piece: NBT) -> Bool {
        switch piece["id"]?.string {
        case "minecraft:tejp", "minecraft:tedp", "minecraft:tesh":
            return piece["HPos"]?.int == -1
        default:
            return false
        }
    }
}

extension Chunk {
    /// Structures that begin in this chunk.
    public var structureStarts: [StructureStart] { StructureStart.starts(inChunk: nbt) }

    /// Entries a structure scan doesn't need: the block data, and everything in
    /// `keysNotNeededForTerrain` except `structures` itself. Pass to
    /// `RegionFile.chunkNBT(localX:localZ:skipping:)` to read structures quickly; the resulting
    /// `Chunk` has no sections.
    public static let keysNotNeededForStructures: Set<String> =
        keysNotNeededForTerrain.subtracting(["structures"]).union(["sections", "Heightmaps"])
}
