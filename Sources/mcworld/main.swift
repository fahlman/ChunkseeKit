import Foundation
import MCWorldKit

let usage = """
usage:
  mcworld <world>                                   world summary
  mcworld <world> chunk <cx> <cz> [dimension]       chunk summary
  mcworld <world> block <x> <y> <z> [dimension]     block and biome at a position
  mcworld <world> scan [dimension]                  decode every chunk and report errors
  mcworld <world> players                           players' last positions, deaths and respawn points
  mcworld <world> structures [dimension]            structures found in generated chunks, by kind
  mcworld <world> poi [dimension]                   points of interest (beds, workstations, portals…) by type
  mcworld <world> portals                           Nether portals and where each one leads
  mcworld <world> find <text> [dimension]           containers and players holding matching items
  mcworld <world> text <text> [dimension]           signs and books containing the text
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

    case "players":
        func show(_ location: PlayerInfo.Location?) -> String {
            guard let l = location else { return "-" }
            return "\(l.dimension) \(Int(l.x.rounded(.down))) \(Int(l.y.rounded(.down))) \(Int(l.z.rounded(.down)))"
        }
        // The game folder holding this world's saves folder keeps the local name cache.
        let gameFolder = world.url.deletingLastPathComponent().deletingLastPathComponent()
        let names = UserCache.names(under: gameFolder, depth: 0)
        for player in world.players() {
            let you = player.uuid == world.level.singleplayerUUID ? " (singleplayer)" : ""
            let name = names[player.uuid].map { " \($0.name)" } ?? ""
            print("\(player.uuid.uuidString.lowercased())\(name)\(you)")
            print("  saved:    \(player.lastSaved.map { "\($0)" } ?? "?")  data version \(player.dataVersion.map(String.init) ?? "none")")
            print("  position: \(player.position.map { show($0) } ?? "unknown dimension \(player.unrecognizedDimension ?? "?")")")
            print("  death:    \(show(player.lastDeath))")
            print("  respawn:  \(show(player.respawn))")
            if player.isFromBukkitServer { print("  written by a Bukkit server\(player.bukkitWorldName.map { " (world \"\($0)\")" } ?? "")") }
        }

    case "find":
        guard rest.count > 1 else { fail(usage) }
        let query = rest[1].lowercased()
        func matches(_ item: ItemStack) -> Bool {
            item.id.lowercased().contains(query) || (item.customName?.lowercased().contains(query) ?? false)
        }
        func summary(_ items: [ItemStack]) -> String {
            let hits = items.flatMap(\.allItems).filter(matches)
            let byID = Dictionary(grouping: hits, by: { $0.customName.map { "\"\($0)\"" } ?? $0.id }).mapValues { $0.reduce(0) { $0 + $1.count } }
            return byID.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        }
        for player in world.players() {
            for (label, items) in [("inventory", player.inventory + Array(player.equipment.values)), ("ender chest", player.enderChest)] {
                let found = summary(items)
                if !found.isEmpty { print("player \(player.uuid.uuidString.prefix(8).lowercased()) \(label): \(found)") }
            }
        }
        let dims = rest.count > 2 ? [dimension(2)] : world.dimensions()
        var total = 0
        for dim in dims {
            for (rx, rz, _) in dim.regionFiles() {
                for container in (try? dim.containers(regionX: rx, regionZ: rz)) ?? [] {
                    let found = summary(container.items)
                    guard !found.isEmpty else { continue }
                    total += 1
                    let name = container.customName.map { " \"\($0)\"" } ?? ""
                    print("\(dim.id) \(container.kind)\(name) at (\(container.x), \(container.y), \(container.z)): \(found)")
                }
            }
        }
        print("\(total) containers")

    case "text":
        guard rest.count > 1 else { fail(usage) }
        let query = rest[1].lowercased()
        func books(_ items: [ItemStack]) -> [String] {
            items.flatMap(\.allItems).compactMap { item in
                guard let book = item.book else { return nil }
                let text = ([book.title, book.author].compactMap(\.self) + book.pages).joined(separator: "\n")
                guard text.lowercased().contains(query) else { return nil }
                return book.title.map { "\"\($0)\" by \(book.author ?? "?")" } ?? "book and quill"
            }
        }
        for player in world.players() {
            for book in books(player.inventory + player.enderChest) {
                print("player \(player.uuid.uuidString.prefix(8).lowercased()): \(book)")
            }
        }
        let dims = rest.count > 2 ? [dimension(2)] : world.dimensions()
        var total = 0
        for dim in dims {
            for (rx, rz, _) in dim.regionFiles() {
                guard let contents = try? dim.contents(regionX: rx, regionZ: rz) else { continue }
                for sign in contents.signs {
                    let lines = (sign.front + sign.back).filter { !$0.isEmpty }
                    guard lines.joined(separator: " ").lowercased().contains(query) else { continue }
                    total += 1
                    print("\(dim.id) \(sign.kind) at (\(sign.x), \(sign.y), \(sign.z)): \(lines.joined(separator: " / "))")
                }
                for container in contents.containers {
                    for book in books(container.items) {
                        total += 1
                        print("\(dim.id) \(container.kind) at (\(container.x), \(container.y), \(container.z)): \(book)")
                    }
                }
            }
        }
        print("\(total) matches")

    case "portals":
        guard let overworld = world.dimension("overworld"), let nether = world.dimension("the_nether") else {
            fail("this world needs both an Overworld and a Nether")
        }
        let overworldPortals = try overworld.netherPortals(), netherPortals = try nether.netherPortals()
        func describe(_ p: NetherPortal) -> String { "(\(Int(p.centerX.rounded(.down))), \(p.minY), \(Int(p.centerZ.rounded(.down))))" }
        func show(_ portals: [NetherPortal], _ candidates: [NetherPortal], back: [NetherPortal], label: String) {
            print("\(label): \(portals.count) portals")
            for portal in portals {
                switch portal.link(into: candidates) {
                case .portal(let target, _)?:
                    // Does the target lead back here?
                    var note = ""
                    if case .portal(let returns, _)? = target.link(into: back), returns != portal { note = "  (one-way: it leads back to \(describe(returns)))" }
                    print("  \(describe(portal)) -> \(describe(target))\(note)")
                case .wouldCreateNewPortal(let destination)?:
                    print("  \(describe(portal)) -> no portal in range; would create one near (\(destination.x), \(destination.y), \(destination.z))")
                case nil:
                    print("  \(describe(portal)) -> ?")
                }
            }
        }
        show(overworldPortals, netherPortals, back: overworldPortals, label: "Overworld")
        show(netherPortals, overworldPortals, back: netherPortals, label: "Nether")

    case "poi":
        let dims = rest.count > 1 ? [dimension(1)] : world.dimensions()
        for dim in dims {
            var byType: [String: [PointOfInterest]] = [:]
            for (x, z) in dim.pointOfInterestRegions() {
                for poi in (try? dim.pointsOfInterest(regionX: x, regionZ: z)) ?? [] { byType[poi.type, default: []].append(poi) }
            }
            print("\(dim.id): \(byType.values.reduce(0) { $0 + $1.count }) points of interest")
            for (type, list) in byType.sorted(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }) {
                let places = list.prefix(3).map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: " ")
                print("  \(list.count)\t\(type)  \(places)\(list.count > 3 ? " …" : "")")
            }
        }

    case "structures":
        let dims = rest.count > 1 ? [dimension(1)] : world.dimensions()
        for dim in dims {
            var byKind: [String: [StructureStart]] = [:]
            for (_, _, url) in dim.regionFiles() {
                guard let region = try? RegionFile(contentsOf: url) else { continue }
                for (lx, lz) in region.chunkCoordinates {
                    guard let nbt = try? region.chunkNBT(localX: lx, localZ: lz, skipping: Chunk.keysNotNeededForStructures) else { continue }
                    for start in StructureStart.starts(inChunk: nbt) { byKind[start.id, default: []].append(start) }
                }
            }
            print("\(dim.id): \(byKind.values.reduce(0) { $0 + $1.count }) structures")
            for (id, starts) in byKind.sorted(by: { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }) {
                let places = starts.prefix(4).compactMap(\.bounds).map { "(\(($0.minX + $0.maxX) / 2), \(($0.minZ + $0.maxZ) / 2))" }
                print("  \(starts.count)\t\(id)  \(places.joined(separator: " "))\(starts.count > 4 ? " …" : "")")
            }
        }

    case "scan":
        let dims = rest.count > 1 ? [dimension(1)] : world.dimensions()
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

    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
