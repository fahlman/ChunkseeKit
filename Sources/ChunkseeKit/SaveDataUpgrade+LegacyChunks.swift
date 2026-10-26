extension SaveDataUpgrade {
    struct ChunkStatusRename: Sendable {
        let version: Int
        let aliases: [String: String]
        let fallback: String?
    }

    /// Interpret the saved section range. Minecraft's loader-supplied generation context is
    /// not part of a chunk file; this reader does not schedule new terrain below old worlds.
    static func legacyChunkLayout(_ nbt: NBT) -> NBT {
        guard nbt["sections"] == nil, var root = nbt.compound,
              let level = root["Level"]?.compound, let savedSections = level["Sections"]?.list else { return nbt }
        // Numeric block storage needs its own flattening adapter. Never turn those bytes into air.
        guard !savedSections.contains(where: { $0["Blocks"] != nil }) else { return nbt }
        let version = nbt["DataVersion"]?.int ?? -1
        root.removeValue(forKey: "Level")
        for (key, value) in level { root[key] = value }
        for (old, new) in [("Sections", "sections"), ("TileEntities", "block_entities"),
                           ("Entities", "entities"), ("TileTicks", "block_ticks"), ("Structures", "structures")] {
            if let value = root.removeValue(forKey: old) { root[new] = value }
        }
        if var structures = root["structures"]?.compound,
           let starts = structures.removeValue(forKey: "Starts") {
            structures["starts"] = starts
            root["structures"] = .compound(structures)
        }
        if var status = root["Status"]?.string {
            for step in GeneratedLegacyChunkFacts.statusSteps where version < step.version {
                status = step.aliases[status] ?? step.fallback ?? status
            }
            root["Status"] = .string(status)
        }
        if var heights = root["Heightmaps"]?.compound {
            if version < GeneratedLegacyChunkFacts.heightmapNameBoundary {
                for (old, names) in GeneratedLegacyChunkFacts.heightmapNames {
                    if let value = heights.removeValue(forKey: old) {
                        for name in names { heights[name] = value }
                    }
                }
            }
            for (name, value) in heights {
                if let words = value.longArray {
                    heights[name] = .longArray(align(words, entries: 256, bits: GeneratedLegacyChunkFacts.heightmapBits))
                }
            }
            root["Heightmaps"] = .compound(heights)
        }
        let needsSectionLayout = version < GeneratedLegacyChunkFacts.sectionBoundary
            || level["Biomes"] != nil || savedSections.contains { $0["Palette"] != nil || $0["BlockStates"] != nil }
        if needsSectionLayout {
            let oldBiomes = numericBiomes(level["Biomes"])
            let extended = oldBiomes?.count == GeneratedLegacyChunkFacts.newSectionCount * GeneratedLegacyChunkFacts.biomeContainerSize
            let minimum = extended ? GeneratedLegacyChunkFacts.newMinSectionY : 0
            let sectionCount = extended ? GeneratedLegacyChunkFacts.newSectionCount : GeneratedLegacyChunkFacts.oldSectionCount
            var sections = savedSections.map { legacySection($0, biomes: oldBiomes, minimum: minimum, count: sectionCount) }
            let present = Set(sections.compactMap { $0["Y"]?.int })
            for y in minimum..<(minimum + sectionCount) where !present.contains(y) {
                sections.append(legacySection(.compound(["Y": .int(Int32(y))]),
                    biomes: oldBiomes, minimum: minimum, count: sectionCount))
            }
            root["sections"] = .list(sections)
            root["yPos"] = .int(Int32(minimum))
            root.removeValue(forKey: "Biomes")
        }
        if version < GeneratedLegacyChunkFacts.lightResetBoundary {
            // ChunkDeleteLightFix discards light computed under the older lighting rules.
            root.removeValue(forKey: "isLightOn")
            if let sections = root["sections"]?.list {
                root["sections"] = .list(sections.map { section in
                    guard var fields = section.compound else { return section }
                    fields.removeValue(forKey: "BlockLight")
                    fields.removeValue(forKey: "SkyLight")
                    return .compound(fields)
                })
            }
        }
        return .compound(root)
    }

    private static func legacySection(_ section: NBT, biomes: [Int]?, minimum: Int, count: Int) -> NBT {
        guard var fields = section.compound else { return section }
        if fields["block_states"] == nil {
            if let palette = fields["Palette"]?.list, let data = fields["BlockStates"] {
                var blocks: [String: NBT] = ["palette": .list(palette)]
                if palette.count != 1 {
                    let bits = max(4, Int.bitWidth - max(0, palette.count - 1).leadingZeroBitCount)
                    blocks["data"] = data.longArray.map { .longArray(align($0, entries: 4096, bits: bits)) } ?? data
                }
                fields["block_states"] = .compound(blocks)
            } else {
                fields["block_states"] = .compound(["palette": .list([
                    .compound(["Name": .string(GeneratedLegacyChunkFacts.emptyBlock)]),
                ])])
            }
        }
        fields.removeValue(forKey: "Palette")
        fields.removeValue(forKey: "BlockStates")
        if fields["biomes"] == nil, let y = fields["Y"]?.int, (minimum..<(minimum + count)).contains(y) {
            fields["biomes"] = legacyBiomeContainer(biomes, offset: (y - minimum) * GeneratedLegacyChunkFacts.biomeContainerSize)
        }
        return .compound(fields)
    }

    private static func numericBiomes(_ value: NBT?) -> [Int]? {
        guard let values = value?.intArray?.map(Int.init) else { return nil }
        if values.count == 256 {
            // ChunkBiomeFix samples the center of each four-by-four horizontal cell, then
            // repeats that layer through the original build height.
            var layer: [Int] = []
            for z in 0..<4 {
                for x in 0..<4 { layer.append(values[(4 * z + 2) * 16 + 4 * x + 2]) }
            }
            return (0..<(GeneratedLegacyChunkFacts.oldSectionCount * GeneratedLegacyChunkFacts.biomeContainerSize))
                .map { layer[$0 % layer.count] & 255 }
        }
        let size = GeneratedLegacyChunkFacts.biomeContainerSize
        guard values.count == GeneratedLegacyChunkFacts.oldSectionCount * size
                || values.count == GeneratedLegacyChunkFacts.newSectionCount * size else { return nil }
        return values.map { $0 & 255 }
    }

    private static func legacyBiomeContainer(_ values: [Int]?, offset: Int) -> NBT {
        guard let values else {
            return .compound(["palette": .list([.string(GeneratedLegacyChunkFacts.defaultBiome)])])
        }
        var codes: [Int] = []
        var indices: [Int] = []
        for value in values[offset..<(offset + GeneratedLegacyChunkFacts.biomeContainerSize)] {
            if let index = codes.firstIndex(of: value) { indices.append(index) }
            else { indices.append(codes.count); codes.append(value) }
        }
        let palette = codes.map { NBT.string(GeneratedLegacyChunkFacts.biomes[$0] ?? GeneratedLegacyChunkFacts.defaultBiome) }
        var fields: [String: NBT] = ["palette": .list(palette)]
        if codes.count > 1 {
            let bits = Int.bitWidth - (codes.count - 1).leadingZeroBitCount
            fields["data"] = .longArray(pack(indices, bits: bits))
        }
        return .compound(fields)
    }

    /// Structural word counts distinguish the two encodings, even when metadata is missing.
    /// Power-of-two widths already have the same representation and need no copy.
    private static func align(_ words: [Int64], entries: Int, bits: Int) -> [Int64] {
        guard (1..<64).contains(bits), words.count == (entries * bits + 63) / 64,
              words.count != PackedLongs.wordCount(entries: entries, bits: bits) else { return words }
        let mask = (UInt64(1) << bits) - 1
        let values = (0..<entries).map { index in
            let bit = index * bits, word = bit / 64, shift = bit % 64
            var value = UInt64(bitPattern: words[word]) >> shift
            if shift + bits > 64 { value |= UInt64(bitPattern: words[word + 1]) << (64 - shift) }
            return Int(value & mask)
        }
        return pack(values, bits: bits)
    }

    private static func pack(_ values: [Int], bits: Int) -> [Int64] {
        let perWord = 64 / bits
        var words = [UInt64](repeating: 0, count: PackedLongs.wordCount(entries: values.count, bits: bits))
        for (index, value) in values.enumerated() { words[index / perWord] |= UInt64(value) << ((index % perWord) * bits) }
        return words.map { Int64(bitPattern: $0) }
    }
}
