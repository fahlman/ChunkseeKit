import Foundation
import ChunkseeKit

/// Totals from decoding chunks, mergeable so regions can be scanned independently.
struct ScanTally: Sendable {
    var chunks = 0
    var sections = 0
    var entityChunks = 0
    var errors: [String: Int] = [:]
    var blockCounts: [String: Int] = [:]

    mutating func merge(_ other: ScanTally) {
        chunks += other.chunks
        sections += other.sections
        entityChunks += other.entityChunks
        errors.merge(other.errors, uniquingKeysWith: +)
        blockCounts.merge(other.blockCounts, uniquingKeysWith: +)
    }
}

/// Decodes every chunk in a dimension. Region files are independent, so up to one per core is
/// scanned at a time; each region is read and decoded on a single task.
func scan(_ dimension: ChunkseeKit.Dimension) async -> ScanTally {
    let regions = dimension.regionFiles()
    let width = max(1, ProcessInfo.processInfo.activeProcessorCount)
    return await withTaskGroup(of: ScanTally.self) { group in
        var next = regions.startIndex
        func startNext() {
            guard next < regions.endIndex else { return }
            let region = regions[next]
            next += 1
            group.addTask { scanRegion(x: region.x, z: region.z, url: region.url, in: dimension) }
        }
        for _ in 0..<width { startNext() }
        var total = ScanTally()
        for await tally in group {
            total.merge(tally)
            startNext()
        }
        return total
    }
}

func scanRegion(x rx: Int, z rz: Int, url: URL, in dimension: ChunkseeKit.Dimension) -> ScanTally {
    var tally = ScanTally()
    let region: RegionFile
    do { region = try RegionFile(contentsOf: url) } catch {
        tally.errors["\(error)", default: 0] += 1
        return tally
    }
    for (lx, lz) in region.chunkCoordinates {
        do {
            guard let nbt = try region.chunkNBT(localX: lx, localZ: lz) else { continue }
            let chunk = try Chunk(nbt: nbt)
            guard chunk.x == rx * 32 + lx, chunk.z == rz * 32 + lz else {
                tally.errors["position mismatch", default: 0] += 1
                continue
            }
            tally.chunks += 1
            for section in chunk.sections {
                guard let states = section.blockStates else { continue }
                tally.sections += 1
                for (i, n) in states.paletteCounts().enumerated() { tally.blockCounts[states.palette[i].id, default: 0] += n }
            }
            tally.entityChunks += try dimension.entities(chunkX: chunk.x, chunkZ: chunk.z).isEmpty ? 0 : 1
        } catch {
            tally.errors["\(error)", default: 0] += 1
        }
    }
    return tally
}

func scanCommand(_ world: World, _ arguments: Arguments) async {
        let dims = arguments.dimensions(1, in: world)
        for dim in dims {
            let tally = await scan(dim)
            print("\(dim.id): \(tally.chunks) chunks, \(tally.sections) sections, \(tally.entityChunks) chunks with entities")
            // Ties sort by name so the output is the same on every run.
            let byCount: ((key: String, value: Int), (key: String, value: Int)) -> Bool = {
                $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }
            for (id, n) in tally.blockCounts.sorted(by: byCount).prefix(8) { print("  \(n)\t\(id)") }
            for (e, n) in tally.errors.sorted(by: byCount) { print("  ERROR ×\(n): \(e)") }
        }
}
