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

The ChunkseeKit reader is read-only apart from the NBT writer, and it never modifies world files.

## Requirements

- Swift 6.4 or later (Xcode 27)
- macOS 27 or later
- zlib (included with macOS)

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fahlman/ChunkseeKit.git", .upToNextMinor(from: "0.40.0")),
],
targets: [
    .target(name: "MyApp", dependencies: ["ChunkseeKit"]),
]
```

## v0.40.0

`World.dimensionSettings()` exposes independently available dimension types and noise-generation
bounds through `DimensionSettings` and `NoiseGenerationSettings`. They share the saved mapping
and resource priorities with `dimensionTypes()`. The type-only query does not read generator
resources. Unknown definitions stay unavailable, and empty noise heights remain valid.
`surfaceRuleRange(in:)` follows verified 26.3 surface-rule anchors; it does not locate a physical roof.

Enabled ordinary ZIP data packs now use the same resolver as folders. Requested resources use
bounded raw deflate and CRC checks through the existing public system zlib. No files are extracted;
malformed or unsupported archives remain unavailable rather than permit an incorrect fallback.

`Chunk.ColumnStart`, `ColumnRun` and `forEachColumnRun(from:_:)` let callers use the shared surface
rule or an explicit Y and resolve their result during one downward traversal. Uniform sections
produce spans; each reached nonuniform section is unpacked once. Missing sections remain gaps,
and each column can stop independently. Existing surface queries share this traversal.

These are additive APIs, with no serialized shape or existing surface-meaning changes.
RegionFacts interpretation remains version 6. App colors, water shading, roof-view policy and
performance validation remain separate adoption work on fahlman/ChunkseeKit#51. This release
adds no legacy terrain support, cave-biome inference or world writes.

## v0.39.0

`Chunk.surfaceY(x:z:height:)` and `surfaceHeights(height:)` expose the highest non-air block
in one or all 256 columns. They share the WORLD_SURFACE heightmap and actual-block fallback
used by region biome sampling. Missing heightmaps no longer make a section top or unused
palette entry count as a surface. Empty columns stay unavailable; colors and roof hiding
remain front-end choices.

`Villager.isUnemployed` interprets the explicit unemployed profession through the shared
identifier rules, retaining unknown values, nitwits, custom professions and raw saved data.

Block-air classification, the CLI's air-section filter and empty-item reading recognize valid
default-namespace spellings. Foreign namespaces remain distinct. The CLI's structures command
also uses the library's shared chunk visitor.

These are additive APIs. RegionFacts interpretation version 6 invalidates earlier cached surface
samples and air-item reads; rebuild old facts caches. No serialized shape changes or new legacy
terrain support. Chunksee adoption and the remaining shared-reader work are tracked in
fahlman/ChunkseeKit#51.

## v0.38.0

`PlayerStatistics.unit(of:in:)` adds the saved units for known vanilla general statistics:
ticks, centimeters and tenths of a damage point. Counts and unknown units remain raw numbers;
front ends own names, rounding and localized formatting. Time and distance retain the supported
legacy IDs; damage scaling is verified only for 26.3 (data version 5023).

The `distances` convenience projection now uses that same lookup instead of guessing from an
arbitrary `_one_cm` suffix. Unknown or custom IDs remain in `values`, but are no longer included
as distances. This additive API and classification correction do not change region-cache
interpretation or the existing raw statistics. Chunksee adoption is tracked in fahlman/Chunksee#298.

## Shared indexing (v0.37.0)

`ChunkseeIndex` is a separate library product in this package, depending on the core reader.
Add `.product(name: "ChunkseeIndex", package: "ChunkseeKit")` to the consuming target's dependencies.
Its first API, `StoredItemTotal.totals(in:)`, aggregates quantities and outer-container counts
by saved item ID. It includes nested box/bundle contents, keeps differently named stacks of the
same ID together, and never predicts unopened loot. Results are ordered by ID; clients supply
display names and their preferred display order. For example:

```swift
import ChunkseeIndex

let totals = StoredItemTotal.totals(in: containers)  // [ItemContainer] from the core reader
for item in totals { print(item.id, item.count, item.containers) }
```

This product was introduced in v0.37.0 and Chunksee uses its storage totals.

**v0.42.0:** `BiomeArea.connected(in:)` groups a dictionary of chunk positions and biome IDs
into edge-connected areas. Every area is kept, including single chunks; corners do not connect.
Each area supplies its members, exposed chunk sides and a representative member nearest its
mean position, with ties ordered by X then Z. Chunks whose block origins cannot be represented
are omitted. Clients select surface/cave membership and supply paths, colors and names. Chunksee's
adoption is tracked on fahlman/Chunksee#383; its existing grouping rule is the source of this API.

**v0.43.0:** `PointIndex<Element>` stores an immutable snapshot and indexes its exact X/Z
positions by region. `candidates(minX:maxX:minZ:maxZ:)` returns broad candidates in input order,
including entries without a usable bucket; clients apply their precise geometry and visibility.
Unusable query bounds return the full snapshot. Large sparse queries visit occupied buckets
instead of enumerating empty space. The app's existing marker lookup is the source of this API;
its adoption is tracked on fahlman/Chunksee#384. No file access, scheduling or cache is introduced.

**v0.44.0:** `SearchQuery` interprets the existing app query grammar and matches searchable
text. Recognized `structure:`, `place:`, `creature:`, `pet:`, `villager:`, `trade:`, `biome:` and
`block:` prefixes select a filter. Other colons remain literal search text. Every whitespace-separated
word must occur, ignoring case, in any order; an empty filter can list all of its category.
Clients choose the category's records and provide names, searchable text and result presentation.
The `phrase:` initializer preserves the CLI's existing `find`/`text` grammar: one literal phrase,
including its spaces and colons, without parsing filters. Both use the same substring matcher.
The CLI consumes this API; the app adopted it in fahlman/Chunksee#385.

```swift
let query = SearchQuery("pet: summer wolf")
if query.filter == .pet && query.matches("Summer minecraft:wolf") { /* matching pet */ }
let phrase = SearchQuery(phrase: "red and blue") // CLI-compatible contiguous phrase
```

**v0.45.0:** `NotableBlock` owns the existing block-search catalog and its exact saved IDs.
`NotableBlock.Deposit.grouped(_:)` combines the core reader's per-ID deposits into those groups,
including ordinary/deepslate ore variants, and returns counts and enclosing section-height ranges.
Results are ordered by the group's raw value; unknown IDs and blocks outside this catalog are
omitted. The range is not an exact ore position. The core scan still accepts any chosen block IDs;
this catalog does not expand the app's existing scan or search scope. Names and display wording
remain in the app; adoption is tracked on fahlman/Chunksee#386.

**v0.46.0:** `RegionIndex` retains compact search inputs from `RegionFacts`, discarding the large
terrain grids. `DimensionIndex` combines retained regions, storage totals, portals, biome areas and
notable deposits. Its `updating(available:selected:replacements:)` returns a new snapshot: omitted
available replacements retain the last good data, selected missing regions are removed, and a nil
selection reconciles the whole dimension. A partial selection leaves other regions untouched after
the first completed pass. Call `regionsToRead(available:selected:)` to schedule the reads: the first
pass always reads all available regions, even after a partial notification. `updating` uses that same
read-set rule. A completed empty or failed pass is distinct from a never-read index.
Only replacements with matching dimension/cave policy and selected available coordinates are accepted.

Callers explicitly supply the cave-biome IDs; the library does not define a new cave-membership rule.
`CreatureEntry` keeps villagers, owned pets and named creatures with supported locations, using that
category precedence and the existing stable UUID (or exact saved-position fallback) identity.
The core `BlockPosition.mapCoordinates(x:y:z:)` supplies the shared map bounds: floored X/Z must fit
Int32 and a supplied Y must fit Int; unknown Y stays nil. It does not impose the game world border.
Client wording, native geometry, scheduling, cancellation
and publication remain outside the index. These values introduce no persisted cache format.

```swift
let caves: Set<String> = ["minecraft:lush_caves"] // example client policy
let region = ChunkseeIndex.RegionIndex(facts, caveBiomeIDs: caves)
let previous = ChunkseeIndex.DimensionIndex(dimension: facts.dimension, caveBiomeIDs: caves)
let current = previous.updating(available: [facts.region], selected: nil, replacements: [region])
```

**v0.47.0:** `WorldIndex<Dimension>` holds the world's dimension catalog and supplies typed
`Placed<Value>` records through `all(_:)`. Each record keeps its dimension ID, including when
different dimensions contain identical values. Member order is preserved; dimension order is
unspecified, as in the app's original SearchIndex. Replacing one dictionary entry leaves the other
dimensions and earlier value snapshots intact. The payload can be `DimensionIndex` or a client's
native projection of it, without adding UI dependencies to the shared module. There is no second
catalog, file access, task, or persistence owner.

```swift
let worldIndex = WorldIndex(dimensions: [current.dimension: current])
for entry in worldIndex.all(\.containers) {
    print(entry.dimension, entry.value.kind)
}
```

**v0.47.0:** `ItemTotals` adds up matching stacks, including nested box and bundle contents.
Clients supply the match predicate and grouping key, so the app can match localized item labels
while the CLI keeps its saved-ID/custom-name search and alphabetical output. `quantities` holds
each group's count; `count` is their total. A matching zero-count stack still makes `isEmpty` false.
The CLI's `find` command and storage totals use this owner; app adoption follows its release.
Storage still counts each outer container once for each saved item ID it contains.

```swift
let matches = ItemTotals(in: items, matching: { query.matches($0.id) }, groupingBy: \.id)
for (id, quantity) in matches.quantities { print(id, quantity) }
```

**Unreleased:** Search input selection also lives in this module. `PlayerInfo.searchableInventory`
combines inventory and saved equipment, leaving the ender chest separate and avoiding an extra
inferred main-hand copy. `BookContent.searchText` joins saved title, author and pages with newlines;
`Sign.searchLines` keeps both sides without empty lines, preserving whitespace for phrase queries.
The CLI uses these inputs; clients still supply localized names and display formatting.

`SearchQuery.Filter.includes(_:)` supplies creature-category membership, including villagers for
trade searches. `WorldIndex.richestDeposits(matching:limit:in:)` selects the strongest matching
deposits across dimensions from richest-first arrays such as `DimensionIndex.blocks`. It keeps
each result's dimension and height bounds; equal-count order remains unspecified. Clients choose
the result limit, match localized block names to kinds, and convert selected chunks to map pins.

Typed search results, remaining CLI adoption and app adoption are tracked in fahlman/Chunksee#214.
Core decoding and low-level file APIs stay in ChunkseeKit.

## Synthetic test data (v0.35.0)

`ChunkseeKitTestSupport` is a separate library product available starting in v0.35.0.
Add it to a test target with
`.product(name: "ChunkseeKitTestSupport", package: "ChunkseeKit")`.
The reader and CLI do not depend on this product. This release adds no breaking reader APIs
and does not change saved-data interpretation or cache versions.

Its public `Fixtures` builders are the same ones used by the library and CLI tests:
packed indices, sections, chunks, region files, UUID int arrays and compressed NBT files.
They accept explicit NBT so tests can describe unusual or incomplete saves. For example:

```swift
import Foundation
import ChunkseeKit
import ChunkseeKitTestSupport

