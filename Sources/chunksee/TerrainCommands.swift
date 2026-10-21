import Foundation
import ChunkseeKit

/// Commands that read terrain: chunks, blocks, structures and time spent.

func chunkCommand(_ world: World, _ arguments: Arguments) throws {
        let (cx, cz) = (arguments.int(1), arguments.int(2))
        guard let chunk = try arguments.dimension(3, in: world).chunk(x: cx, z: cz) else { fail("chunk \(cx), \(cz) not generated") }
        print("Chunk \(chunk.x), \(chunk.z)  data version \(chunk.dataVersion)  status \(chunk.status ?? "?")")
        print("Block entities: \(chunk.blockEntities.count)")
        for s in chunk.sections {
            guard let states = s.blockStates else { continue }
            if states.palette.allSatisfy(\.isAir) { continue }
            let names = states.palette.map(\.description)
            let biomes = s.biomes?.palette.joined(separator: ", ") ?? "-"
            print("  section y=\(s.y): \(names.count) states (\(states.bitsPerEntry) bits), biomes [\(biomes)]")
            for n in names.prefix(8) { print("    \(n)") }
            if names.count > 8 { print("    … \(names.count - 8) more") }
        }
}

func blockCommand(_ world: World, _ arguments: Arguments) throws {
        let (x, y, z) = (arguments.int(1), arguments.int(2), arguments.int(3))
        let dim = arguments.dimension(4, in: world)
        let position = BlockPosition(blockX: x, blockY: y, blockZ: z)
        guard let chunk = try dim.chunk(at: position.chunk) else { fail("chunk not generated") }
        print("Block: \(chunk.block(x: x & 15, y: y, z: z & 15)?.description ?? "none")")
        print("Biome: \(chunk.biome(x: x & 15, y: y, z: z & 15) ?? "none")")
        if let be = chunk.blockEntity(x: x, y: y, z: z) { print("Block entity: \(be.id ?? "?")") }
}

func timeCommand(_ world: World, _ arguments: Arguments) async {
        // Chunks where players spent the most time; regions are read in parallel.
        let dim = arguments.dimension(1, in: world)
        let chunks = await withTaskGroup(of: [(x: Int, z: Int, ticks: Int)].self) { group in
            for region in dim.regionFiles() {
                group.addTask {
                    // Read into a local first: Swift 6.4 release builds can misread values captured
                    // next to an awaited call in task-group children (see fahlman/Chunksee#6).
                    let times = (try? dim.inhabitedTimes(regionX: region.x, regionZ: region.z)) ?? []
                    return times.enumerated().filter { $0.element > 0 }.map { (region.x * 32 + $0.offset % 32, region.z * 32 + $0.offset / 32, $0.element) }
                }
            }
            var all: [(x: Int, z: Int, ticks: Int)] = []
            for await found in group { all += found }
            return all
        }
        print("\(chunks.count) chunks with time recorded")
        for chunk in chunks.sorted(by: { $0.ticks > $1.ticks }).prefix(10) {
            print("  chunk \(chunk.x), \(chunk.z) (blocks \(chunk.x * 16), \(chunk.z * 16)): \(chunk.ticks / 72_000) hours")
        }
}

func structuresCommand(_ world: World, _ arguments: Arguments) {
        let dims = arguments.dimensions(1, in: world)
        for dim in dims {
            var byKind: [String: [StructureStart]] = [:]
            for region in dim.regionFiles() {
                try? dim.forEachChunk(regionX: region.x, regionZ: region.z, skipping: Chunk.keysNotNeededForStructures) { _, _, nbt in
                    guard let chunk = try? Chunk(nbt: nbt), chunk.isFullyGenerated else { return }
                    for start in chunk.structureStarts { byKind[start.id, default: []].append(start) }
                }
            }
            print("\(dim.id): \(byKind.values.reduce(0) { $0 + $1.count }) structures")
            for (id, starts) in byKind.sorted(by: { byCount(($0.key, $0.value.count), ($1.key, $1.value.count)) }) {
                let places = starts.prefix(4).compactMap(\.bounds).compactMap { box -> String? in
                    // BlockBox includes both endpoints; the center is halfway between its outer faces.
                    guard let x = BlockPosition.coordinate(containing: (Double(box.minX) + Double(box.maxX) + 1) / 2),
                          let z = BlockPosition.coordinate(containing: (Double(box.minZ) + Double(box.maxZ) + 1) / 2) else { return nil }
                    return "(\(x), \(z))"
                }
                print("  \(starts.count)\t\(id)  \(places.joined(separator: " "))\(starts.count > 4 ? " …" : "")")
            }
        }
}
