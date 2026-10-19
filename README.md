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

// A path for a watcher/cache, without opening or requiring the file. These are region coordinates.
let terrainURL = overworld.regionURL(x: -1, z: 2)
let poiURL = overworld.regionURL(.pointsOfInterest, x: -1, z: 2)
// regionURL(.entities, x:z:) addresses entity regions; region(_:x:z:) opens an existing region.

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

Heightmaps store the absolute Y of the first free block above the matching surface. The automatic
reader returns `nil` if stored length cannot uniquely determine width: for example, 11-bit and
12-bit maps both use 52 longs. Vanilla 128/256/384-block heights remain unambiguous. When the
actual dimension build height is known, pass it explicitly:

```swift
let tallSurface = chunk.heightmap("WORLD_SURFACE", height: 4000) // build height, not maximum Y
```

The explicit overload checks stored length and value range against that height. Missing/inconsistent
maps and overflowing Y values return `nil`. Callers without height context should use their normal
surface fallback rather than treat an ambiguous packing guess as a valid map. This changes the
availability of ambiguous maps in the existing overload; their previously guessed values could be
incorrect. It does not add pre-1.18 terrain decoding.

A `BlockState` whose `properties` is empty is in its default state. Since 26.3, the game no longer saves the properties of default states.

### Slime chunks

```swift
if let seed = try world.seed() {  // modern saved data or the older level.dat layout
    let slimeChunk = World.isSlimeChunk(x: -12, z: 27, seed: seed) // chunk coordinates, Int32
    print(slimeChunk)
}
```

The engine follows Java Edition’s seed mixing and random draw, verified against Minecraft 26.3.
Use the classification for low-altitude Overworld slime chunks; height and other spawning
conditions still apply, and swamps have a separate spawning rule.

### Iterate every chunk