let directory = try Fixtures.tempDirectory()
defer { try? FileManager.default.removeItem(at: directory) }
let section = Fixtures.section(y: 0, palette: [.string("minecraft:stone")])
let chunk = Fixtures.chunk(x: 0, z: 0, dataVersion: SaveVersion.java26_3, sections: [section])
let bytes = try Fixtures.region([.init(localX: 0, localZ: 0, nbt: chunk)])
try Fixtures.write(bytes, to: directory.appendingPathComponent("r.0.0.mca"))
```

Region coordinates passed to `RegionChunk` are local, from 0 through 31. It defaults to zlib
compression and a fixed timestamp. `chunk` retains its existing `DataVersion.perBlockBiomes`
default; pass a version explicitly for version-specific fixtures. The helpers expect valid
packing widths and indices, and write only to caller-supplied paths; tests own their temporary
directories and cleanup. The CLI executable-location helper remains private to the Kit tests.

## Migrating to v0.37.0

`PlayerInfo.nbt`, `LevelInfo.nbt`, `Chunk.nbt` and `ItemStack.components` are no longer public.
Use each model's typed properties for the fields it models. Tests that construct saves should retain their original
NBT input for file writes rather than retrieving it from a typed model. The public
`PlayerInfo(uuid:nbt:lastSaved:)`, `Chunk(nbt:)` and `ItemStack` initializers still accept that input.
Item enchantments, durability and other typed properties keep their existing behavior; Codable
continues preserving the saved item components.
Raw-file tools can continue using the public NBT, region-file and compression APIs directly.

`Chunk.blockEntities` and `blockEntity(x:y:z:)` now return `BlockEntity` values with optional
`id` and absolute `position`, rather than NBT. Read `entity.id` instead of `entity["id"]?.string`.
The list retains saved order and incomplete entries; coordinate lookup retains its first-match
and chunk-local X/Z behavior. Use the existing container, sign and spawner readers for their
typed details, or read NBT through `RegionFile` for fields without a typed reader.

v0.37.0 includes these breaking API changes and the additive ChunkseeIndex product.
Saved-data interpretation and cache versions are unchanged.

## Migrating to v0.31.0

v0.31.0 removes `PlayerInfo.isFromBukkitServer`, `bukkitWorldName`
and `locationsBelongToWorld`. Player locations now follow vanilla dimension and
coordinate rules regardless of unrelated extra fields. Consumers should use
`position`, `lastDeath` and `respawn` and check coordinate availability. Unknown
dimension values remain unavailable; vanilla legacy numeric dimensions and datapack
dimensions remain supported. `LevelInfo.wasModded` and `serverBrands` remain because
vanilla writes them. These removals are a breaking change from v0.30.0.

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

### Saved world clocks

`try world.clockTimes()` returns whole saved ticks by normalized clock ID, including custom
clocks. It reads the existing namespaced/flat saved-data layouts and preserves signed 64-bit
values on supported Macs. `dayTime()` uses this same owner for the Overworld. Legacy `DayTime`
fills a missing valid Overworld entry; ambiguous normalized IDs are omitted even when a legacy
value exists. Other missing/malformed entries are omitted, and file read errors propagate.
This snapshot does not evaluate timeline periods, fractional ticks, rates or dimension links,
and does not validate clock registry membership. This additive API is unreleased; the app's
time-of-day lighting is tracked separately on fahlman/Chunksee#357.

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
    let chest = chunk.blockEntity(x: 3, y: 64, z: 7)     // typed identity and position
    print(chest?.id ?? "no saved ID")
}

let entities = try overworld.entities(chunkX: 0, chunkZ: -1)
print(entities.compactMap { $0["id"]?.string })
```

`Chunk.biome` reads the saved cell directly. For the game's irregular biome boundaries, the
additive, unreleased `BiomeSampler(seed:)` takes the raw value from `World.seed()` and
`cellOrigin(at: BlockPosition)` selects the four-block cell used by Minecraft 26.3. Construct the
sampler once per world. Its result is a block position: use its `chunk` to choose the source chunk,
then pass its local X/Z and absolute Y to `Chunk.biome`. The source may be in a neighboring chunk
or section. If that data is missing, the caller chooses how to handle the unavailable biome.
Coordinates outside signed 32-bit input are unavailable; results retain the full cell origin
without narrowing. The `cellOrigin(at:in:)` overload takes a validated `DimensionType` and clamps
the selected cell to its build-height limits, following the game's source-chunk lookup. The
unclamped overload remains available; neither fills a missing interior section or neighbor.
The sampler performs no file reads or color blending and
does not apply to per-block biome palettes. Seed hashing uses Apple's CryptoKit; no external
package dependency or stored-format change is introduced.

`Chunk.biomeSnapshot` is an additive, unreleased immutable view of only the decoded biome
palettes and section heights. Retain it when neighboring terrain needs these values after the
full chunk is released. Its `biome(x:y:z:)` has the same coordinate and missing-data rules as
`Chunk.biome`; `hasPerBlockBiomes(atBlockY:)` reports the decoded section's layout, or nil when
its biome palette is absent. Uniform palettes preserve the existing reader's cell layout because
no packed data distinguishes their resolution. Full chunks and snapshots share their lookup
and palette-addressing code. The snapshot performs no I/O or cell selection, retains no blocks,
light or raw NBT, and adds no serialized format.

When only biomes are needed, pass `Chunk.keysNotNeededForBiomes` to
`RegionFile.chunkNBT(localX:localZ:skipping:)`, then construct a `Chunk` and keep its
`biomeSnapshot`. This opt-in profile also skips block palettes and heightmaps, avoiding their
decode and allocation. It uses the same biome reader, including missing data and per-block
layouts. Skipped block data is not validated; malformed biome palettes and missing required
chunk/section fields still fail. The existing terrain and light read profiles are unchanged.
This additive profile is unreleased, tracked on #128; app adoption and measured benefit follow.

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

For batched readers, `ChunkSection.blockIndex(x:y:z:)` addresses the array returned by
`blockStates.allPaletteIndices()` using the same order as block and light lookups. It wraps each
coordinate to the section's 0–15 range, including negative coordinates. This additive helper is
available starting in v0.36.0. This release has no breaking APIs, reader behavior changes or
cache-version changes.

### Dimension build limits (v0.33.0)

`World.dimensionTypes()` reads each saved dimension's type from modern world-generation data
or the older inline `WorldGenSettings`. It resolves inline definitions and references in enabled
folder data packs, with later packs taking priority. The four vanilla definitions are verified
for 26.3 / data version 5023. A dimension can use a different type from its own ID; neither its
folder name nor its occupied chunk sections determine the result.

```swift
if let type = try world.dimensionTypes()["minecraft:the_nether"] {
    print(type.buildRange)     // 0...255 for the verified vanilla Nether type
    print(type.logicalHeight) // 128, distinct from its 256-block build height
    print(type.hasCeiling)     // true; this does not identify the generated roof's Y
}
```

