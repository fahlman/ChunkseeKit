# ChunkseeKit — Repository Instructions

Read with the shared `AGENTS.md`. Project record: fahlman/ChunkseeKit#1.

## Project

ChunkseeKit is the engine for reading Minecraft: Java Edition world saves. Ryan intends to
open-source it so others can build their own GUIs on it. It owns the file formats and nothing
else: NBT, Anvil region files, chunk decoding, and the world-folder layout. It has no UI and no
app code. The Mac app **Chunksee** (`com.fahlsing.Chunksee`, fahlman/Chunksee) lives in its own
repository and depends on this package, the way Euchre depends on EuchreKit. Dependency direction:
**Chunksee app → ChunkseeKit**. Both were renamed from MCWorld and MCWorldKit on 2026-10-10
(fahlman/Chunksee#75).

- **Kind:** Swift package (a library plus a command-line tool). It is not a Mac app, so it has
  no `.xcodeproj`.
- **Products:**
  - `ChunkseeKit`, the library.
  - `ChunkseeKitTestSupport`, synthetic save builders for test targets, using the reader's public
    NBT and compression APIs. This additive product is introduced in v0.35.0; app adoption
    follows that release, tracked on #82.
  - `chunksee`, a command-line tool that inspects a world and decodes every chunk (`scan`). It
    uses only the library's public API and serves as a working example for GUI authors.
- **License:** MIT (`LICENSE`).
- **Dependencies:** Foundation, plus the system zlib through the `CZlib` module map. There are
  no package dependencies, so there is no `Package.resolved` to track (it is git-ignored).

## Modules

| Module | Owns | May depend on |
|---|---|---|
| `CZlib` | Module map for the system `libz` | — |
| `ChunkseeKit` | `NBT` (read/write, modified UTF-8), `Compression` (zlib/gzip, LZ4 block streams), `RegionFile`, `Chunk`/`ChunkSection`/`PalettedContainer`/`BlockState`, `World`/`Dimension`/`LevelInfo` | Foundation, `CZlib` |
| `chunksee` | Command-line presentation only | `ChunkseeKit` |
| `ChunkseeKitTestSupport` | Shared synthetic section, chunk, region, UUID and file builders (`Fixtures.swift`); packing stays independent of the decoder | Foundation, `ChunkseeKit` |
| `ChunkseeKitTests` | Tests built with the public fixture builders; `CLIFixtures.swift` locates and launches the CLI built beside the test bundle | `ChunkseeKit`, `ChunkseeKitTestSupport`, `CZlib` |

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
gain verified health defaults. POI, map banners and paired block locations share the int-array
reader; only map banners retain their existing legacy coordinate-compound fallback. Chunk,
containers, signs and spawners share modern block-entity list/position readers. This adds no
legacy terrain support. These public APIs are available starting in v0.30.0.
The CLI structure scan uses `Chunk.isFullyGenerated` and `structureStarts` after skipping
unneeded block data; it does not apply its own chunk-status or placement rules. Structure-center
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

`DimensionType` owns validated build bounds, logical height and the ceiling flag.
`World.dimensionTypes()` follows saved dimension-to-type links in modern world-generation data
or legacy inline settings. Enabled folder packs resolve in reverse priority order; the four vanilla
definitions are verified for 26.3/5023. Missing, malformed or unresolved values remain absent.
ZIP/experimental packs, overlays and filters are not resolved, so an unsupported higher-priority
pack blocks lower fallbacks. This narrow reader does not infer types from dimension IDs, infer roof
Y from logical height, load a complete game registry, or cache metadata. Path checks keep reads
within the selected pack; file-read failures propagate. The fields, bounds and pack priority were
checked against the official 26.3 DimensionType/LevelStem codecs and resource manager; the saved
mapping was checked in the committed ChunkseeTestWorld 26.3 metadata. This additive API is
introduced for v0.33.0, with app adoption on fahlman/Chunksee#248 and shared ownership on #51.

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
The public NBT-taking initializers and low-level NBT/region/compression APIs remain public. This unreleased breaking boundary change
requires the next minor release and a migration note; it is not in v0.36.0 (fahlman/Chunksee#214).
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