```swift
var diamonds = 0
for (regionX, regionZ, _) in overworld.regionFiles() {
    try overworld.forEachChunk(regionX: regionX, regionZ: regionZ) { _, _, nbt in
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

`forEachChunk` visits decoded NBT one chunk at a time. Its `skipping` set omits unneeded keys;
`.entities` and `.pointsOfInterest` select the other region folders. Missing regions have no
visits and unreadable chunks are skipped. File-opening errors and errors from your callback
(including `CancellationError`) propagate immediately. The callback can retain values if needed;
the visitor does not build an array of raw chunks.

For combined scans, the same chunk NBT can feed the existing container, sign, spawner, structure
and terrain readers. `Chunk.inhabitedTime(in:)` also handles old `Level.InhabitedTime` metadata
without requiring a legacy terrain decode:

```swift
try overworld.forEachChunk(regionX: -1, regionZ: 0, skipping: Chunk.keysNotNeededForInhabitedTime) { x, z, nbt in
    print(x, z, Chunk.inhabitedTime(in: nbt) ?? 0)
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
    guard let nbt = try region.chunkNBT(localX: x, localZ: z, skipping: Chunk.keysNotNeededForStructures),
          let chunk = try? Chunk(nbt: nbt), chunk.isFullyGenerated else { continue }
    for start in chunk.structureStarts {
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

### Block coordinates

`BlockPosition` converts exact coordinates to the containing block, rounding negative fractions
down and returning nil for nonfinite or out-of-Int-range values. Entity-container reads and the
CLI use this same public rule. Callers with only X/Z can convert each available axis without
inventing a height:

```swift
let block = BlockPosition(x: -8.7, y: 63.9, z: -513.1) // x: -9, y: 63, z: -514
let x = BlockPosition.coordinate(containing: -8.7)     // -9
```

### Spawners

```swift
// Monster spawners and the mob each spawns (nil for an empty one); trial spawners aren't included.
for spawner in try overworld.contents(regionX: 0, regionZ: 0).spawners {
    print(spawner.mob ?? "empty", spawner.x, spawner.y, spawner.z)
}
```

### Signs and books

`TextComponent.plainText` removes legacy `§` formatting codes consistently from parsed
components, including item/container names, signs, map banners and written book pages. Spaces
and line breaks are preserved when components are joined. Unsigned writable-book pages remain
literal strings. Creature names retain their existing outer-whitespace trimming.

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

`PlayerInfo.shoulderPets` reads parrots stored in `ShoulderEntityLeft` and
`ShoulderEntityRight`, left first, through the same `Creature` reader and player
DataVersion. Saved owner, UUID, name, health and appearance are preserved. These
entity snapshots contain the position **before mounting**: locate a shoulder pet
with the player's current `position`, applying the player's dimension/Bukkit
restrictions. An unavailable player position does not discard its shoulder pets.
The dimension's entity-region reader does not include them; a client combines the
player and dimension records. Verified against the official 26.3 save/load and
shoulder-mount code. This additive API is unreleased; the app adoption waits for
an approved release.

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

`Villager.level` defaults to 1 (Novice) only when a `VillagerData` compound omits `level`,
matching the vanilla 26.3 codec. Explicit numeric values are preserved; malformed levels stay
unavailable. A trader with offers but no `VillagerData` has no level. Previously cached creatures
still decode as saved, so rescan them to obtain this corrected default.

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

To classify the return as well, use `portal.roundTrip(into: netherPortals,
returningThrough: overworldPortals)`. It returns `.twoWay(target:block:)`,
`.oneWay(target:block:returning:)`, or `.wouldCreateNewPortal(destination:)`.
The one-way result includes whether the default return goes to another existing portal or
would create a new one. Unsupported source dimensions return `nil`.

Supply complete lists from both dimensions. These are predictions using each portal's default
bottom-center entry (or the specified outward `entering:` block); the return does not use the
outward arrival block. Entering elsewhere or chunks the game cannot load can change the trip.
The CLI `portals` command uses this shared classification and flags both one-way outcomes.

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

Modern world spawn, player death and player respawn share the `{dimension, pos: [I; x, y, z]}`
reader. A partial/unsupported world-spawn record leaves **both** `spawnDimension` and
`spawnPosition` unavailable; arbitrary coordinates never acquire an assumed Overworld dimension.
Bare dimension strings use the `minecraft:` namespace, as player/map dimensions already do;
custom qualified IDs stay intact. The reader does not validate world membership or identifier
syntax. Legacy world-spawn XYZ still means Overworld, and the existing legacy player respawn
fallback remains.

Player maximum health uses the same saved attribute arithmetic as creatures, including permanent
Health Boost in modern and legacy saves. It is not reconstructed from the effect list. Equipped-item
modifiers are added separately. Only the selected hotbar item (or explicit saved
main hand) contributes main-hand modifiers; slot groups and duplicate modifier IDs are honored.
The omitted vanilla player base is supplied only for verified 26.3/data-version-5023 saves.
Unknown defaults, modifier operations or unsupported effect/item/active-enchantment defaults leave
the maximum nil. The same vanilla-enchantment override limitation described for creatures applies.
Active effects read modern names and legacy numeric IDs, omitting expired/malformed entries
and queued `hidden_effect` values. They describe the save and do not count down in real time.
Amplifiers follow 26.3's `UNSIGNED_BYTE` codec: integral tags retain their low eight bits;
floating tags first narrow to Java's signed-int range (truncate toward zero, NaN to zero,
overflow/infinity to the corresponding endpoint), then retain their low eight bits. Thus edited
int `-1` means level 256, short `256` means level 1, and int `300` means level 45. Nonnumeric
amplifiers remain unavailable; a missing amplifier is level 1. Duration parsing is unchanged.

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

`MapItem.banners` reads both the three-int `pos` array used by 26.3 and the older
coordinate compound. Incomplete positions are skipped. Color and name remain the saved optional
values: current maps omit the default white color and an absent custom name. The array shape and
defaults were checked against the official 26.3 `MapBanner`/`BlockPos` codecs and a game-written map;
the version that changed the position shape has not been established.

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

Creature and player coordinates name the containing block (negative fractions round down).
Edited or malformed positions that cannot be represented are printed as `unknown position`;
the creature/player remains in the list. Creature listing scans entity region files even when
there is no corresponding terrain file.

The structures command lists starts in fully generated chunks and uses the containing block of
each inclusive bounding box's center. It keeps unknown placement for piece types without a
verified placement flag, following `StructureStart`.

Both item and text searches include inventory, equipment (including offhand books) and ender
chests, plus containers from terrain and entity region files. Overlapping terrain/entity regions
are read once per search, and an entity region does not need a matching terrain file.

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

Entity containers use the containing block of their saved `Pos`, rounding negative fractions down.
A missing, nonnumeric, nonfinite or out-of-range coordinate makes that container unavailable;
other readable containers in the same region are still returned.

## Testing

```bash
swift test
```

The tests use synthetic worlds and region files, so you don't need any Minecraft data to run them.

## License

MIT. See [LICENSE](LICENSE).

### Typed save values (unreleased)

`BlockPosition` retains exact whole integers through `init(blockX:blockY:blockZ:)`; its existing
failable Double initializer floors exact entity coordinates and rejects unrepresentable values.
`block.chunk` and `block.region` identify the containing chunk/region even for negative values.
`ChunkPosition.blockOrigin` and `RegionPosition.blockOrigin` return X/Z columns only, with no
invented height, and return nil on overflow. Dimension has typed `chunk(at:)`, `block(at:)` and
`regionURL(_:at:)` overloads; its older integer APIs remain available.

`Identifier` validates namespace/path characters and applies the default `minecraft` namespace.
Its Codable representation is the qualified string. Syntax matches the official 26.3 codec,
including empty paths; this does not imply that an identifier exists or is safe as a file path.
Malformed saved dimension/effect/enchantment IDs are now unavailable instead of being accepted
as arbitrary strings. `SaveVersion` names verified release numbers and format boundaries;
`DataVersion` remains an alias for source compatibility. Raw NBT, region and compression APIs
remain public. These additions await a separately approved minor release.
