# MCWorldKit

A Swift library and command-line tool for reading Minecraft: Java Edition world saves, including the 26.x format changes.

- **NBT**: reading and writing, with Java's modified UTF-8 for strings.
- **Anvil region files** (`.mca`): gzip, zlib, uncompressed and LZ4 chunks, plus oversized chunks stored in `.mcc` files.
- **Chunks** (1.18 and later):
  - all three block-palette forms: 26.3 compact strings, `{"": id}` and `id`/`properties`, plus the older `Name`/`Properties`
  - cell biomes (4×4×4) and 26.4 per-block biomes
  - light, heightmaps, block entities and entities
- **World folders**: the 26.1+ layout (`dimensions/minecraft/<dim>`, `players/data`, `data/minecraft/*.dat`), with a fallback to the older `region/`, `DIM-1`, `DIM1` and `playerdata/` layout.
- **`level.dat`**: name, versions and version history, difficulty, spawn, singleplayer UUID and seed.

It is read-only apart from the NBT writer, and it never modifies world files.

## Requirements

- Swift 6.4 or later (Xcode 27)
- macOS 27 or later
- zlib (included with macOS)

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fahlman/MCWorldKit.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: ["MCWorldKit"]),
]
```

## Library usage

### Open a world

```swift
import MCWorldKit

let world = try World(contentsOf: URL(fileURLWithPath: "/path/to/saves/My World"))

print(world.level.name ?? "?")            // "My World"
print(world.level.versionName ?? "?")     // "26.3"
print(world.level.dataVersion ?? 0)       // 5023
print(world.level.difficulty ?? "?")      // "easy"
print(try world.seed() ?? 0)

if let spawn = world.level.spawnPosition {
    print("Spawn at \(spawn.x) \(spawn.y) \(spawn.z)")
}
```

### Dimensions, chunks and blocks

```swift
for dimension in world.dimensions() {
    print(dimension.id, dimension.regionFiles().count)  // "minecraft:overworld 357"
}

let overworld = world.dimension("overworld")!   // or "minecraft:the_nether", "mymod:custom"

// One-off lookup by world coordinates.
let state = try overworld.block(x: 10, y: 68, z: -2)
print(state?.description ?? "not generated")    // "minecraft:stone_bricks"

// Loading a chunk is faster when you read many blocks from it.
if let chunk = try overworld.chunk(x: 0, z: -1) {        // chunk coordinates
    let block = chunk.block(x: 10, y: 68, z: 14)         // chunk-local x/z, world y
    let biome = chunk.biome(x: 10, y: 68, z: 14)         // "minecraft:windswept_hills"
    print(chunk.status ?? "?", block?.id ?? "-", block?.properties ?? [:], biome ?? "-")

    let surface = chunk.heightmap("WORLD_SURFACE")       // 256 Y values, index = z * 16 + x
    let chest = chunk.blockEntity(x: 3, y: 64, z: 7)     // raw NBT
}

let entities = try overworld.entities(chunkX: 0, chunkZ: -1)
print(entities.compactMap { $0["id"]?.string })
```

A `BlockState` whose `properties` is empty is in its default state. Since 26.3, the game no longer saves the properties of default states.

### Iterate every chunk

```swift
var diamonds = 0
for (_, _, url) in overworld.regionFiles() {
    let region = try RegionFile(contentsOf: url)
    for (localX, localZ) in region.chunkCoordinates {
        guard let nbt = try region.chunkNBT(localX: localX, localZ: localZ) else { continue }
        let chunk = try Chunk(nbt: nbt)
        for section in chunk.sections {
            guard let states = section.blockStates else { continue }
            // Matches both minecraft:diamond_ore and minecraft:deepslate_diamond_ore.
            let ore = Set(states.palette.indices.filter { states.palette[$0].id.hasSuffix("diamond_ore") })
            guard !ore.isEmpty else { continue }
            diamonds += states.allPaletteIndices().filter(ore.contains).count
        }
    }
}
```

### Structures

```swift
// Structures are recorded in the chunk they start in; skip block data for a fast scan.
let region = try RegionFile(contentsOf: overworld.regionFiles()[0].url)
for (x, z) in region.chunkCoordinates {
    guard let nbt = try region.chunkNBT(localX: x, localZ: z, skipping: Chunk.keysNotNeededForStructures) else { continue }
    for start in StructureStart.starts(inChunk: nbt) {
        print(start.id, start.bounds as Any, start.pieces.map(\.id))  // e.g. a stronghold's "minecraft:shpr"
    }
}
```

### Points of interest

```swift
for (x, z) in overworld.pointOfInterestRegions() {
    for poi in try overworld.pointsOfInterest(regionX: x, regionZ: z) where poi.type == "minecraft:nether_portal" {
        print("portal block at", poi.x, poi.y, poi.z)
    }
}
```

### Items

```swift
for (x, z, _) in overworld.regionFiles() {
    for container in try overworld.containers(regionX: x, regionZ: z) {
        // allItems includes the contents of shulker boxes and bundles.
        let diamonds = container.allItems.filter { $0.id == "minecraft:diamond" }.reduce(0) { $0 + $1.count }
        if diamonds > 0 { print(container.kind, container.x, container.y, container.z, diamonds) }
    }
}
let pockets = player.inventory + player.enderChest   // PlayerInfo
```

### Signs and books

```swift
// One pass over a region reads both its containers and its signs.
let contents = try overworld.contents(regionX: 0, regionZ: 0)
for sign in contents.signs {
    print(sign.x, sign.y, sign.z, sign.front.joined(separator: " / "), sign.back)
}
for item in contents.containers.flatMap(\.allItems) {
    if let book = item.book { print(book.title ?? "book and quill", book.author ?? "", book.pages.count) }
}
```

### Nether portals

```swift
let overworldPortals = try overworld.netherPortals()
let netherPortals = try world.dimension("the_nether")!.netherPortals()
for portal in overworldPortals {
    switch portal.link(into: netherPortals) {
    case .portal(let target, let block)?: print("leads to the portal at", target.centerX, target.centerZ, "arriving at", block)
    case .wouldCreateNewPortal(let destination)?: print("would create a new portal near", destination)
    case nil: break
    }
}
```

### Players and saved data

```swift
for uuid in world.playerUUIDs() {
    let player = try world.playerData(uuid)
    print(uuid, player?["Health"]?.double ?? 0)
    let stats = world.playerJSON(uuid, kind: "stats")   // URL of the stats JSON file
}

