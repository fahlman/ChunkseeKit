# ChunkseeKit — Repository Instructions

Read with the shared `AGENTS.md`. Project record: fahlman/ChunkseeKit#1.

## Project

ChunkseeKit is the engine for reading Minecraft: Java Edition world saves. Ryan intends to
open-source it so others can build their own GUIs on it. The core library owns the file formats:
NBT, Anvil region files, chunk decoding, and the world-folder layout. The package's separate
ChunkseeIndex library owns aggregation over typed facts. Neither has UI or app code.
The Mac app **Chunksee** (`com.fahlsing.Chunksee`, fahlman/Chunksee) lives in its own
repository and depends on this package, the way Euchre depends on EuchreKit. Dependency direction:
**Chunksee app → ChunkseeKit**. Both were renamed from MCWorld and MCWorldKit on 2026-10-10
(fahlman/Chunksee#75).

- **Kind:** Swift package (a library plus a command-line tool). It is not a Mac app, so it has
  no `.xcodeproj`.
- **Products:**
  - `ChunkseeKit`, the library.
  - `ChunkseeIndex`, shared aggregation over the reader's typed facts. Its first API,
    `StoredItemTotal.totals(in:)`, owns per-ID quantities and outer-container counts, including
    nested contents. This product is available in v0.37.0; app adoption follows this release.
  - `ChunkseeKitTestSupport`, synthetic save builders for test targets, using the reader's public
    NBT and compression APIs. This additive product is introduced in v0.35.0; app adoption
    follows that release, tracked on #82.
  - `chunksee`, a command-line tool that inspects a world and decodes every chunk (`scan`). It
    uses only the library's public API and serves as a working example for GUI authors.
- **License:** MIT (`LICENSE`).
- **Dependencies:** Foundation and system zlib through `CZlib`. There are no package
  dependencies, so there is no `Package.resolved` to track (it is git-ignored).

## Modules

| Module | Owns | May depend on |
|---|---|---|
| `CZlib` | Module map for the system `libz` | — |
| `ChunkseeKit` | `NBT` (read/write, modified UTF-8), `Compression` (zlib/gzip, bounded raw deflate, LZ4 block streams), `RegionFile`, `Chunk`/`ChunkSection`/`PalettedContainer`/`BlockState`, `World`/`Dimension`/`LevelInfo` | Foundation, `CZlib` |
| `ChunkseeIndex` | World catalog and dimension-labelled enumeration, compact retained region inputs and dimension reconciliation/aggregation; matching-item and storage totals, connected biome areas, point-region lookup, grouped deposits, creature membership/identity and query interpretation/matching. No display names, localization, UI state or file decoding | Foundation, `ChunkseeKit` |
| `chunksee` | Command-line presentation only | `ChunkseeKit`, `ChunkseeIndex` |
| `ChunkseeKitTestSupport` | Shared synthetic section, chunk, region, UUID and file builders (`Fixtures.swift`); packing stays independent of the decoder | Foundation, `ChunkseeKit` |
| `ChunkseeKitTests` | Tests built with the public fixture builders; `CLIFixtures.swift` locates and launches the CLI built beside the test bundle | `ChunkseeKit`, `ChunkseeKitTestSupport`, `CZlib` |
| `ChunkseeIndexTests` | Public aggregation behavior over synthetic typed inputs and shared save fixtures | Foundation, `ChunkseeIndex`, `ChunkseeKit`, `ChunkseeKitTestSupport` |

`ChunkseeIndex.BiomeArea.connected(in:)` owns edge-connected biome grouping, representative-member
selection and exposed chunk sides. It preserves every area and ignores unmappable chunk origins.
This pure aggregation takes chosen biome membership; file reads, surface/cave policy, display
names, colors and drawing paths stay outside it. Membership and boundary discovery share one walk.
This additive API is available in v0.42.0; app adoption is tracked on fahlman/Chunksee#383 and #214.
It changes no save reader, cache interpretation or held cave-biome rule.

`ChunkseeIndex.PointIndex` owns immutable region buckets and broad point-candidate lookup, using
the core checked coordinate conversion and region size. Results preserve input order and retain
unbucketable entries for the client's final checks; unusable bounds return the full snapshot.
Sparse queries inspect occupied buckets instead of enumerating huge empty ranges. This is the
app's existing PointMarkers lookup, with viewport conversion, precise geometry, visibility and
presentation kept outside the library. The additive API is available in v0.43.0; app adoption is
tracked on fahlman/Chunksee#384 and #214. It adds no reader, cache or task owner.

`ChunkseeIndex.SearchQuery` owns the app's existing category-prefix parsing and all-word matching.
Recognized prefixes ignore case and trim horizontal whitespace; unknown prefixes stay literal.
Its explicit phrase initializer preserves the CLI's contiguous, case-insensitive `find`/`text`
queries, including spaces and colons. Both forms share one substring matcher. The CLI consumes
that owner; app names, prompts, symbols, category membership and result formatting remain outside
the library. This additive API is available in v0.44.0 and adopted by fahlman/Chunksee#385.
Retained world-index state and typed result aggregation remain separate work on fahlman/Chunksee#214.

`ChunkseeIndex.NotableBlock` owns the app's existing nine block-search groups and exact ID catalog.
Its nested Deposit groups the core reader's per-ID counts and enclosing section-height bounds,
combining ore variants and ordering by the group's raw value. Unknown IDs and common blocks outside
the catalog remain excluded. These are indexed section ranges, not exact block locations. Core
scan options and file interpretation are unchanged; client names and search-result wording stay
outside the module. This additive API is available in v0.45.0; app adoption is fahlman/Chunksee#386.
It prepares compact typed region contributions without retaining unused heightmaps or repeating
group aggregation in the app. Tests exercise public scans with shared synthetic fixtures.

`ChunkseeIndex.RegionIndex` retains compact typed contributions; `DimensionIndex` owns replacement,
failed-read retention, selected deletion and complete cross-region aggregates. Its public
regionsToRead method supplies the read set for both the client scheduler and updating. The first
pass always covers all available regions; a completed empty/failed pass is distinct from never-read.
A broad pass removes
all unavailable regions; a partial pass preserves unselected contributions. Replacements must match
the dimension, selected/available coordinates and explicit cave-membership set. Empty successful
reads clear old values; an omitted available replacement retains them. Region traversal is X then Z;
native marker sort/presentation remains a client concern. Portal and biome joins happen after all
retained contributions are combined. Heightmaps, inhabited-time grids and ordinary unnamed mobs
are not retained. These are in-memory values, with no persistence or file/task owner.

`CreatureEntry` owns the app's existing villager > owned pet > named category precedence, stable
UUID/fallback identity and checked location eligibility through core BlockPosition.mapCoordinates
(floored X/Z fit Int32, supplied Y fits Int, unknown Y stays nil). Native map navigation and creature
eligibility share this public helper; it does not enforce the game world border.
Its category raw values remain named/pet/villager for client settings. Names, colors, symbols and
player-carried projections remain in the app. The additive region/dimension APIs are available in v0.46.0;
separate app adoption on fahlman/Chunksee#214 will remove its matching rules and retain cached native
marker projections for unchanged regions. Background-work scheduling and canceled-publication
guards remain app-owned. Tests use real synthetic scans, including cross-region joins and incremental
versus complete reads. No renderer, scan-ID, cave-membership or RegionFacts version change.

`WorldIndex<Dimension>` owns the dimension-keyed world snapshot and its typed Placed/all enumeration.
The generic payload lets clients keep native projections with their shared facts, without a second
world catalog or UI imports here. Matching values in different dimensions remain separate records;
member order is preserved and dimension order is unspecified. Dictionary value semantics retain
earlier snapshots when a later one replaces a dimension. The app's reader catalog, background tasks,
cancellation and publication stay app-owned. This additive API is available in v0.47.0; app adoption and
remaining typed search-result work are tracked on fahlman/Chunksee#214.

`ItemTotals<Key>` owns matching-stack quantities, using the core ItemStack.allItems traversal for
nested contents. The caller supplies its predicate and grouping identity; searchable fields,
localized labels, ordering and output remain client-owned. CLI find uses its existing custom-name
or saved-ID key; StoredItemTotal uses saved IDs and keeps outer-container counts. A matching
zero-count stack remains a result. This additive API is available in v0.47.0; app adoption follows the
release on fahlman/Chunksee#214. No reader, inventory selection or cache meaning changes.

SearchSelection owns the inventory-plus-saved-equipment input, saved book/sign search fields,
creature-filter membership and strongest-deposit selection across dimensions. The CLI consumes
PlayerInfo.searchableInventory, BookContent.searchText and Sign.searchLines from this module.
Saved sign whitespace and book line boundaries remain significant to phrase queries; the app can
trim captions separately. Filter.includes shares creature/pet/villager/trade membership, with
offer matching still required for trades. WorldIndex.richestDeposits expects each dimension's
canonical richest-first array and preserves the existing equal-count ordering freedom. The app
retains its display limit, localized search labels and marker/title/detail construction. These
additive APIs are unreleased, with app adoption on fahlman/Chunksee#214. No core reader or cache change.

The library's public `BlockPosition` owns conversion from exact positions to whole containing
blocks. Its `coordinate(containing:)` function handles one axis; its failable XYZ initializer,
entity-container reads and CLI creature/player output share that rule. Negative fractions round
down, and nonfinite/out-of-range coordinates are unavailable. The CLI retains those records with
unknown positions; the container reader omits an unmappable container while keeping its neighbors.
`BlockPosition`, `ChunkPosition` and `RegionPosition` own block/chunk/region conversion,
including negative containing coordinates and checked multiplication for region/chunk origins.
Their typed Dimension overloads and the older integer overloads share those rules. PlayerInfo's
exact Location exposes a checked containing block without changing its saved decimals.
X/Z-only callers use `ChunkPosition(containingBlockX:blockZ:)` and `localColumnIndex(blockX:blockZ:)`;
the full BlockPosition conversion delegates to the same initializer. RegionPosition owns its
public block-side constant, independent of renderer pixels. These additive APIs are available in v0.31.0; app adoption is tracked on fahlman/Chunksee#214 (Claude-F2 on #232).
`Identifier` owns the default namespace and 26.3 character validation. Dimension/effect/enchantment
readers use it; malformed saved identifiers become unavailable. The empty-path codec value is
retained, but World.dimension still requires a nonempty path and rejects an explicit empty namespace.
Identifier syntax is not file-path validation. `SaveVersion` owns verified release numbers and
format boundaries; `DataVersion` remains a source-compatible alias. Unknown newer versions do not
gain verified health defaults. PlayerInfo and MapItem share the unknown-dimension description
next to the NBT dimension-tag reader: raw strings and integers remain readable, unsupported tag
shapes use `?`, and missing values remain absent. This replaces the player's debug-NBT fallback;
it changes no public signature or RegionFacts value. POI, map banners and paired block locations share the int-array
reader; only map banners retain their existing legacy coordinate-compound fallback. Chunk,
containers, signs and spawners share modern block-entity list/position readers. This adds no
legacy terrain support. These public APIs are available starting in v0.30.0.
The CLI structure scan streams each region through `Dimension.forEachChunk`, then uses
`Chunk.isFullyGenerated` and `structureStarts` after skipping unneeded block data; it does not
repeat region/chunk reads or apply its own chunk-status or placement rules. Structure-center
X/Z coordinates use the same public single-axis conversion without inventing a height.
CLI item/text searches share inventory-plus-equipment selection and a deduplicated union of
terrain/entity region coordinates. ChunkseeKit's existing readers own item and region formats.
CLI scan totals use `PalettedContainer.paletteCounts()` directly over packed data rather than
expand an array of every block index before counting.
`NetherPortal.roundTrip` owns the default-entry two-way/one-way classification; the CLI presents
its result, including a return that would create another portal. Existing single-link prediction
rules and `NetherPortal.Link` are unchanged; the additive API is available starting in v0.28.0.
Portal grouping checks neighbor additions, and dimension scaling clamps before converting to
Int. Link distances use Double subtraction/squares, matching 26.3 Vec3i/PortalForcer, so extreme
saved heights cannot trap. Search radii, border bounds and the lower-Y tie rule are unchanged.

`Dimension.scan(region:options:)` owns the combined terrain/entity/POI traversal and returns
`RegionFacts`. Each present chunk payload is decoded once using the shared format readers.
Typed terrain facts expose used biome IDs, an explicitly chosen middle-column biome sample,
per-ID block counts/section bounds, heightmaps and generation metadata. UI categories, cave-area
joining and search stay outside the core. Incomplete generation contributes metadata, not terrain
search facts; legacy chunks still contribute inhabited time and format counts. Missing files are
empty, unreadable chunks are counted, and file-open failures/cancellation throw instead of
returning a cacheable partial value. No cache storage or task scheduling is introduced here.
`RegionFacts.interpretationVersion` must increase whenever any reader changes a fact's meaning.
The versioned envelope is the new Codable boundary, with options and dimension/region identity;
consumers also key all three file fingerprints and their own transform version. Older model
conformances remain source-compatible until separately migrated. The new API is available in
v0.30.0; Chunksee's pin and app adoption are separate work.

`ItemContainer.lootTable` retains the saved table ID for unopened-loot presentation, including
chest minecarts; readers keep the existing sealed-loot and empty-container behavior. RegionFacts
interpretation version 2 forced older cached regions to be reread for the new field. The additive
API is available in v0.31.0 and its app adoption remains on fahlman/Chunksee#122.

`ItemContainer.uuid` retains the optional saved identity of entity containers through the shared
`NBT.uuid` reader. Fixed block containers have no entity identity, and missing or unreadable IDs
remain nil. Colocated minecarts stay distinct and moving a cart does not change its saved UUID.
Standalone older container archives still decode; RegionFacts interpretation version 3 requires
cached regions to be reread. This additive API is introduced for v0.34.0; app adoption remains on fahlman/Chunksee#122.

The library only reads world files. Apart from the NBT writer, which tests and tools use to
build fixtures, it never writes into a world folder.

`GameRule.wanderingTraderSpawning.value(in:)` looks up the current or legacy saved identifier
in the existing `World.gameRules()` dictionary. It accepts explicit Boolean values only, gives
the current ID precedence, and leaves missing/malformed values unknown. Other namespaces and
display labels do not identify this rule. The raw dictionary API stays unchanged. This additive
API is available in v0.32.0; Chunksee's display-name comparison adoption remains on #51.

`Dimension.regionURL(_:x:z:)` owns the `r.x.z.mca` filename under terrain/entities/POI.
It accepts region coordinates and returns the path without opening or requiring a file. `region(_:x:z:)`
uses it and keeps missing-file (`nil`) and read-error behavior; clients need not reproduce filenames.

`Dimension.forEachChunk` exposes a synchronous, throwing visit without retaining a decoded NBT
array. Missing regions are empty, damaged chunks are skipped, and opening/callback errors
propagate. `Chunk.inhabitedTime(in:)` owns the current root/legacy `Level` metadata fallback,
shared with Chunk and the regional time reader. It does not decode legacy terrain or change
the hold on #38. These are additive public APIs.

`PackedLongs` owns the non-straddling packed-long traversal used by palettes and heightmaps.
`ChunkSection.blockIndex(x:y:z:)` exposes the existing YZX section-index owner for batched
consumers. Blocks, per-block biomes and lights call it too. Coordinates retain the existing
0–15 wrapping; the inlinable public body lets a renderer share the rule in its inner loop.
This additive API is available in v0.36.0; app adoption remains on #51. Reader/cache meaning is unchanged.
`Chunk.heightmap(_:)` infers only a unique width from stored length; ambiguous maps require
`heightmap(_:height:)` with the dimension's actual build height. Both return first-free-block
absolute Y. Invalid context or overflowing coordinates are unavailable; no legacy terrain support
is added. The explicit-height overload is additive public API.

`Chunk.surfaceY(x:z:height:)` and `surfaceHeights(height:)` share the WORLD_SURFACE reader and
actual-block fallback. Surface means the highest non-air block, including plants and water,
matching 26.3 Heightmap.Types/NOT_AIR; MOTION_BLOCKING is not an equivalent fallback. Empty
columns remain unavailable. Single-column reads inspect only that column; batched reads unpack
each reached nonuniform section once. RegionScan uses the same owner for its surface biome
sample while preserving explicit-Y sampling. RegionFacts interpretation version 4 invalidates
older sampled biomes, which could use a section top or an unused palette entry without a real
surface. These additive APIs are available in v0.39.0; app adoption is tracked on #51.
Colors, water shading, roof-view selection and the held cave-biome rule are unchanged here.
The additive `Chunk.forEachColumnRun(from:_:)`, available in v0.40.0, shares that fallback
traversal with surface queries. It visits all columns from the shared surface rule or an explicit Y, emitting
uniform-section spans and individual nonuniform blocks with their original section/palette
references. Missing sections remain gaps; invalid references cannot establish a surface.
Callers stop each column independently, while each reached nonuniform section is unpacked once.
Single-column surface queries retain direct lookups without unpacking the whole section.
Checked Y arithmetic, heightmap starts and section/column iteration belong here; colors, water
shading and roof hiding stay in the app. App adoption and its separate measured comparison are
tracked on #51 and fahlman/Chunksee#354. No existing surface or cache interpretation changes.
`BlockState.isAir` uses Identifier's shared namespace rules while retaining raw IDs. Short and
empty-default-namespace air names therefore match their qualified vanilla names; foreign
namespaces do not. RegionFacts interpretation version 5 invalidates cached surface samples
that treated valid short air names as solid blocks. The CLI's air-only section filter uses this
same classification. ItemStack uses Identifier for the empty `minecraft:air` item too, including
nested inventories, while retaining other raw IDs. Interpretation version 6 invalidates cached
item reads with the old literal-only rule. No public API or serialized shape changes.

`DimensionType` owns validated build bounds, logical height and the ceiling flag.
`World.dimensionTypes()` follows saved dimension-to-type links in modern world-generation data
or legacy inline settings. Enabled folder packs resolve in reverse priority order; the four vanilla
definitions are verified for 26.3/5023. Missing, malformed or unresolved values remain absent.
Experimental packs, overlays and filters are not resolved, so an unsupported higher-priority
pack blocks lower fallbacks. This narrow reader does not infer types from dimension IDs, infer roof
Y from logical height, load a complete game registry, or cache metadata. Path checks keep reads
within the selected pack; file-read failures propagate. The fields, bounds and pack priority were
checked against the official 26.3 DimensionType/LevelStem codecs and resource manager; the saved
mapping was checked in the committed ChunkseeTestWorld 26.3 metadata. This additive API is
introduced for v0.33.0, with app adoption on fahlman/Chunksee#248 and shared ownership on #51.

Enabled ZIP packs now use the same priority as folders. `ZipResources` validates their complete
central directory and matching local headers before a missing resource can permit fallback.
It reads ordinary stored/deflated entries with exact UTF-8 names, using the existing public
zlib API through `Compression` for bounded raw deflate and checking CRC and exact output size.
Duplicate names, overlapping records, encrypted, ZIP64, multipart, unsupported compression and
malformed archives stay unavailable. Requested JSON payloads have a 16 MiB bound; an invalid
present override still blocks fallback. No file is extracted, no private SDK declarations or
new dependency is added. Layout follows PKWARE APPNOTE 6.3.10, sections 4.3–4.4. This support
is available in v0.40.0, with separate app adoption on #51.

The companion `World.dimensionSettings()` reads that same mapping once for independently
available dimension types and noise-generation facts. `NoiseGenerationSettings` reads inline
or referenced `minecraft:noise` settings; its seven vanilla bounds and sea levels are verified for 26.3.
Its optional `seaLevel` reads the root `sea_level` signed 32-bit integer independently of the bounds.
Absent or malformed sea levels stay nil without discarding readable bounds or taking another
pack's value. Values outside the generation/build range remain unchanged, matching the game's
Codec.INT's lack of a range constraint and the floating-islands preset. Numeric decoding follows
the existing bounds reader: integral NBT tags and integer-valued JSON numbers (including `63.0`)
within Int32 are accepted; floating-point NBT tags, fractional JSON values and overflow stay nil.
This is deliberately stricter than the game's `Number.intValue` conversion, which can truncate or
narrow such numbers. The app owns how to use these facts in a height scale; no actual water surface
is inferred. This additive field supports fahlman/Chunksee#388 and #356, with publication and app
adoption handled separately.
The existing type-only API shares the resolver but never opens generator resources. Empty noise
heights remain valid; unknown generator kinds and unresolved settings remain unavailable.
DimensionType owns the common packed-Y validation, with its extra nonempty-height requirement.
`surfaceRuleRange(in:)` follows WorldGenerationContext/VerticalAnchor's max-of-minima and
min-of-heights calculation, not range intersection or logical height. It describes surface-rule
anchors, not a verified physical roof. Official 26.3 bytecode/JSON and the frozen world copy's
saved generator references were checked without writing to the copy. These additive APIs are
available in v0.40.0; app ceiling-context adoption remains on #51. Cave inference
and app colors/view policy are unchanged.

World-level saved data and per-dimension world-border/dragon records share the internal
World.readSavedData path/existence/NBT reader. Public World.savedData retains namespaced-first
and flat-file fallback; dimension records keep modern-only file lookup and their existing
level.dat fallback. This does not broaden which legacy files are parsed as modern records.

`World.isSlimeChunk(x:z:seed:)` owns Java Edition's chunk classification for the slime overlay.
It accepts Int32 chunk coordinates and an Int64 seed; seed mixing and the 48-bit bounded random
draw preserve the game's overflow/rejection semantics. Verified against the official 26.3
client, including an explicitly constructed rejection case. Spawn conditions remain separate.
The app uses World.seed() and this public rule, available starting in v0.29.0.

`PlayerInfo.shoulderPets` owns the two saved shoulder-entity keys and reuses Creature decoding
with the player's DataVersion. It retains parrots even without a usable player location. Their
serialized coordinates predate mounting; consumers locate them through the player, including
its dimension and coordinate availability. 26.3 ServerPlayer saves these compounds and places a
released bird at the player, while ShoulderRidingEntity saves then discards the world entity. The app
adoption is tracked separately in #74; this API is in v0.30.0 and entity-region reads remain region-only.
The CLI `creatures` command combines shoulder pets with region records in the selected dimension.
It prints the carrier's checked position and UUID separately from the saved owner, never the stale
mounting position. Player locations use vanilla dimension and coordinate rules without a separate
server-file policy. Unknown values remain unavailable; vanilla's Modded metadata remains. The
server-specific PlayerInfo APIs were removed in v0.31.0, a breaking change documented in README's migration note (fahlman/ChunkseeKit#90).

`Creature.health` and `maxHealth` use half-hearts. Maximum health reads saved attributes and
permanent modifiers; verified cat/parrot/wolf defaults cover exactly 26.1/4786, 26.1.1/4788,
26.1.2/4790, 26.2/4903 and 26.3/5023, with other pet defaults limited to 26.3/5023. Verified unowned wolves reset the loaded
base to 8; owned wolves retain the saved base, and an unidentified saved owner stays unavailable.
`Dimension.creatures(chunkX:chunkZ:)` retains the entity chunk's saved version, as the existing
per-region creature read does; raw `entities` remains unchanged.
Health Boost is included once through the permanent saved attribute modifiers. `EntityEquipment`
owns current slots and legacy player/creature equipment reading; `EquipmentHealth` selects applicable
equipped modifiers for both APIs. Empty/broken items, removed components and wrong-slot modifiers
do not contribute. Unsupported item/effect/active-enchantment defaults leave either maximum
unavailable. ItemStack shares current/wrapped/legacy enchantment parsing while keeping stored
book enchantments separate from equipped effects. The 43 vanilla 26.3 enchantment definitions
have no max-health effects; data packs overriding their IDs are not resolved. Maximums
use the game's Float precision. Pet appearance/order/collar/equipment interpretation
also belongs here. All new stored fields are optional, so older cached creatures still decode
but must be reread for the values. See README for format coverage and availability.

`PlayerInfo.activeEffects`, `maxHealth` and `mainHandItem` expose saved player details.
PlayerInfo, LevelInfo and Chunk keep their full saved NBT internal; typed accessors own its keys.
ItemStack likewise keeps its components internal, preserving typed accessors, raw-input initializers
and the existing Codable representation.
Chunk's block-entity list and lookup expose BlockEntity identity/position values rather than NBT.
They retain list order/count and first local-column match, including unavailable fields, using the
shared saved-position reader. The values are projected only when requested; a lookup stops at
its first match, so region scans do not materialize an unused list. The CLI consumes the typed ID; low-level region/NBT reads and
specialized container/sign/spawner readers remain available.
The public NBT-taking initializers and low-level NBT/region/compression APIs remain public. These
breaking boundary changes are available in v0.37.0, with the README migration note
(fahlman/Chunksee#214). Saved-data interpretation and cache versions are unchanged.
`PlayerInfo.equippedItems` owns equipment-plus-selected-main-hand composition, preserving the
explicit saved main hand's precedence and excluding unselected inventory. Player health consumes
that same collection. This additive API is available in v0.32.0; app adoption remains on #51.
`PlayerInventorySection` owns hotbar/storage/ender-chest slot ranges. `PlayerInfo.inventorySlots(in:)`
returns ordered optional items, retaining empty positions and the original saved item slot numbers.
The existing inventory filter and selected-hand reader use that owner too. Layout ignores
missing/out-of-section slot numbers and keeps the last readable item at a repeated slot, matching
the app's existing layout and the game's loaded inventory. The selected hand now uses that same
hotbar, correcting its first-item choice for duplicate slots; explicit saved main-hand equipment
still wins. Raw inventories remain unchanged. This additive
API is available in v0.32.0; Chunksee's numeric section layout adoption remains on #51.
Shared health arithmetic lives in `EntityHealth`; player maximum health includes applicable saved
equipment modifiers and Health Boost. Item durability defaults are owned by `VanillaItemDurability`,
checked against 26.3, with explicit overrides and unbreakable/removed components respected.
`Creature.uuid` is optional for cache/source compatibility and preserves individual identity.
`NBT.uuid` owns UUID strings, four-int arrays and the enclosing modern/legacy entity compounds.
Embedded singleplayer records, pet identities/owners and attribute-modifier replacement use that
reader, so a legacy Most/Least pair and a current array identify the same player or modifier.

`Villager` owns the missing-level default: a `VillagerData` compound with no `level` reads as 1,
verified against the 26.3 codec. Explicit values are retained, and malformed/absent data does not
invent a level. Consumers must rescan previously cached creatures to obtain the corrected value.
The computed `Villager.isUnemployed` owns the explicit `minecraft:none` profession category,
using Identifier's namespace and validation rules. Missing/empty/malformed values stay unknown;
nitwits and custom professions remain distinct. This is not a work/trade capability check. Raw
profession, Codable data and cache interpretation are unchanged. This additive API is available in v0.39.0;
the app's job-label adoption is tracked on #51.

`Villager.supportsTrading` owns the vanilla 26.3 trading-profession rule beside `isUnemployed`.
Saved readable offers establish trading first; otherwise the 13 vanilla trading professions
return true, `none`/`nitwit` false, and unknown/custom/malformed professions nil. Offers are
created lazily in the game, so their absence alone cannot rule out trading. The fact does not
claim current interaction readiness or resolve custom registries. It is an additive computed
API over existing fields, with no Codable or RegionFacts interpretation change. App adoption
and the Profession label follow a published release, tracked on fahlman/Chunksee#295 and #131.

`MapItem` owns banner positions: complete three-int arrays (verified in 26.3) and the existing
coordinate compounds. Omitted saved color/name remain optional; 26.3 omits white/unnamed defaults.
No map pixels or world files are changed when reading banners.

Modern world spawn and player death/respawn share `SavedBlockLocation`'s paired string-dimension
and integer-array position reader. World-spawn fields become available together; a partial modern
record never gains an inferred Overworld dimension. The existing dimension-tag normalization is
shared by player/map locations through an internal NBT accessor; legacy XYZ/number rules stay intact.

`SavedDate` owns Mojang's saved timestamp grammar for UserCache and AdvancementProgress. Its
private DateFormatter is fully configured once and never mutated by readers. Apple documents
modern DateFormatter as thread safe on 64-bit macOS, covering this Mac-only macOS 27 target:
https://developer.apple.com/documentation/foundation/dateformatter. No custom unchecked-concurrency
annotation or additional lock is used.

`PlayerStatistics.unit(of:in:)` owns scaled-statistic units, verified against 26.3 Stats and
StatFormatter. It recognizes vanilla general-statistic IDs and retains legacy play-time/diving
IDs; the latter share the time/distance formatters in the official 1.12.2 client. Damage scaling
is limited to verified data version 5023. Unknown or unscaled values remain raw. The existing
distances projection uses this owner instead of guessing from an arbitrary ID's suffix.
This additive API is available in v0.38.0; app names, locale, rounding and presentation stay in Chunksee,
with adoption on fahlman/Chunksee#298. No region-cache interpretation changes.

## Format sources

The format knowledge comes from the Minecraft Wiki pages *Java Edition level format*,
*Chunk format* and *Region file format*, checked on 2026-10-09. It was also checked against a
real 26.3 world (data version 5023): 314,171 chunks across three dimensions decoded with no
errors. Version-specific handling is listed in the README's "Format notes" table. A wiki entry
is a claim, so verify it against a real save before relying on it. The 26.4 per-block biome
change is covered only by synthetic tests.

## Build and test

Run from the repository root:

```sh
swift build
swift test
```

To build the command-line tool:

```sh
swift build -c release
```

The tool is then at `.build/release/chunksee`.

- **Required checks:** `swift build` and `swift test` must pass on the commit you publish.
  The tests need no Minecraft data.
- **Automated GitHub checks:** none exist. Ryan's projects run no hosted macOS CI, and the
  repository is private on a plan without branch protection. This was recorded on 2026-10-09;
  revisit it if the repository goes public.

## Releases

Ryan approved this process on 2026-10-09.

- A release is an annotated semantic-version tag on a commit that has been reviewed and merged
  to `main`:

  ```sh
  git tag -a vX.Y.Z -m '<summary>'
  git push origin vX.Y.Z
  ```

- Every tag needs Ryan's approval. Approval to merge is not approval to release.
- Before 1.0, the version number shows what changed:
  - Additive public API is a minor bump.
  - A breaking change is also a minor bump, but it must be named in the tag message. A breaking
    change includes adding a public enum case, because that breaks a downstream exhaustive
    `switch`.
  - Fixes that don't change the public API are a patch bump.
- Before tagging, run the required checks on the exact commit being tagged.
- Record the tag, its commit and the checks in the release's issue.
- Release order: tag ChunkseeKit first, then bump the Chunksee app's pin.
- The first release is `v0.1.0`, made after fahlman/ChunkseeKit#2 merges.

## Toolchain and platforms

Rechecked on 2026-10-18 against [Apple's releases](https://developer.apple.com/news/releases/),
[its SDK table](https://developer.apple.com/xcode/system-requirements), and the
[Swift releases](https://www.swift.org/install/macos/), then compared with the installed tools
and the project's settings. Xcode 27.2 and Swift snapshots are previews, not the stable toolchain.

- **Compiler:** Xcode 27.1 (`27A9275`) and Apple Swift 6.4 (`swiftlang-6.4.0.34.1`). The
  package requires `swift-tools-version: 6.4`.
- **Swift language mode:** 6, set explicitly with `swiftLanguageModes: [.v6]`.
- **SDK:** macOS 27.0 SDK. The package doesn't pin an SDK version.
- **Minimum macOS:** 27, set with `platforms: [.macOS(.v27)]`. The package is Mac only.
