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
| `ChunkseeKitTests` | Tests built on synthetic worlds (`Fixtures.swift`) | `ChunkseeKit`, `CZlib` |

The library only reads world files. Apart from the NBT writer, which tests and tools use to
build fixtures, it never writes into a world folder.

`Creature.health` and `maxHealth` use half-hearts. Maximum health reads saved attributes and
permanent modifiers; only verified 26.3/data-version-5023 pet defaults fill an omitted attribute.
Health Boost is included once through the permanent saved attribute modifiers. Custom equipment
that changes maximum health leaves the maximum unavailable rather than report an incomplete
total. Maximums use the game's Float precision. Pet appearance/order/collar/equipment interpretation
also belongs here. All new stored fields are optional, so older cached creatures still decode
but must be reread for the values. See README for format coverage and availability.

`PlayerInfo.activeEffects`, `maxHealth` and `mainHandItem` expose saved player details. Shared
health arithmetic lives in `EntityHealth`; player maximum health includes applicable saved
equipment modifiers and Health Boost. Item durability defaults are owned by `VanillaItemDurability`,
checked against 26.3, with explicit overrides and unbreakable/removed components respected.
`Creature.uuid` is optional for cache/source compatibility and preserves individual identity.

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

On 2026-10-09 these were verified as the newest non-beta releases on Apple's and Swift's release
pages, then compared with what this Mac uses.

- **Compiler:** Xcode 27.0 (`27A266a`) and Apple Swift 6.4 (`swiftlang-6.4.0.34.1`). The
  package requires `swift-tools-version: 6.4`.
- **Swift language mode:** 6, set explicitly with `swiftLanguageModes: [.v6]`.
- **SDK:** macOS 27.0 SDK. The package doesn't pin an SDK version.
- **Minimum macOS:** 27, set with `platforms: [.macOS(.v27)]`. The package is Mac only.
