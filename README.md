# ChunkseeKit

A Swift library and command-line tool for reading Minecraft: Java Edition world saves, including the 26.x format changes.

- **NBT**: reading and writing, with Java's modified UTF-8 for strings.
- **Anvil region files** (`.mca`): gzip, zlib, uncompressed and LZ4 chunks, plus oversized chunks stored in `.mcc` files.
- **Chunks** (1.18 and later):
  - all three block-palette forms: 26.3 compact strings, `{"": id}` and `id`/`properties`, plus the older `Name`/`Properties`
  - cell biomes (4×4×4) and 26.4 per-block biomes
  - light, heightmaps, block entities and entities
- **World folders**: the 26.1+ layout (`dimensions/minecraft/<dim>`, `players/data`, `data/minecraft/*.dat`), with a fallback to the older `region/`, `DIM-1`, `DIM1` and `playerdata/` layout.
- **`level.dat`**: name, versions and version history, difficulty, spawn, singleplayer UUID and seed.
- **UUIDs**: strings, four-int arrays and legacy `UUIDMost`/`UUIDLeast` pairs share one reader;
  older embedded singleplayer records use the same identity and player-data fallback as current saves.

It is read-only apart from the NBT writer, and it never modifies world files.

## Requirements

- Swift 6.4 or later (Xcode 27)
- macOS 27 or later
- zlib (included with macOS)

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fahlman/ChunkseeKit.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: ["ChunkseeKit"]),
]
```

## Library usage

### Open a world

```swift
import ChunkseeKit

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
    // regionFiles(.entities) and regionFiles(.pointsOfInterest) list the other two folders.
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

