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
/// Only chunks that have been generated record their structures, so this covers explored terrain.
public struct StructureStart: Sendable, Equatable {
    /// One building block of a structure, such as a stronghold's portal room (`minecraft:shportalroom`).
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

    /// The starts in a chunk's NBT. Placeholder starts (`INVALID`) are left out.
    public static func starts(inChunk nbt: NBT) -> [StructureStart] {
        guard let starts = nbt["structures"]?["starts"]?.compound else { return [] }
        return starts.compactMap { key, start in
            let id = start["id"]?.string ?? key
            guard id != "INVALID", let chunkX = start["ChunkX"]?.int, let chunkZ = start["ChunkZ"]?.int else { return nil }
            let pieces = (start["Children"]?.list ?? []).compactMap { child -> Piece? in
                guard let box = BlockBox(child["BB"]) else { return nil }
                return Piece(id: child["id"]?.string ?? "", box: box)
            }
            return StructureStart(id: id, chunkX: chunkX, chunkZ: chunkZ, pieces: pieces)
        }.sorted { $0.id < $1.id }
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
