/// Saved biome access after the rest of a decoded chunk is released. Coordinates have the
/// same meaning as Chunk.biome: local block X/Z and absolute Y, with missing sections unknown.
/// This view preserves the decoded palette layout; it does not select neighboring biome cells.
public struct ChunkBiomeSnapshot: Sendable {
    private struct Section: Sendable {
        let y: Int
        let biomes: PalettedContainer<String>?
    }
    private let sections: [Section]

    init(sections: [ChunkSection]) {
        // Keep section order and empty entries so even sparse/duplicate-height lookup agrees
        // with the source chunk. The values retain no block, light or raw NBT storage.
        self.sections = sections.map { Section(y: $0.y, biomes: $0.biomes) }
    }

    public func biome(x: Int, y: Int, z: Int) -> String? {
        sectionAtBlockY(y, in: sections, sectionY: { $0.y })?.biomes?.biome(x: x, y: y, z: z)
    }

    /// Matches ChunkSection.hasPerBlockBiomes for a present palette. An absent section or
    /// palette is unavailable, rather than evidence of either layout. Uniform palettes retain
    /// the existing reader's cell layout because no packed data distinguishes their resolution.
    public func hasPerBlockBiomes(atBlockY y: Int) -> Bool? {
        guard let biomes = sectionAtBlockY(y, in: sections, sectionY: { $0.y })?.biomes else { return nil }
        return biomes.hasPerBlockBiomes
    }
}

extension PalettedContainer where Element == String {
    var hasPerBlockBiomes: Bool { entryCount == 4096 }

    /// The one cell/per-block addressing rule shared by full chunks and biome-only snapshots.
    func biome(x: Int, y: Int, z: Int) -> String? {
        if hasPerBlockBiomes { return self[ChunkSection.blockIndex(x: x, y: y, z: z)] }
        return self[((y & 15) >> 2) << 4 | ((z & 15) >> 2) << 2 | ((x & 15) >> 2)]
    }
}

/// Preserve the full chunk's contiguous fast path and sparse/duplicate fallback in both views.
@inline(__always)
func sectionAtBlockY<Section>(_ y: Int, in sections: [Section], sectionY: (Section) -> Int) -> Section? {
    let sy = y >> 4
    let guess = sy.subtractingReportingOverflow(sections.first.map(sectionY) ?? 0)
    if !guess.overflow, sections.indices.contains(guess.partialValue), sectionY(sections[guess.partialValue]) == sy {
        return sections[guess.partialValue]
    }
    return sections.first { sectionY($0) == sy }
}
