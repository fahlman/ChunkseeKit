import Foundation
import MCWorldKit

let usage = """
usage:
  mcworld <world>                                   world summary
  mcworld <world> chunk <cx> <cz> [dimension]       chunk summary
  mcworld <world> block <x> <y> <z> [dimension]     block and biome at a position
  mcworld <world> scan [dimension]                  decode every chunk and report errors
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first else { fail(usage) }

do {
    let world = try World(contentsOf: URL(fileURLWithPath: path))
    let rest = Array(args.dropFirst())

    func dimension(_ index: Int) -> MCWorldKit.Dimension {
        let id = rest.count > index ? rest[index] : "minecraft:overworld"
        guard let d = world.dimension(id) else { fail("no such dimension: \(id)") }
        return d
    }
    func int(_ index: Int) -> Int {
        guard rest.count > index, let v = Int(rest[index]) else { fail(usage) }
        return v
    }

    switch rest.first {
    case nil:
        let l = world.level
        print("Name:            \(l.name ?? "?")")
        print("Version:         \(l.versionName ?? "?") (data version \(l.dataVersion.map(String.init) ?? "?"))")
        if !l.versionHistory.isEmpty { print("Version history: \(l.versionHistory.map(String.init).joined(separator: ", "))") }
        print("Layout:          \(world.usesDimensionsFolderForVanilla ? "26.1+ (dimensions/)" : "legacy")")
        print("Difficulty:      \(l.difficulty ?? "?")\(l.isHardcore == true ? " (hardcore)" : "")")
        if let seed = try? world.seed() { print("Seed:            \(seed)") }
        if let p = l.spawnPosition { print("Spawn:           \(p.x) \(p.y) \(p.z) in \(l.spawnDimension ?? "?")") }
        if let uuid = l.singleplayerUUID { print("Player:          \(uuid.uuidString.lowercased())") }
        if let date = l.lastPlayed { print("Last played:     \(date)") }
        print("Dimensions:")
        for d in world.dimensions() { print("  \(d.id): \(d.regionFiles().count) region files") }
        print("Players with data: \(world.playerUUIDs().count)")

    case "chunk":
        let (cx, cz) = (int(1), int(2))
        guard let chunk = try dimension(3).chunk(x: cx, z: cz) else { fail("chunk \(cx), \(cz) not generated") }
        print("Chunk \(chunk.x), \(chunk.z)  data version \(chunk.dataVersion)  status \(chunk.status ?? "?")")
        print("Block entities: \(chunk.blockEntities.count)")
        for s in chunk.sections {
            guard let states = s.blockStates else { continue }
            let names = states.palette.map(\.description)
            if names == ["minecraft:air"] { continue }
            let biomes = s.biomes?.palette.joined(separator: ", ") ?? "-"
            print("  section y=\(s.y): \(names.count) states (\(states.bitsPerEntry) bits), biomes [\(biomes)]")
            for n in names.prefix(8) { print("    \(n)") }
            if names.count > 8 { print("    … \(names.count - 8) more") }
        }

    case "block":
        let (x, y, z) = (int(1), int(2), int(3))
        let dim = dimension(4)
        guard let chunk = try dim.chunk(x: x >> 4, z: z >> 4) else { fail("chunk not generated") }
        print("Block: \(chunk.block(x: x & 15, y: y, z: z & 15)?.description ?? "none")")
        print("Biome: \(chunk.biome(x: x & 15, y: y, z: z & 15) ?? "none")")
        if let be = chunk.blockEntity(x: x, y: y, z: z) { print("Block entity: \(be["id"]?.string ?? "?")") }

    case "scan":
        let dims = rest.count > 1 ? [dimension(1)] : world.dimensions()
        for dim in dims {
            var chunks = 0, sections = 0, entityChunks = 0
            var errors = [String: Int]()
            var counts = [String: Int]()
            for (rx, rz, url) in dim.regionFiles() {
                let region: RegionFile
                do { region = try RegionFile(contentsOf: url) } catch { errors["\(error)", default: 0] += 1; continue }
                for (lx, lz) in region.chunkCoordinates {
                    do {
                        guard let nbt = try region.chunkNBT(localX: lx, localZ: lz) else { continue }
                        let chunk = try Chunk(nbt: nbt)
                        guard chunk.x == rx * 32 + lx, chunk.z == rz * 32 + lz else {
                            errors["position mismatch", default: 0] += 1; continue
                        }
                        chunks += 1
                        for s in chunk.sections {
                            guard let states = s.blockStates else { continue }
                            sections += 1
                            var perIndex = [Int](repeating: 0, count: states.palette.count)
                            for i in states.allPaletteIndices() where i < perIndex.count { perIndex[i] += 1 }
                            for (i, n) in perIndex.enumerated() { counts[states.palette[i].id, default: 0] += n }
                        }
                        entityChunks += try dim.entities(chunkX: chunk.x, chunkZ: chunk.z).isEmpty ? 0 : 1
                    } catch {
                        errors["\(error)", default: 0] += 1
                    }
                }
            }
            print("\(dim.id): \(chunks) chunks, \(sections) sections, \(entityChunks) chunks with entities")
            for (id, n) in counts.sorted(by: { $0.value > $1.value }).prefix(8) { print("  \(n)\t\(id)") }
            for (e, n) in errors.sorted(by: { $0.value > $1.value }) { print("  ERROR ×\(n): \(e)") }
        }

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