let gameRules = try world.savedData("game_rules")       // data/minecraft/game_rules.dat

// Player files hold only UUIDs; Minecraft's usercache.json files map them to names.
let names = UserCache.names(under: URL(fileURLWithPath: "/Users/me/Library/Application Support/minecraft"))

for player in world.players() {                         // most recently saved first
    print(names[player.uuid]?.name ?? "unknown name")
    print(player.uuid, player.position?.dimension ?? "?", player.position?.x ?? 0, player.position?.z ?? 0)
    print("  died at", player.lastDeath as Any, "respawns at", player.respawn as Any)
    if player.isFromBukkitServer { print("  locations may be in another world:", player.bukkitWorldName ?? "?") }
}
```

### Raw NBT

```swift
let level = try NBT.read(contentsOf: url)               // handles gzip and zlib automatically
let name = level["Data"]?["LevelName"]?.string

let bytes = NBT.compound(["answer": .int(42)]).serialized()
let (rootName, value) = try NBT.read(bytes)
```

Every decoded type keeps its source NBT (`chunk.nbt` and `world.level.nbt`), so you can read fields the typed API doesn't cover.

## Command-line tool

Build the tool:

```bash
swift build -c release
```

Print a world summary:

```bash
.build/release/mcworld "$HOME/Library/Application Support/minecraft/saves/My World"
```

```
Name:            My World
Version:         26.3 (data version 5023)
Layout:          26.1+ (dimensions/)
Difficulty:      easy
Seed:            2077048737
Spawn:           10 69 -2 in minecraft:overworld
Dimensions:
  minecraft:overworld: 357 region files
  minecraft:the_nether: 45 region files
  minecraft:the_end: 4 region files
```

Other commands:

| Command | Output |
|---|---|
| `mcworld <world> block <x> <y> <z> [dimension]` | Block, biome and block entity at a world position |
| `mcworld <world> chunk <cx> <cz> [dimension]` | Each section's palette, bit width and biomes |
| `mcworld <world> scan [dimension]` | Decodes every chunk, reports block counts and any errors |
| `mcworld <world> structures [dimension]` | Structures in generated chunks, by kind, with positions |
| `mcworld <world> poi [dimension]` | Points of interest (beds, workstations, portals, bells…) by type |
| `mcworld <world> find <text> [dimension]` | Containers and players holding items whose id or custom name matches |
| `mcworld <world> text <text> [dimension]` | Signs and books whose text matches |
| `mcworld <world> portals` | Nether portals and where each one leads, flagging one-way links |
| `mcworld <world> players` | Each player's name (from the game folder's `usercache.json`), last position, last death and respawn point |

For example:

```bash
.build/release/mcworld "<world>" block 10 68 -2
```

```bash
.build/release/mcworld "<world>" scan minecraft:the_nether
```

## Format notes

| Version | Data version | Change | Handling |
|---|---|---|---|
| 1.18 | 2844 | Chunk fields moved to the root; `block_states` and `biomes` became paletted containers | Older chunks are rejected with `ChunkError.unsupportedLegacyFormat` |
| 1.20.5 | | LZ4 chunk compression (lz4-java block framing) | Supported; checksums are not verified |
| 26.1 | | Vanilla dimensions moved to `dimensions/minecraft/*`, player files to `players/`, world settings to `data/minecraft/` | Both the new and old layouts are read |
| 26.3 | 5009 | Block palettes use `id`/`properties`, may be lists of strings, and omit default properties | All forms are accepted |
| 26.4 | 5119 | Biomes stored per block (4096 per section); `Status` renamed to `status` | Detected from the data length; both names are read |

Chunks upgraded from pre-1.18 worlds can keep a leftover `Level: {Structures}` compound. These chunks are parsed normally.

## Testing

```bash
swift test
```

The tests use synthetic worlds and region files, so you don't need any Minecraft data to run them.

## License

MIT. See [LICENSE](LICENSE).