Missing, malformed and unresolved types are omitted. Enabled folder and ZIP packs share the same
priority. ZIP reading validates the complete central directory and matching local headers without
extracting files. It supports ordinary stored/deflated entries with UTF-8 names, using public
system zlib for raw deflate and CRC checks. Encrypted, ZIP64, multipart or unsupported compression,
duplicate names, overlapping entries and malformed records remain unavailable. Only requested
JSON resources are decompressed, with exact-size checks and a 16 MiB limit per resource.
The unreleased file-reader update (#156) also bounds compressed entry reads to 32 MiB.
A malformed present override never permits a lower definition to take over.
ZIP support is available starting in v0.40.0. Built-in experimental packs, pack overlays and
resource filters are not resolved yet: an unsupported higher-priority pack
prevents guessing a lower definition, including vanilla. Vanilla defaults are unavailable for
unverified save versions. Explicit definitions must have valid aligned bounds and logical height;
file lookup rejects paths or symlinks escaping the pack. File-read errors propagate. This API
reads metadata only, has no cache and never writes a world. It does not change terrain decoding,
`RegionFacts`, or the app's height controls until separate app adoption.

The resource reader follows [PKWARE's ZIP format specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
(6.3.10, sections 4.3–4.4). It uses the existing `CZlib` module; no new library, private SDK
declarations, archive-writing API or external package is added.


`World.dimensionSettings()` is the companion query when both the type and generator context
are needed. Each value has independently optional `type` and `noiseGeneration` fields. Noise
settings resolve through the same saved mapping and enabled-pack rules; they are available only
for a saved `minecraft:noise` generator. The seven vanilla noise definitions are verified for
26.3, and inline/custom bounds are validated without assuming a complete game registry.
`dimensionTypes()` remains a type-only read and never opens generator resources.

The additive `dimensionTypes(assets:)` and `dimensionSettings(assets:)` overloads can read vanilla
definitions from a matching supplied `GameAssets` jar. Enabled data-pack priority is unchanged.
A matching jar is authoritative: a missing or malformed definition does not use the built-in
fallback. Without a matching jar, the original verified build/spawn-light fallback remains, with
no time/base-lighting metadata or clock/timeline table.

For readable 26.3 definitions, `DimensionType.time` exposes `hasFixedTime`, `hasSkylight`,
`defaultClock` and `timelines`. References are normalized through `Identifier`; timelines preserve
either a tag or an ordered list (including a single-reference shorthand). As the verified codec
specifies, an absent or JSON-null fixed-time field means false, an absent or null clock means no
default clock, and absent or null timelines mean an empty list. A missing skylight flag, malformed time field or unverified
version leaves the entire time value nil while independently valid build limits remain readable.
This metadata query does not expand timeline tags, validate clock/timeline registry membership,
evaluate lighting or simulate elapsed time. The savedSkyLighting query below resolves its lighting projection. These unreleased APIs are the metadata prerequisite for
fahlman/Chunksee#357, tracked in fahlman/ChunkseeKit#175.

`GameAssets.lightingTimeline(_:)` reads a supplied 26.3/5023 jar's five lighting tracks:
sun/moon angle, sky-light factor/color and moon phase. The immutable `LightingTimeline` retains
its own `clockID` and optional `periodTicks`. Pass that clock's saved whole ticks and an explicit
`SkyLighting` base to `applying(at:to:)`; absent tracks preserve the base. Angles use degrees and
RGB channels retain float precision. The result is an intermediate attribute layer, without
final range clamping, weather, spatial effects or rendered brightness. Nonfinite input/results
remain unavailable. The dimension base comes from `DimensionType.baseSkyLighting` below;
enabled-pack/tag resolution is supplied by savedSkyLighting below. App drawing remains separate.

The shared keyframe sampler preserves ordered duplicate-tick jumps, negative-time wrapping,
constant endpoints and the game's Float arithmetic. Supported easing is linear, constant or
cubic-Bezier; other curves stay unavailable. Scalar modifiers are override/add/subtract/multiply/
minimum/maximum, RGB modifiers are override/add/subtract/multiply, and moon phase uses override.
Other relevant modifiers are unavailable, not silently approximated. Color add/subtract apply
the game's one-sided channel limits; override/multiply do not quantize or clamp channels.
Sky-light-factor override keyframes require 0...1, while other modifiers may produce intermediate
values outside that range. Moon phases step according to the eased segment's progress.

The reader bounds JSON to 16 MiB, track entries to 256, relevant keyframes to 4,096, and baked
segment endpoints/lengths to Int32. Unsupported/malformed relevant data makes the whole timeline
unavailable. Unrelated tracks and time markers are not interpreted or validated, so this is not
a complete timeline-registry validator. Numeric JSON remains strict as in the other asset readers.
These additive APIs are unreleased on fahlman/ChunkseeKit#177 for fahlman/Chunksee#357. They read
no chunks, write no worlds, simulate no clocks and introduce no mutable cache or dependency.

`DimensionType.baseSkyLighting` supplies the static layer for readable 26.3 definitions. It applies
that definition's `attributes` entries to the registered defaults: sun/moon angle 0 degrees,
sky-light factor 1, white sky-light color and full moon. Absent or JSON-null `attributes` uses
those defaults. Both shorthand values and expanded `modifier`/`argument` entries use the same
value codecs and simple modifier arithmetic as timelines. The sky-light-factor override must
be 0...1; other modifiers can produce values outside that range until later layer composition.
No dimension name, fixed-time flag or skylight flag substitutes a lighting value.

Inline NBT, enabled folder/ZIP overrides and matching-jar definitions share the existing type
reader and resource priority. Unsupported/malformed relevant entries, ambiguous aliases or more
than 256 attribute entries leave the whole base nil without discarding independently valid build
or time metadata. Other attributes are ignored, so this is not full registry validation. Other
save versions and the no-jar build-limit fallback provide no base. No weather, biome/spatial
layers, timeline application, final range clamping or rendering happens in this query. This
additive API is unreleased on fahlman/ChunkseeKit#179 for fahlman/Chunksee#357.

`World.savedSkyLighting(assets:)` composes each readable dimension's base and timeline layers
using each timeline's own named saved clock. It uses the shared type, clock, resource and sampler
readers rather than an app-owned vanilla table. Fixed-time flags do not bypass tracks, and the
dimension's default clock never substitutes for a track's clock. Empty lighting tracks require
no unrelated clock; dimensions with no timelines need no timeline-resource or clock read.

Enabled folder/ZIP packs and a matching supplied 26.3 jar share normal definition priority.
Timeline tags combine resource stacks from low to high priority: `replace` clears earlier entries,
nested tags preserve first occurrence, and missing optional references are skipped. Missing
required members invalidate their tag; a direct list retains duplicate timelines. Malformed or
cyclic selections, unreadable/unknown resources, unsupported relevant tracks and missing named
clocks omit the affected dimension. Invalid optional selections remain unavailable rather than
being treated as absent. This deliberately does not reproduce the game's partial recovery from
invalid tag files or hash-order-dependent cyclic tags. File-read errors and cancellation propagate.

This query returns intermediate dimension/timeline attributes; it does not simulate time, apply
weather or biome/spatial effects, perform final range clamping or draw pixels. It reads no chunks
and writes no worlds. Resources and clock snapshots are shared within the call, with no persistent
mutable cache. Bounds are 64 enabled packs, 64 tag levels, 4,096 entries/members per tag/direct list,
16 MiB per resource, 64 MiB of selected payloads and 65,536 reference/member steps per query.
These additive APIs are unreleased on fahlman/ChunkseeKit#181; app lighting remains on
fahlman/Chunksee#357.

The unreleased spawn-light extension adds `monsterSpawnBlockLightLimit` (0...15) and
`monsterSpawnLightLevel` (an inclusive range) to each dimension type. The latter reports the
bounds of constant or uniform random light thresholds; unsupported distributions remain nil.
These are independent optional facts: missing or invalid light fields leave valid build limits
intact and never acquire vanilla guesses. The saved type reference and enabled data-pack priority
apply, even when the dimension folder has a familiar vanilla name. They do not establish whether
a monster can spawn: the game also checks surfaces, available space, biome, time and other rules.

`Chunk.isLightOn` reports whether the chunk marks its saved lighting as valid. The new
`chunk.blockLight(x:y:z:)` and `chunk.skyLight(x:y:z:)` accessors take chunk-local X/Z and absolute Y,
returning a saved 0...15 value only when the flag is true and the section has a complete light
array. Missing, malformed or skipped arrays return nil, not zero. Existing section-level accessors
still expose raw stored values. `Chunk.keysNotNeededForTerrain` continues to skip both the flag
and light arrays, so ordinary terrain reads do no extra lighting work. No propagation is simulated.

`Chunk.resolvedBlockLight(x:y:z:)` additionally resolves an omitted block-light layer to zero
for valid 26.3 saves. The game's serializer omits null or empty default-zero layers, and its
block-light storage reads an absent layer as zero. A malformed **present** tag is not an omission.
Stale lighting, unverified-version omissions and invalid query coordinates stay unknown; raw
stored-array accessors are unchanged. Read all light fields or use the terrain-plus-light profile:
a caller that selectively skips `BlockLight` but retains `isLightOn` has discarded the distinction.
No sky-light fallback or light propagation is added. The monster-light convenience query uses
this shared interpretation. This additive API is tracked on fahlman/ChunkseeKit#187.

`World.nightMonsterLighting(assets:)` supplies a clear-night planning snapshot for each supported
26.3 dimension. It reads the separate gameplay sky-light attribute and applies the dimension's
selected timelines at their first declared `minecraft:midnight`, then uses the game's final
clamping and integer sky darkening. All relevant tracks must share that midnight's clock and period;
missing or conflicting markers and other relevant clocks remain unavailable. Static sky levels
need no marker, and dimensions without skylight need no sky projection. Saved clock time,
weather, later nights and a complete game registry are not simulated. Existing visual lighting
remains independently readable.

Each `MonsterSpawnLight` answers whether valid saved channels **can pass the ordinary monster
light check**. This is not a probability or a guarantee that a mob can spawn. The separate block
ceiling and the raw-brightness threshold both apply; a ceiling of 15 does not disable the latter.
`canPass(in:x:y:z:)` takes chunk-local X/Z and absolute Y, preserves unknown/stale light, and
requires a saved sky array only when that dimension has skylight and block light has not
already ruled out a pass. Missing sky light never makes a known excessive block value unknown.
It includes the game's horizontal brightness bounds. To opt in when decoding, use
`Chunk.keysNotNeededForTerrainAndLight`; the original terrain read profile is unchanged. This additive prerequisite is tracked on
fahlman/ChunkseeKit#185; the app overlay and its checks remain on fahlman/Chunksee#86.

`NoiseGenerationSettings.seaLevel` is the saved `sea_level`, independently optional when missing
or not a readable signed 32-bit integer. It uses the same inline definitions and enabled folder/ZIP
packs as the bounds. An absent or malformed value does not discard readable bounds or fall back to
another pack's sea level. Numeric decoding follows the bounds reader's strict checks rather than
the game's permissive `Number.intValue` conversion. It is not clamped to the generation/build range:
the verified 26.3 floating-islands preset has sea level −64 with a `0..<256` generation range. This is a generation
setting, not a measurement of water in saved chunks; display scales and colours belong to the app.

`NoiseGenerationSettings.range` is the saved noise range, including a valid empty range.
`surfaceRuleRange(in:)` reproduces 26.3's `WorldGenerationContext` range for vertical anchors:
it starts at the larger minimum Y and uses the smaller height. This differs from intersecting
range endpoints. For the vanilla Nether, build bounds are `0...255` but the surface-rule range
is `0..<128`. Neither this range nor `hasCeiling` proves where a physical roof block exists;
view selection and colors remain the caller's policy. These companion APIs are available starting
in v0.40.0; app adoption is tracked separately on fahlman/ChunkseeKit#51.


### Region facts (v0.30.0)

`Dimension.scan(region:options:)` reads the terrain, entities and POIs for one region in a single
pass. Each chunk payload is decoded once. The result contains containers, signs, spawners,
placed structure starts, creatures, POIs, inhabited time and format counts. Its typed terrain
chunks include decoded heightmaps, actually used biome IDs (including cave biomes), a sampled
biome, and block counts with the enclosing section-height ranges. It does not choose UI groups,
combine biome areas, name ores, or run search queries.

```swift
let region = RegionPosition(x: -1, z: 2)
let options = RegionScanOptions(
    blockIDs: ["minecraft:diamond_ore", "minecraft:deepslate_diamond_ore"],
    biomeSampleY: overworld.id == "minecraft:the_nether" ? 64 : nil
)
let facts = try overworld.scan(region: region, options: options)
print(facts.containers.count, facts.creatures.count, facts.formats.legacy)
let cacheData = try JSONEncoder().encode(facts)
let restored = try JSONDecoder().decode(RegionFacts.self, from: cacheData)
```

A nil block-ID set counts all IDs; an empty set skips counting. Nil biome-sampling Y uses the
middle column's surface from the shared reader below. Supply a Y for a different sample (for example,
64 under the Nether roof). Optional `height` is the dimension's actual build height, for decoding
ambiguous heightmaps; it is never inferred from occupied sections. The used-biome list excludes
unused palette entries. Partial-generation chunks keep metadata/heightmaps but contribute no
structure, sampled-biome, used-biome or deposit search facts. Legacy chunks contribute inhabited
time and format counts without enabling legacy terrain decoding.

The additive `RegionFacts.paletteBlockIDs` catalog retains declared block IDs from fully generated
chunks' saved palettes, including unused entries and modded names. It is collected during the same
section walk, independent of `RegionScanOptions.blockIDs`, without another chunk decode or block
traversal. It names available palette choices; it does not assert that every name occupies a block.
`RegionIndex.paletteBlockIDs` retains the compact regional set and `DimensionIndex.paletteBlockIDs`
unions the retained regions. Refresh, failed-read retention, replacement and deletion use the same
rules as the other dimension aggregates. Partial/legacy/unreadable chunks contribute no names.
RegionFacts interpretation version **7** rejects older archives, which lack this catalog. Consumers
must rebuild their scan caches when adopting it. This prerequisite for Chunksee #365 is unreleased;
block hiding, highlighting, labels and native controls remain app responsibilities.

Starting in v0.39.0, `Chunk.surfaceY(x:z:height:)` returns the highest non-air block's absolute Y in
one column. `Chunk.surfaceHeights(height:)` returns the same values for all 256 columns, indexed
by `z * 16 + x`, with each reached nonuniform section decoded once. Both use a decodable
`WORLD_SURFACE` heightmap (first-free-block Y minus one), otherwise the actual referenced blocks.
The optional build height disambiguates tall-world heightmaps. Empty columns and malformed
references stay unavailable; air variants are skipped, while plants and water count as surface.
`MOTION_BLOCKING` is not used because it describes a different set of blocks. Roof hiding,
water shading and cave-biome classification are separate from this reader.

Starting in v0.40.0, the additive `Chunk.forEachColumnRun(from:_:)` API visits saved blocks in all
256 columns in one downward traversal. Use `.surface(height: knownBuildHeight)` for the same
WORLD_SURFACE/actual-block starting rule, or `.height(y)` for an explicit cutaway. Uniform
sections produce a clipped inclusive Y range; other sections produce one block per run. The
run identifies its column, original section index and palette index, so clients can resolve
their own presentation once per palette entry instead of copying block names at every step.

```swift
chunk.forEachColumnRun(from: .surface()) { run in
    guard let palette = run.paletteIndex,
          let blocks = chunk.sections[run.sectionIndex].blockStates else { return false }
    print(run.column, run.y, blocks.palette[palette].id)
    return false // Finish this column; other columns continue independently.
}
```

Return true to continue below that run; throwing stops the whole traversal. Missing/light-only
sections stay gaps. Clients counting contiguous water, for example, must compare neighboring
run ranges rather than fill a gap. Saved empty surface columns and invalid build heights produce
no visits. Without a readable heightmap, air is skipped and an invalid reference stops that column
before a surface is established. After the starting surface (or from an explicit Y), air and
invalid palette references are reported so the caller can choose its policy. Each reached
nonuniform section is unpacked once. The existing single/batched surface fallback uses this
same traversal, with single-column queries reading only their requested column. No colors,
roof-hiding policy, cache format or region-fact interpretation changes are introduced here.

Region scans now use this surface owner instead of sampling a section's top when a heightmap
is absent. Air classification uses Identifier's default namespace, so `air` and `:air` are
equivalent to `minecraft:air`; foreign-namespace names are not treated as vanilla air. Raw block
IDs remain unchanged. Item reads use the same namespace rule for the empty `minecraft:air` item,
including nested contents; the CLI chunk listing uses the shared block-air classification.
RegionFacts interpretation version 6 invalidates older cached biome samples and empty-item
interpretations; rebuild them after adopting this change. Explicit sampling Y and the used-biome
list are unchanged.

Cache keys must include all three source-file fingerprints, the options,
`RegionFacts.interpretationVersion`, and the consumer's transform version. Kit must bump the
interpretation version whenever any fact's meaning changes. Decoding rejects other versions and
malformed grid sizes. `RegionFacts` owns the new persistence contract; existing model Codable
conformances remain source-compatible but are not independently versioned caches. No raw NBT is
exposed by the new facts. The lower-level NBT, region and compression APIs remain public.

Missing region files are empty. Unreadable individual chunks are counted and skipped, while
region-open errors and cancellation throw; callers must not cache a failed scan as an empty or
complete region. Scanning does no disk caching or background scheduling of its own. The API is
available starting in v0.30.0; app adoption is tracked separately in fahlman/Chunksee#212.

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

`ItemStack.itemModelID` identifies the item definition used for its picture. It reads the saved
`minecraft:item_model` reference with the shared Identifier codec; absent overrides use the item's
ID, the standard prototype default verified in 26.3. Removed or malformed components return nil,
so callers do not silently restore the ordinary picture. Pass the identifier to
`GameAssets.defaultItemModel(_:)` for a default illustration; missing or unsafe resources still
return nil there. This reference does not resolve registry/data-pack prototype changes or select
variants. It computes from retained components, so existing cached items need no new field or rescan.

For a saved stack, `ItemStack.itemModelSelection` adds its trim-material key and custom-model data.
Pass this hashable value to `GameAssets.itemModel(for:)` and use it as the model-cache key; stacks
with different trim materials can select different models. The **26.3 / 5023** trim selector reads
the saved `minecraft:trim.material` reference, or legacy `tag.Trim.material`. Missing/removed trim
uses the definition's fallback; removal/current values suppress legacy data. An inline material
holder has no registry key and also uses the fallback, matching the game's `Holder.unwrapKey`.
Malformed material/model values leave the selection unavailable. Only the material identity is
read: trim-pattern and tooltip fields do not choose an inventory picture, and this does not validate
the full trim codec or resolve its registry. Names, counts, trim patterns and independent dye/potion
tints do not change this model key; apply those tints separately using the original stack. These additive
selection APIs are unreleased for fahlman/Chunksee#390; no serialized field or rescan is added.

`ItemStack.customModelData` reads the saved floats, flags, strings and RGB colors used by custom
item pictures. Missing/removed components return known empty lists; malformed data returns nil
and leaves `itemModelSelection` unavailable. A present current value or removal suppresses legacy
`tag.CustomModelData`. Older numeric values become one Float, matching the game's migration.
The lists share a 4,096-entry bound, with at most 16 MiB of string bytes. RGB vectors use the
existing conservative color reader: nonfinite or out-of-range channels remain unavailable.
Java numeric conversion, mixed-list wrappers and array tags are shared with the NBT/color owners.
The hashable selection includes these data, including custom colors that become constant tints;
float identity preserves narrowed negative zero and canonicalizes NaNs, and strings keep their
exact Unicode spelling. This additive API is unreleased on #183 for fahlman/Chunksee#390.

`ItemStack.potDecorations` exposes decorated-pot sides (v0.67.0). It reads current
`pot_decorations` named item templates, earlier back/left/right/front lists and legacy
`BlockEntityTag.sherds`. Each side retains its item ID and default, removed, named or inline
`provides_pottery_pattern` selection. Missing/removed decorations are empty; malformed present
values are unavailable. Earlier lists are limited to four entries, with absent positions filled
by brick as in the official migration. Work is bounded to four sides and 16 MiB of identifier
strings. The computed facts use existing saved components; ItemStack's archive format is unchanged.

`ItemModelSelection` includes these sides, so changing a side or its pattern changes the model
cache key, while stack count/name and template count/tooltips do not. The verified **26.3 / 5023**
special-model path renders the neck, rim, caps and side faces through the existing shared cuboid,
UV, part-pose and item-transform code. The game's 23 sherd component defaults come from its code;
each pattern's asset comes from the supplied jar's `decorated_pot_pattern` registry. Explicit named
and inline patterns override defaults, and removed patterns stay blank. Unknown mod-item defaults,
unsafe/missing/malformed selected definitions and unsupported versions remain unavailable. This
is a static inventory model, without wobble animation or world writes. It adds no image decoder,
app renderer or bundled artwork. App adoption remains on fahlman/Chunksee#390 after release.

`ItemStack.bannerDesign` exposes the saved base dye and ordered banner patterns used by shield
and banner pictures (unreleased, #189). Missing or removed fields are known empty; malformed
fields return nil. A current component or removal suppresses its own legacy counterpart. The
reader retains named pattern holders and inline asset/translation-key holders without resolving
the world's registry. Older `BlockEntityTag.Base` and `Patterns` fields share the verified dye
identities and short-pattern migration; intermediate lowercase `patterns` is also supported.
Invalid legacy dye IDs stay unknown. Limits are 4,096 layers and 16 MiB of pattern string data;
the reader keeps every accepted layer rather than applying a renderer's layer limit.
`DyeColor` is the common saved-name/legacy-ID owner, also used by pet collars. This computed
reader changes no stored item or cache format. Picture selection and material resolution use
the shared model API below; pixel decoding/compositing and the app's adoption remain separate.

The unreleased #191 extension includes this design in `ItemModelSelection`. For the verified
26.3 shield model, `GameAssets.itemModel(for:)` resolves named patterns from the supplied jar's
`data/<namespace>/banner_pattern` JSON or uses saved inline assets. Its existing plate/handle
geometry carries one `AssetModel.Material`: the patterned base skin plus ordered `overlays`,
each with a texture ID and RGB multiplier. Clients composite the overlays over the base before
projecting that geometry. Plain shields and `defaultItemModel` keep their existing plain skin.
The first overlay uses the base dye (white when only patterns are saved), followed by at most
16 saved patterns, matching the game's drawing limit. The full saved list stays in `bannerDesign`.
Pattern JSON and overlays share the existing whole-item budget; missing, malformed or unsafe
definitions stay unavailable. This interprets the supplied jar, not resource-pack layering or
world registry overrides. Image decoding, compositing and cache-cost adoption remain app work
on fahlman/Chunksee#390. Consumers must handle material overlays before adopting patterned images.

The unreleased #197 extension resolves 26.3 banner special models through those same APIs.
The definition chooses the base dye and ground (default) or wall attachment; a stack's base-color
component does not override that dye. Only the cloth receives the dyed base and first sixteen
saved patterns. Its support/pole keeps the plain `entity/banner/banner_base` skin. The cloth retains the
game's fixed inventory pose (phase zero), while the definition supplies node and GUI transforms.
Existing cuboids, rotations and material overlays describe the whole banner; clients need no
banner-specific renderer. A transform that would shear the tilted cloth stays unavailable.
Unknown versions, malformed definitions and unresolved selected patterns retain the usual fallback.

`ItemStack.dyedColor` and `customPotionColor` expose explicit saved color overrides as optional
`UInt32` values in 0xRRGGBB form (unreleased, #145). They read current components and legacy tags;
the dye reader also accepts the older `rgb` wrapper and current three-channel vectors. Removed
or malformed-present components do not fall back to old tags. Numeric tags follow Java's integer
narrowing, including signed colors; vector channels use Float precision and floor(channel × 255).
Nonfinite/out-of-range channel vectors remain unavailable. These are computed from the retained
components, so existing cached ItemStacks gain them without a rescan or Codable change.

Absent colors remain nil. `customPotionColor` does not calculate the normal color of a potion's
effects; it is the explicit override only. Clients apply these values to the appropriate model
tint layers, leaving default colors and normal potion-effect resolution to their respective owners.

`ItemStack.potionColor(gameDataVersion:defaultColor:)` resolves the full potion tint (unreleased,
#149). Pass the matching game's data version and the default from the item's tint definition.
An explicit custom color wins. Otherwise visible base and custom effects contribute their RGB
channels weighted by amplifier + 1, with integer division as in the game. Zero/missing duration
does not remove an effect from this color calculation; hidden particles do. Current components,
the potion-ID shorthand and legacy `Potion`/`CustomPotionEffects` tags share the same path.
Removal suppresses older tags and uses the supplied default. Missing contents or no visible
effects also uses that default. Unknown needed recipes/effect colors, unreadable color-driving
fields and more than 4,096 effects return nil, so clients can keep their unavailable-image fallback.

The vanilla registry facts are verified for **26.3 / 5023 only**, through the official game code
and a read-only registry probe (46 potions, 40 effects). They are defined in Minecraft's code,
not asset JSON. Other versions cannot borrow these inferred colors; an explicit saved override
or an empty effect set needs no registry lookup. This computed API changes no saved ItemStack
fields or cache version. It reuses active-effect ID/amplifier reading without changing which
effects count as active on a player.

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

Creature decoding reads the mob record Minecraft writes to the save. `Mob.addAdditionalSaveData`
unconditionally saves three booleans: `CanPickUpLoot`, `PersistenceRequired` and `LeftHanded`.
All three must be readable, including false values. `Health`, ownership and a familiar type
name alone do not establish that a saved entity is a mob. Items, experience orbs, armor stands
and players do not have this mob record in normal game saves.

This rule has no built-in entity catalog or per-version type list. New and modded IDs use the
same reader, and readable saved position, name, health, owner and UUID are retained without a
blanket “unrecognized” label. Missing health remains nil. IDs use Minecraft's canonical namespace
rules. The data version still governs existing version-specific facts such as omitted health
defaults; it does not gate mob membership.

This is a reader of the saved record, not a reconstruction of Minecraft's entity registry.
Incomplete or hand-edited records without the mob fields cannot establish membership, and a
record deliberately given those fields is read as a mob record. Raw entity APIs preserve all
records regardless. See [the source verification procedure](Tools/EntityTypes/README.md).
RegionFacts interpretation 14 discards earlier classifications and top-level-only entity scans,
including unpublished versions 8–13. `Fixtures.mob` supplies the game's saved mob booleans for
synthetic tests; callers supply ID, position and the other fields under test.

Entity-chunk creature and container reads include nested `Passengers`, with a vehicle before
its riders in saved order. `Dimension.entities(chunkX:chunkZ:)` returns that same flat walk of
raw records. Their original `Passengers` fields remain intact; callers consuming this list
must not traverse those fields again. A filtered or unreadable vehicle does not hide readable
riders. Each mob keeps the entity chunk's data version and its own `Pos`: Minecraft saves a
rider at the vehicle's current X/Z and the rider's current Y.

`PlayerInfo.rootVehicleCreatures` reads mobs in `RootVehicle.Entity`, including nested
passengers, through the same traversal and the player's data version. Use their own saved
coordinates with `PlayerInfo.dimension`, which is available independently of player coordinates.
`RootVehicle.Attach` names the player's immediate vehicle, not the player or the mob's owner;
the reader retains saved mobs even if that attachment cannot be reconstructed. Minecraft
excludes a root vehicle with exactly one player passenger from normal entity storage, saving
that tree with the player instead. These APIs read saved facts without simulating mounting.
The CLI combines these mobs with entity-region records. The app must adopt the player API
after the library is published; region facts alone cannot supply player-file mounts.

`PlayerInfo.shoulderPets` reads parrots stored in `ShoulderEntityLeft` and
`ShoulderEntityRight`, left first, through the same `Creature` reader and player
DataVersion. Saved owner, UUID, name, health and appearance are preserved. These
entity snapshots contain the position **before mounting**: locate a shoulder pet
with the player's current `position`, applying dimension and coordinate checks. An
unavailable player position does not discard its shoulder pets.
The dimension's entity-region reader does not include them; a client combines the
player and dimension records. Verified against the official 26.3 save/load and
shoulder-mount code. This additive API is available starting in v0.30.0; app adoption is
tracked separately in fahlman/ChunkseeKit#74.

The `creatures` command includes shoulder parrots in its selected dimension's
listing and totals. Their location is the carrier's saved position, with the
carrier UUID shown separately from the saved owner. A nonfinite or out-of-range
position prints as unknown; players without a recognized dimension/location record
are omitted from this dimension-specific command.

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

Starting in v0.39.0, the computed `Villager.isUnemployed` interprets the saved profession's explicit
`minecraft:none` category, using the shared identifier rules (so `none` means the same thing).
Missing, empty or malformed identifiers return nil. Nitwits and custom professions remain
distinct; false does not mean that the villager can work or trade. The raw `profession` and
serialized data are retained, so older cached values use this interpretation without a rescan.

The additive `Villager.supportsTrading` fact uses the vanilla 26.3 profession registrations
when there are no readable saved offers: the 13 trading professions return true, `none` and
`nitwit` return false, and unknown/custom/malformed professions return nil. A farmer that has
never been traded with still returns true because Minecraft creates offers lazily. Readable
saved trades take precedence, including custom or command-edited villagers. This does not
describe current interaction readiness (age, sleeping or sold-out offers). Custom registry
definitions are not loaded, and vanilla profession definitions are assumed unchanged.
The property is computed from existing fields: saved levels, Codable data and RegionFacts
interpretation are unchanged, and older cached records need no rescan for it.

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
    let stats = try world.statistics(for: player.uuid)            // statistics(forName:) for files from before 1.7.6
    print("  played", (stats?.playTime ?? 0) / 72_000, "hours, mined", stats?.value("minecraft:stone", in: "minecraft:mined") ?? 0, "stone")
    let advancements = try world.advancements(for: player.uuid) ?? []
    print("  ", advancements.filter { $0.isDone && !$0.isRecipe }.count, "advancements")
}
```

`player.inventorySlots(in: .hotbar)`, `.storage` and `.enderChest` expose ordered contents
with empty slots retained as `nil`. ChunkseeKit owns the saved slot ranges; clients supply
their own labels and visual layout. ItemStack keeps its original saved slot number, including
storage slots 9–35. Missing/out-of-range slots are omitted from this layout and the last
readable item wins a repeated slot, matching the game's loaded inventory. The selected-hand
reader uses that same hotbar, correcting its old first-item choice for duplicate slots; an
explicit saved main hand still wins. Raw inventory, ender-chest and equipment APIs are unchanged.
This additive API is available starting in v0.32.0.

`PlayerStatistics.unit(of:in:)` exposes the saved scale of known vanilla general statistics:
centimeters, ticks (20 per second), or tenths of a damage point. Unscaled counts and unknown
units return `nil`, so callers retain the raw number. Names, rounding and localized display
units belong to the front end. The original `values` dictionary is unchanged.
Time/distance IDs include legacy play-time and diving names. Damage scaling is verified only
for data version 5023 (26.3); other versions leave it unavailable. `distances` uses the same unit
lookup and no longer assumes that every unknown or custom ID ending in `_one_cm` is a distance.
Those values remain in `values`. This additive API and corrected classification are available in v0.38.0;
the app adoption is tracked in fahlman/Chunksee#298.

`GameRule.wanderingTraderSpawning.value(in: rules)` recognizes the current
`minecraft:spawn_wandering_traders` identifier and the legacy `doTraderSpawning` identifier.
It returns an explicit `.bool` value, or `nil` for missing or malformed values; the current
identifier takes precedence. Display names and other namespaces do not match. The existing
`World.gameRules()` dictionary is unchanged. This additive lookup is available starting in v0.32.0.

Modern world spawn, player death and player respawn share the `{dimension, pos: [I; x, y, z]}`
reader. A partial/unsupported world-spawn record leaves **both** `spawnDimension` and
`spawnPosition` unavailable; arbitrary coordinates never acquire an assumed Overworld dimension.
Bare dimension strings use the `minecraft:` namespace, as player/map dimensions already do;
custom qualified IDs stay intact. The shared identifier reader validates syntax, not world
membership. Legacy world-spawn XYZ still means Overworld, and the existing legacy player respawn
fallback remains. Player and map `unrecognizedDimension` values share one description: unknown
strings and integers retain their raw text, unsupported tag shapes use `?`, and missing tags remain
`nil`. Malformed player tags no longer expose a debug NBT dump. Public signatures and region-cache
interpretation are unchanged.

`PlayerInfo.equippedItems` combines the saved equipment slots and the selected main-hand item.
An explicit saved main hand takes precedence over the selected hotbar slot; unselected inventory
items are excluded. Player maximum health uses this same collection. The existing `equipment`,
`inventory` and `mainHandItem` APIs keep their meanings. `equippedItems` is an additive API
available starting in v0.32.0.

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

### Game asset models (v0.50.0 and later)

`GameAssets` reads a supplied Minecraft game jar through the same validated ZIP reader as data
packs. It never extracts files. The jar must contain a readable `version.json` with an ID and
world data version. The client chooses an installed jar matching its world and caches results
for that jar; no Minecraft artwork is bundled in this package.

The unreleased file-reader update (#156) keeps a read-only handle and the validated entry index,
rather than retaining the complete jar. Small temporary header buffers are released after
validation, and resource bytes are read only when requested. The same path serves ZIP data packs;
the in-memory constructor continues to retain its supplied Data. File reads use independent offsets
and retain their handle through each read, so copied readers can be used concurrently.
In-place modification or truncation makes subsequent resources unavailable. Replacing a path never
switches an existing reader to the new archive: it either keeps the original inode's resources or
becomes unavailable. A changed data pack blocks lower-priority fallback until it is reopened.
The last reader releases its file handle. No file is mapped into memory, extracted or written.
Sandboxed callers retain their required security-scoped access while using file-backed resources.
Memory and latency comparisons are still pending; this describes ownership, not measured savings.

```swift
if let assets = try GameAssets(contentsOf: gameJarURL),
   let model = assets.model("minecraft:block/stone") {
    // model.geometry has resolved cuboid faces or generated item layers.
    // Each material's texture identifier can be passed to assets.texture(_:).
    print(assets.version.id, model.guiTransform)
}
```

`AssetModel` contains inherited model geometry, resolved material references, tint indices,
face UVs/rotation, element rotation, light-emission/shade metadata and the game's GUI transform.
Cuboid positions and UVs retain the 16-unit model coordinate system; GUI translation is converted
to block units and clamped as in the game. Generated items expose ordered layer0...layer4, stopping
at the first absent layer. Texture reads return the original PNG bytes; image decoding, compositing,
projection, tint application and color averaging belong to the client.

Parents and texture references have cycle detection and a 64-step limit. Each resource and the
combined model JSON have a 16 MiB limit, and a model may have at most 4,096 elements. Missing or
unresolvable required resources return nil, as do nonfinite/invalid numeric fields; valid empty
geometry stays empty. These reader bounds intentionally reject unusually large custom models.
No resource-pack layering, general sprite-atlas remapping or animation interpretation is included.
Those follow separately for fahlman/Chunksee#390 and #363 using this shared reader.
The model format and defaults were checked against the official 26.3 client JSON and its
cuboid/model resolver bytecode.

`assets.palettedTexture("minecraft:trims/items/helmet_trim_quartz", in: "minecraft:items")`
resolves a palette-generated sprite from one atlas definition in **26.3 / 5023**. Its
`AssetPalettedTexture` names the base image, key palette and replacement palette as texture IDs;
read their original PNG bytes with `assets.texture(_:)`. Palette paths include the game's
`palettes/` directory. No trim/material-name table or image decoder is included.

Source order is preserved for `paletted_permutations`, `directory` and `single`: later existing
sprites replace earlier ones, while missing base images add nothing. A later plain sprite,
unsupported source kind, malformed resource or unverified version returns nil. Missing palette
PNGs or invalid images remain unavailable when the client reads/decodes the returned resources.
The atlas is limited to 16 MiB of JSON, 256 sources and 4,096 generated sprite entries in total.

After decoding both palettes to row-major **unpremultiplied `0xAARRGGBB`** pixels, use
`AssetPaletteMapping(key:palette:)` and its `color(_:)` method on base-image pixels. The palettes
must have equal lengths, at most 4,096 entries. Matching ignores alpha, skips fully transparent
key entries and uses the last repeated RGB key. Replacement alpha multiplies the source alpha
with integer division by 255; unmatched or fully transparent source pixels stay unchanged.
These rules come from the official `PaletteMapping`, `Palette` and atlas loaders. The APIs are
an unreleased foundation for fahlman/Chunksee#390; saved trim selection and app image/cache
adoption follow separately. Clients own PNG decoding, pixel conversion and caching.

`assets.defaultItemModel("minecraft:leather_helmet")` resolves the static default variant from
an item definition. Its ordered `AssetItem.parts` reuse `AssetModel` and carry
indexed tint sources: constant RGB, saved dye/potion/firework with definition defaults, or a
pixel in the supplied grass colormap. The client decodes that 256×256 PNG and applies colors to
the corresponding layer/face tint index; an absent index is untinted. Saved dye and custom-potion
overrides are available on ItemStack; normal potion-effect and saved firework colors are not
calculated by this asset reader.

Calling this API explicitly requests a static inventory illustration. A `minecraft:display_context`
select uses its `gui` case (a string or a member of a string list), or its fallback if none matches.
Other selects and ranges use fallbacks, conditions use their false branch, and a range without a
fallback uses its lowest-threshold entry (first on a tie).
It does not evaluate live compass angles, time, trim, custom model data or saved item-model
overrides. Only the selected branches are interpreted; unsupported unselected branches do not
prevent a usable default. An unsupported selected special/entity renderer, unknown tint or malformed value
makes the entire item unavailable, rather than returning part of a composite. Valid empty
definitions stay empty. Limits across the definition and its resolved models are 16 MiB of JSON,
4,096 elements, 64 selected nodes and 32 parts. Tint lists are limited to 32; range tables without
a fallback and inventory-context tables are limited to 4,096 entries. Inventory-context tables
require nonempty cases and unique, nonempty match values, with at most 4,096 values in total. Numeric JSON colors require signed 32-bit integers or three
finite Float channels in 0...1; Boolean, fractional scalar, overflow and invalid vectors stay unavailable.
Color conversion shares the saved-color owner. The official 26.3 definitions, item-model codecs,
tint codecs and GrassColorSource/ColorMapColorUtil establish the format and colormap coordinates.

`assets.itemModel(for: selection)` shares that reader and every model/resource limit. It also
matches `minecraft:trim_material` against the saved key, using normalized Identifier values for
single/list cases and rejecting duplicate normalized cases. Unmatched/absent keys use the fallback;
an unsupported selected branch never silently recovers the untrimmed picture. Other live properties
keep the default reader's choices. A non-nil trim key stays unavailable with unverified game
versions; a missing key still selects the generic fallback, preserving ordinary older armor.
GUI and trim case tables use one bounded selector. This changes neither defaultItemModel's
explicit fallback behavior nor texture loading. Generated trim textures still require palette-source
interpretation and native image decoding in the client. The official 26.3 TrimMaterialProperty,
ArmorTrim and select codecs establish selection; the item data fixer establishes the legacy field.

With the saved selection and verified **26.3 / 5023** assets, `minecraft:custom_model_data`
conditions read flags, selects match exact strings (including the empty string), numeric ranges
read Floats, and tint sources resolve to constant RGB. Each property's nonnegative `index`
defaults to zero; missing entries yield false, no matching string, zero, or the tint's required
default color. String cases use the same bounded table reader as GUI/trim cases, with exact UTF-8
keys instead of identifier normalization. Numeric ranges apply Float scaling, stable threshold
sorting and the game's actual search, including its duplicate/signed-zero behavior at 16 entries.
NaN products and below-range values use the fallback; an absent required fallback stays unavailable.
Tables are bounded to 4,096 entries. Unverified versions and malformed selected data stay unavailable.
The default-only reader keeps its earlier static branch choices and does not resolve custom tints.
The official 26.3 component/property/tint codecs and range selector establish these semantics;
synthetic saved NBT and definitions are compared directly with those game classes. No game artwork,
live property simulation or app parser is added.

Since v0.50.2, closed single chests and shulker boxes are supported special models for **26.3 / 5023**. They
resolve to ordinary `AssetModel` cuboids, so clients use the same drawing path as block items.
The chest body, lid and latch and the two shulker boxes use verified game-code geometry and UVs;
their texture IDs and inherited GUI presentation come from the supplied jar. Normal, trapped,
ender and copper chests (including oxidation/waxed variants), and undyed/all 16 colored shulker
boxes are covered. The normal chest fallback is used instead of evaluating Christmas dates.
No artwork is included. Clients still handle absent or undecodable PNGs as for ordinary models.

Texture identifiers retain their namespace and path: for example, a chest's `example:painted`
reads `example:entity/chest/painted`. There is no fixed catalog of texture names.
Special geometry stays unavailable for other game versions, open lids or double chests.

Since v0.55.0, the plain shield's plate and handle come from the official
`ShieldModel`, using `entity/shield/shield_base_nopattern` and the definition's base GUI settings.
Saved banner patterns and base colors remain outside this static default-variant API.

The v0.66.3 extension supports the static **26.3 / 5023** conduit item through the same
APIs. Its closed shell uses `entity/conduit/base` and the game's 32×16 skin dimensions; the item
definition still supplies its transform and base GUI settings. Shared cuboids and face UVs describe
it without a conduit-specific client renderer. Active world-conduit animation is not an item model.
Missing images keep the client's normal fallback, and unverified game versions remain unavailable.

The v0.67.1 extension supports **26.3 / 5023** copper-golem statues through these same
cuboids and rotations. The selected special definition supplies one of four fixed poses and a
full texture resource; all eight vanilla items (including waxed and weathered variants) are
covered. Their supplied item transform and base GUI presentation are preserved. `textures/*.png`
resources keep their namespace and use the same client image-loading path as other materials;
unsupported paths, poses and versions stay unavailable. The existing static selection policy
uses the standing fallback for block-state selectors; it does not resolve a saved statue's pose
or animate a live golem. No public API, cache format, image decoder or artwork is added.

The unreleased #205 extension supports **26.3 / 5023** skeleton and wither-skeleton skulls,
and zombie, creeper, dragon and piglin heads through the same cuboid/material APIs. The selected
`minecraft:head` definition supplies the kind, optional texture override and item transform;
the base model supplies its GUI presentation. The fixed phase-zero geometry includes the
zombie's inflated outer skin, dragon jaw and mirrored skin regions, and piglin ears. These
parts share the existing transforms, rotations and skin-size-aware UV mapping. The renderer's
verified default skin IDs are used unless the definition provides a namespace-preserving
`entity/` texture override. Nonzero animation, unknown kinds and unverified versions
stay unavailable. Missing images keep the client's usual fallback. No player-skin download,
new public API, image decoder, app renderer, artwork or world write is introduced.

The unreleased #209 extension adds local **26.3 / 5023** player-head pictures.
`ItemStack.headSkin` and `ItemModelSelection.headSkin` distinguish the unprofiled default,
an explicit current profile's `texture` resource, and an unresolved account skin. Missing or
removed profiles use the game's default slim Steve resource. Current profile data takes precedence
over legacy `SkullOwner`; malformed relevant fields return nil. Only the body's resource changes
local picture identity, not a name, cape, elytra or player-model width. The retained identifier is
bounded to 16 MiB. This is a picture-fact reader, not a complete account/profile validator.
The separate `minecraft:player_head` renderer shares the zombie head/hat geometry and the existing
material, UV, transform and budget code, with the game's translucent skin material. Resource paths
remain checked by the shared asset reader. Named/UUID/texture-property profiles without a local
body resource stay unavailable instead of being shown as their temporary default skin. No network
lookup, downloaded-skin cache, image decoder, artwork or world write is added. This additive API
needs a minor release before app adoption; remaining online skins stay on fahlman/Chunksee#390.

The unreleased #207 API `AssetModel.Material.staticTextureAspectRatio` identifies the verified
whole-image width/height ratio for these static special skins. It is derived from the same skin
layout used for their UV mapping: conduit and several skulls are 2:1; the other supported skins
are square. This lets image clients accept rectangular or higher-resolution skins without guessing
from item IDs or accepting ordinary animation strips. Ordinary materials leave this field nil,
so their frame layout remains unspecified. Pattern recipes and item transforms preserve the
metadata; image decoding, dimension checks and missing-image fallback remain client-owned.

Selected ancestor and local transforms compose in parent-to-child order. They are baked into
special geometry for positive X scale, matching nonzero Y/Z signs, translation, and identity or
an axis-aligned half-turn, with an identity right rotation. This covers both the shulker's quaternion
turn and the shield's parent Y/Z sign flip. Unsupported special-model transforms return nil
instead of being ignored; their final coordinates stay within the existing -16...32 model bounds.

Ordinary element models support translations (since v0.55.1) and unit axis-aligned half-turns
(since v0.57.1), including the colored beds and straw bed. The shared transform moves corners and
rotation origins, remaps faces with their UV orientation and adjusts existing element rotations.
Tints, rescaling and GUI settings remain intact. Transformed coordinates may extend beyond the
source model's bounds, but must remain finite. Other scales/rotations and transforms on generated
layers remain unsupported. All selected parts keep the shared element/JSON/part budgets.
No public type or cache interpretation changes.

### Biome color definitions (v0.52.0)

Biome colors come from the supplied game jar and the world's enabled data packs:

```swift
let assets = try GameAssets(contentsOf: gameJarURL)
let definitions = try world.biomeDefinitions(
    for: ["minecraft:plains", "example:custom_biome"], assets: assets)
if let plains = definitions["minecraft:plains"] {
    print(plains.waterColor, plains.temperature, plains.downfall)
}
// A jar can also be read without a world or data-pack overrides.
let jarPlains = assets?.biomeDefinition("plains")
```

These additive APIs read the verified 26.3 format (data version 5023). Results contain
unclamped base temperature/downfall, a 24-bit RGB water color, optional grass, foliage and
dry-foliage overrides, and the grass modifier (`none`, `dark_forest`, or `swamp`). Colors accept
six-digit `#RRGGBB` strings, signed Int32 values, or three Float channels in 0...1, using the
existing shared conversion. Numeric values are strict: unlike Gson's coercions, fractional
integer colors, out-of-range integers/channels, Boolean and nonfinite numbers are unavailable.
Other biome fields are neither interpreted nor validated.

World lookup canonicalizes requested IDs and reads only those resource payloads. Enabled folder and
ZIP packs use the same priority and safe paths as dimension settings. A present malformed
override or unsupported higher-priority pack prevents lower fallback. Missing or
data-version-mismatched jars make vanilla unavailable; higher-priority pack definitions can
still resolve. Missing/other saved data versions return an empty result, and an absent enabled
pack list is not replaced with an assumed vanilla pack. File errors propagate.

No Minecraft biome-color table or artwork is bundled. The caller supplies the game file and
performs these synchronous reads off its UI actor. Color-map PNG access uses `GameAssets.texture`.
No chunks are scanned or world files written.

The `world.biomeDefinitions(assets:)` overload, available in v0.56.0, discovers all available biome
definitions in those same sources, including nested data-pack IDs, without first scanning
the world's chunks. It loads the enabled packs once and shares the requested-ID query's
priority and invalid-override handling. ZIP discovery uses the validated central directory.
Folder registry discovery follows the game's rule: symbolic links at or below the biome category
folder are not entries, while contained namespace aliases are supported. A higher linked resource
therefore cannot override a lower listed definition. The same registry eligibility now applies
to requested-ID biome queries and dimension-type/noise-settings references (an unreleased
correction to the earlier direct-resource lookup). Each queried category is listed once; payloads
are read only for requested IDs. Inline dimension settings do not require listing, and type-only
queries do not open noise-setting resources.
Malformed definitions remain absent, and an unknown or changed higher pack cannot expose a
lower definition. Cancellation and file-read errors propagate. Retain the returned value as
a snapshot; reread after changing enabled packs or their contents. Image decoding, color
caches and tile invalidation remain client-owned.

### Terrain tint sources (unreleased)

`BlockState.tintSource(at:gameDataVersion:)` interprets a block model face's tint index for the
verified 26.3/5023 registry. Its `BlockTint` is either a fixed 24-bit RGB color or a `BiomeColor`
(`grass`, `foliage`, `dryFoliage`, `water`) with a vertical biome-sampling offset. For example,
spruce and birch leaves have fixed colors; oak and mangrove leaves use foliage; upper tall grass
uses the grass biome one block below. Flower definitions keep their separate untinted and
grass-tinted indexes. Stem age and redstone power retain their saved colors. The omitted
half/power/age defaults use the same verified registry owner as block-model selection; invalid
properties, unknown blocks/indexes and unverified versions return nil.

This API describes in-world **block models**, not item or particle colors. Fluid water obtains
its color directly from the biome; the water/bubble block-model sources are white because the
game applies their biome color only to terrain particles. A water cauldron's model uses water.

Call `BiomeDefinition.color(_:x:z:sample:)` for the chosen biome. It applies explicit overrides,
clamps the saved climate for the shared 256×256 colormap lookup, and applies the game's
dark-forest or fixed-seed swamp-grass modifier. X/Z are signed block coordinates. The `sample`
closure receives a texture identifier and a top-left-origin pixel and returns that decoded
pixel's RGB value, or nil when unavailable. Overrides and water do not need a decoded image;
swamp grass replaces the base color entirely. Missing needed pixels remain unavailable.
`BiomeDefinition.colorDependsOnPosition(_:)` (unreleased) reports whether X/Z can change a
source's color. If false, a client can resolve that source once for this definition and its
unchanged colormap pixels. The color resolver uses the same rule; clients need not repeat
modifier checks to decide which colors can be reused.
Image decoding, choosing the correct biome, optional blending across neighboring biomes,
map shading, caches and drawing stay with the client. Item grass tints share the same climate
pixel arithmetic; no second PNG/archive reader or mutable color cache is added.

### Blockstate model selection

`GameAssets.blockModel(for:)` matches a `BlockState` against its jar definition and returns
an `AssetBlock`. Explicit variants take precedence over multipart selectors. All matching
multipart pieces are retained, in definition order. Each part contains one or more weighted
alternatives, with its model ID, inherited `AssetModel`, X/Y/Z quarter turns and UV-lock flag.
The rotations remain separate from the model's inventory transform. The resolved value preserves
all choices for overview colors. Its `selectedAlternatives(at:)` (v0.66.0) returns one
alternative per part for a whole `BlockPosition`, without rereading resources or projecting faces.
Selection is verified for vanilla 26.3/5023 only. It uses the game's position seed, weighted draw,
and multipart reseeding; beds share their head position, and doors/double plants share the lower
position. The shared legacy random generator preserves Java's signed overflow and rejection rules.
All three input coordinates must fit Int32. Unverified versions/namespaces and unresolved or invalid
seed-driving properties return nil while the existing `parts` remain available. Ordinary Minecraft-namespace
blocks come from the supplied jar's definitions, without a second name catalog; the 49 verified
seed overrides stay in Kit because those rules exist only in game code. Item-frame entity render
states have no block seed and remain unavailable. Modified block behavior is not resolved.
The special seed-rule sets obtain omitted properties from the same registry owner as model predicates.

`AssetModel.Face.textureCoordinates` returns the four normalized UV coordinates in original
face-vertex order after the face's own rotation. The additive, unreleased
`AssetBlock.Alternative.textureCoordinates(for:facing:)` also applies the block's UV lock,
verified against 26.3 `ModelState` and `FaceBakery`. Pass the original face direction before
element/block rotation; rotate geometry separately. Partial and inverted rectangles retain
their meaning, and coordinates outside the texture are not clamped. Model data is unchanged.
The shared reader owns the face-frame transform, so image clients need no second UV-lock rule.

```swift
let horizontalLog = BlockState("minecraft:oak_log", properties: ["axis": "x"])
if let models = assets.blockModel(for: horizontalLog) {
    for part in models.parts {
        for choice in part.alternatives {
            print(choice.modelID, choice.weight, choice.rotation, choice.uvLock)
        }
    }
    let position = BlockPosition(blockX: 10, blockY: 64, blockZ: -4)
    let selected = models.selectedAlternatives(at: position)
    print(selected?.map(\.modelID))
}
```

In 26.3, a saved default state can omit its properties. For a 26.3/5023 asset jar, omitted
properties now use verified registry defaults for known Minecraft blocks (unreleased, #195).
For example, `BlockState("minecraft:oak_log")` resolves the `axis=y` model; supplying `axis=x`
still selects the horizontal model. Explicit saved values win, and the saved `BlockState`
itself stays unchanged. Model predicates, special seed rules and color-driving properties share
one default-property owner. Other versions, namespaces, names and properties gain no inferred
defaults. If an unresolved property prevents a decision, the result stays nil so clients can
retain their fallback. Explicit property domains are not validated against the game registry.
Multipart AND/OR and pipe-separated alternatives are supported, including the
26.3 per-term `!` negation only for data version 5023; negation in other versions stays unavailable.
Integer and Boolean condition values retain the codec's legacy representations. Numeric fields
use strict JSON types and signed 32-bit bounds rather than coercing strings or fractions.

Missing or unsupported selected models, overlapping variants, malformed selectors and exhausted
bounds return nil for the whole result. Unselected model resources are not loaded. An empty
multipart result remains empty. Reads share a 16 MiB JSON / 4,096-element budget across at most
256 selected models. Definitions allow at most 4,096 selectors; condition traversal allows
4,096 nodes/terms and 64 nested levels. Weighted alternatives have positive weights with a
signed 32-bit total; a standalone model ignores the weight field, as in the game.

This additive API reuses the existing archive/model/texture owners. Image decoding, caching,
tinting, color averaging and map drawing remain client/adoption work on
fahlman/Chunksee#363. No world data, persisted shape or RegionFacts interpretation changes.

### Raw NBT

```swift
let level = try NBT.read(contentsOf: url)               // handles gzip and zlib automatically
let name = level["Data"]?["LevelName"]?.string

let bytes = NBT.compound(["answer": .int(42)]).serialized()
let (rootName, value) = try NBT.read(bytes)
```

`serialized` uses an explicit traversal stack, so deeply nested lists and compounds do not
consume one function-call frame per tag. It preserves sorted compound keys, list element
types and the existing binary encodings. The writer has no fixed nesting limit; the reader
still rejects tag depth 512 or greater, with the root at depth zero. A value beyond that
reading limit can therefore be serialized but cannot be read back by this reader.

`ItemStack`, `ItemContainer`, `Spawner`, `Sign`, `BookContent`, `Creature`, `Villager`, `Trade`, `PointOfInterest`, `RegionContents` and `NBT` retain their existing `Codable` conformances; `NBT` encodes as binary NBT. For new combined scan caches, use the versioned `RegionFacts` envelope described above rather than treating each model as an independently versioned cache.

For complete raw saves, use `NBT.read` and `RegionFile.chunkNBT` rather than retrieving the
saved input from `PlayerInfo`, `LevelInfo` or `Chunk`.

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
| `chunksee <world> creatures [dimension]` | Villagers, named and owned creatures, and shoulder pets; then counts of every kind |
| `chunksee <world> maps` | Maps made in the game: dimension, center, scale and whether anything is drawn |
| `chunksee <world> rules` | Game rules and their values |
| `chunksee <world> players` | Each player's name (from the game folder's `usercache.json`), last position, last death, respawn point, game mode, health, food, level, items, play time and advancements |

Creature and player coordinates name the containing block (negative fractions round down).
The creature list uses `CreatureEntry.Group.group(for:)` for the same categories as the map,
including unnamed villagers, and also includes player-carried shoulder pets.
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

`ItemContainer.lootTable` exposes the saved optional loot-table ID on block and entity containers,
including chest minecarts. It adds no item prediction. Consumers can pair it with `isSealedLoot`
to name unopened loot; an opened container no longer has a saved table. This additive property is
**available starting in v0.31.0**. Older standalone container archives decode with a nil table;
RegionFacts interpretation version 2 invalidated earlier region archives so they were reread.

`ItemContainer.uuid` is the optional saved identity of an entity container (added in **v0.34.0**).
It uses the shared UUID reader for current arrays, strings and legacy Most/Least pairs, keeping
colocated minecarts distinct and their identity stable when they move. Blocks and entities with
no readable saved UUID return nil; no identity is generated. Older standalone container archives
still decode with a nil UUID. RegionFacts interpretation version 3 invalidates earlier region
archives so entity IDs are reread from the world.

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

### Typed save values (v0.30.0)

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
remain public. These additions are available starting in v0.30.0.

v0.31.0 also adds `ChunkPosition(containingBlockX:blockZ:)` and
`ChunkPosition.localColumnIndex(blockX:blockZ:)` for clients that have a block column without a
height. The latter selects a column in a 256-entry chunk array, with local Z before X. Both accept
whole block coordinates; use `BlockPosition.coordinate(containing:)` first for exact decimals.
`RegionPosition.sideInBlocks` supplies continuous geometry's region width independently of a
renderer's pixel resolution. These three additions first appear in v0.31.0.