Invalid or empty starts and temples/huts explicitly marked as unplaced are excluded. Minecraft
doesn't record a universal placement flag for every structure type; unknown placement is retained.
For a map of explored terrain, also check `Chunk.isFullyGenerated`.

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
for (x, z, _) in overworld.regionFiles(.pointsOfInterest) {
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

### Spawners

```swift
// Monster spawners and the mob each spawns (nil for an empty one); trial spawners aren't included.
for spawner in try overworld.contents(regionX: 0, regionZ: 0).spawners {
    print(spawner.mob ?? "empty", spawner.x, spawner.y, spawner.z)
}
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

### Creatures

```swift
for creature in try overworld.creatures(regionX: 0, regionZ: 0) {
    if let owner = creature.owner { print(creature.id, creature.customName ?? "", "tamed by", owner) }
    if let health = creature.health { print(health / 2, "hearts") }
    if let villager = creature.villager {
        print(villager.profession ?? "?", villager.level ?? 0, villager.trades.map { "\($0.buy.count) \($0.buy.id) → \($0.sell.id)" })
        // Enchanted books for sale, e.g. ["minecraft:mending": 1].
        for trade in villager.trades where !trade.sell.enchantments.isEmpty { print(trade.sell.enchantments) }
    }
}
```

Creature `health` and `maxHealth` use half-hearts. Maximum health comes from the saved attribute
and its permanent modifiers, including the legacy `Attributes` format. Verified defaults fill
an omitted attribute for cats (10), parrots (6) and wolves (8) in exactly 26.1/4786, 26.1.1/4788,
26.1.2/4790, 26.2/4903 and 26.3/5023. The other documented pet defaults apply only in 26.3/5023. Unknown species/versions
need an explicit maximum attribute; no defaults are inferred for adjacent snapshot versions.
The official clients' attribute builders and taming load paths were checked for these versions.
In these verified versions, an unowned wolf's loaded base is reset to 8 even when the save records another base; its permanent
modifiers remain. An owned wolf preserves its saved base. A saved owner that cannot be identified
leaves that wolf maximum unavailable rather than treating it as untamed. Health Boost is a permanent saved
attribute modifier and is counted once from that list. Applicable equipped-item modifiers are
combined with the saved modifiers, in slot order with duplicate identities replaced. Players
and creatures share slot-group, broken/empty-item and removed-component rules. Unsupported
modded item or active-effect defaults leave the maximum unavailable instead of returning a partial total.
Equipped active enchantments outside the 43 verified vanilla 26.3 definitions also leave it unavailable:
their data-pack definitions can add transient health modifiers absent from saved attributes. Stored
book enchantments, removed enchantments and empty/broken equipment do not contribute. This applies
to current, wrapped and legacy item formats. Vanilla definitions are assumed unchanged; data packs
that override vanilla enchantment IDs are not resolved and can still make a total incomplete.
The result uses Minecraft's Float precision. No maximum is guessed from current health.

Owned pets also expose `sittingOrder` (wolves/cats/parrots), `appearance` (wolf/cat coat,
parrot color, horse coat and markings, llama color), `collarColor` (wolves/cats), and `equipment`
by slot. An empty equipment dictionary means a pet that can wear equipment has none; nil means
not applicable or unavailable. Equipment reads current slots, legacy `ArmorItems`/`HandItems`
lists, older body armor, horse armor/saddle, llama decor and attached chest fields. A current
creature equipment compound supersedes those older fields, including when explicitly empty.
Older horse `ArmorItem` conversion clears the former chest entry, as Minecraft's data fix does;
llama decor conversion retains other armor slots.
Only the game's eight equipment slots participate in health; an attached storage chest is descriptive.
Item `durability` uses saved damage and
maximum components; vanilla wolf armor has an implicit maximum of 64. Unbreakable equipment
has no durability value. These are saved values, not live pose or following behavior.

`CreatureAppearance` normalizes numeric appearance values into symbolic keys with a `minecraft:`
prefix: parrot colors, horse coats/markings and llama colors. These are engine keys, not registry
IDs saved by Minecraft; wolf and cat variants retain their actual registry IDs. Equipment uses
the game's slot names (including `body` and `saddle`). The additional `storage` key is a derived
indicator for an attached chest (`ChestedHorse`), represented by a chest item; it is not an
equipped slot or a replacement for the animal's carried inventory. Equipment/default health also
cover the nautilus, zombie nautilus and camel husk in 26.3.

All new stored fields are optional so old cached creatures still decode. Rebuild those caches
to obtain the new values. `Creature.creatures(inEntityChunk:)` passes the chunk's saved version;
callers decoding a single entity may use `Creature(entity, dataVersion: chunkVersion)`.
For one chunk, `try dimension.creatures(chunkX: x, chunkZ: z)` retains the saved entity version
automatically. `dimension.entities` still returns raw NBT without that context; existing callers
remain source compatible. The per-chunk creature method is additive public API and requires a
minor release. Cache users should reread creatures when adopting the corrected maximums.

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

let rules = try world.gameRules()                       // ["minecraft:keep_inventory": .bool(false), …]
let weather = try world.weather()
let border = try world.worldBorder(of: overworld)       // isLimited is false for the default border
let dragon = try world.enderDragonFight()               // isDefeated, needsStateScanning, remainingGateways
let trader = try world.wanderingTrader()                // spawnDelay (ticks of play), spawnChance (%)

// Player files hold only UUIDs; Minecraft's usercache.json files map them to names.
let minecraft = URL(fileURLWithPath: "/Users/me/Library/Application Support/minecraft")
let names = UserCache.names(under: minecraft)

// Every biome Minecraft 26.3 generates in a vanilla dimension; custom dimensions have none listed.
let overworldBiomes = world.dimension("overworld")!.vanillaBiomes   // 56, from "minecraft:mushroom_fields" on

// Every saved world in every installation's game folder (backups aren't included).
let worlds = World.saved(under: minecraft).compactMap { try? World(contentsOf: $0) }

for player in world.players() {                         // most recently saved first
    print(names[player.uuid]?.name ?? "unknown name")
    print(player.uuid, player.position?.dimension ?? "?", player.position?.x ?? 0, player.position?.z ?? 0)
    print("  died at", player.lastDeath as Any, "respawns at", player.respawn as Any)
    print("  ", player.gameMode as Any, player.health ?? 0, player.foodLevel ?? 0, player.experienceLevel ?? 0)
    print("  maximum health", player.maxHealth as Any)  // half-hearts; nil if unavailable
    for effect in player.activeEffects {
        print(effect.id, effect.level, effect.durationTicks) // ticks at save time; -1 is infinite
    }
    if player.isFromBukkitServer { print("  locations may be in another world:", player.bukkitWorldName ?? "?") }
    let stats = try world.statistics(for: player.uuid)            // statistics(forName:) for files from before 1.7.6
    print("  played", (stats?.playTime ?? 0) / 72_000, "hours, mined", stats?.value("minecraft:stone", in: "minecraft:mined") ?? 0, "stone")
    let advancements = try world.advancements(for: player.uuid) ?? []
    print("  ", advancements.filter { $0.isDone && !$0.isRecipe }.count, "advancements")
}
```

Player maximum health uses the same saved attribute arithmetic as creatures, including permanent
Health Boost in modern and legacy saves. It is not reconstructed from the effect list. Equipped-item
modifiers are added separately. Only the selected hotbar item (or explicit saved
main hand) contributes main-hand modifiers; slot groups and duplicate modifier IDs are honored.
The omitted vanilla player base is supplied only for verified 26.3/data-version-5023 saves.
Unknown defaults, modifier operations or unsupported effect/item/active-enchantment defaults leave
the maximum nil. The same vanilla-enchantment override limitation described for creatures applies.
Active effects read modern names and legacy numeric IDs, omitting expired/malformed entries
and queued `hidden_effect` values. They describe the save and do not count down in real time.

`ItemStack.durability` now also knows the vanilla 26.3 defaults for armor, tools, weapons,
elytra, shields and other damageable equipment. Explicit maximum components override those
defaults; unbreakable and removed damage components suppress durability. Before 1.13, top-level
`Damage` is retained in the existing legacy components value, including when a `tag` is present;
older serialized ItemStacks still decode, but caches must be reread for previously discarded wear.
Custom item IDs need an explicit maximum and damage component. A maximum alone does not make an
item damageable. Enchantments remain available through `ItemStack.enchantments`.

`Creature.uuid` preserves current UUID arrays/strings and older UUIDMost/UUIDLeast pairs, so
callers can distinguish co-located creatures and track a moving one. It defaults to nil for
older cached creatures; rebuild caches before relying on the identity.

### Maps made in the game

```swift
for map in world.mapItems() where !map.isBlank {
    // 128×128 color ids; pixel (0, 0) is at world (map.minX, map.minZ), each covering map.blocksPerPixel blocks.
    let pixels = map.colors.map { MapItem.rgb(forColor: $0) }   // nil is transparent
    print(map.id, map.dimension ?? "?", map.centerX, map.centerZ, pixels.count)
}
```

### Raw NBT

```swift
let level = try NBT.read(contentsOf: url)               // handles gzip and zlib automatically
let name = level["Data"]?["LevelName"]?.string

let bytes = NBT.compound(["answer": .int(42)]).serialized()
let (rootName, value) = try NBT.read(bytes)
```

`ItemStack`, `ItemContainer`, `Spawner`, `Sign`, `BookContent`, `Creature`, `Villager`, `Trade`, `PointOfInterest`, `RegionContents` and `NBT` are `Codable`, so an app can cache scan results; `NBT` encodes as binary NBT.

Every decoded type keeps its source NBT (`chunk.nbt` and `world.level.nbt`), so you can read fields the typed API doesn't cover.

## Command-line tool

Build the tool:

```bash
swift build -c release
```

Print a world summary:

```bash
.build/release/chunksee "$HOME/Library/Application Support/minecraft/saves/My World"
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
| `chunksee <world> block <x> <y> <z> [dimension]` | Block, biome and block entity at a world position |
| `chunksee <world> chunk <cx> <cz> [dimension]` | Each section's palette, bit width and biomes |
| `chunksee <world> scan [dimension]` | Decodes every chunk, reports block counts and any errors |
| `chunksee <world> structures [dimension]` | Structures in generated chunks, by kind, with positions |
| `chunksee <world> poi [dimension]` | Points of interest (beds, workstations, portals, bells…) by type |
| `chunksee <world> find <text> [dimension]` | Containers and players holding items whose id or custom name matches |
| `chunksee <world> text <text> [dimension]` | Signs and books whose text matches |
| `chunksee <world> portals` | Nether portals and where each one leads, flagging one-way links |
| `chunksee <world> time [dimension]` | Chunks where players spent the most time (`InhabitedTime`) |
| `chunksee <world> creatures [dimension]` | Named and tamed creatures with owners, then counts by kind |
| `chunksee <world> maps` | Maps made in the game: dimension, center, scale and whether anything is drawn |
| `chunksee <world> rules` | Game rules and their values |
| `chunksee <world> players` | Each player's name (from the game folder's `usercache.json`), last position, last death, respawn point, game mode, health, food, level, items, play time and advancements |

For example:

```bash
.build/release/chunksee "<world>" block 10 68 -2
```

```bash
.build/release/chunksee "<world>" scan minecraft:the_nether
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
