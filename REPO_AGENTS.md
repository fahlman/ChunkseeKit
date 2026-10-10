# MCWorldKit — Repository Instructions

Read with the shared `AGENTS.md`. Project record: fahlman/MCWorldKit#1.

## Project

MCWorldKit is the engine for reading Minecraft: Java Edition world saves. Ryan intends to
open-source it so others can build their own GUIs on it. It owns the file formats and nothing
else: NBT, Anvil region files, chunk decoding, and the world-folder layout. It has no UI and no
app code. The Mac app **MCWorld** (`com.fahlsing.MCWorld`) will live in its own repository and
depend on this package, the way Euchre depends on EuchreKit. Dependency direction:
**MCWorld app → MCWorldKit**.

- **Kind:** Swift package (a library plus a command-line tool). It is not a Mac app, so it has
  no `.xcodeproj`.
- **Products:**
  - `MCWorldKit`, the library.
  - `mcworld`, a command-line tool that inspects a world and decodes every chunk (`scan`). It
    uses only the library's public API and serves as a working example for GUI authors.
- **License:** MIT (`LICENSE`).
- **Dependencies:** Foundation, plus the system zlib through the `CZlib` module map. There are
  no package dependencies, so there is no `Package.resolved` to track (it is git-ignored).

## Modules

| Module | Owns | May depend on |
|---|---|---|
| `CZlib` | Module map for the system `libz` | — |
| `MCWorldKit` | `NBT` (read/write, modified UTF-8), `Compression` (zlib/gzip, LZ4 block streams), `RegionFile`, `Chunk`/`ChunkSection`/`PalettedContainer`/`BlockState`, `World`/`Dimension`/`LevelInfo` | Foundation, `CZlib` |
| `mcworld` | Command-line presentation only | `MCWorldKit` |
| `MCWorldKitTests` | Tests built on synthetic worlds (`Fixtures.swift`) | `MCWorldKit`, `CZlib` |

The library only reads world files. Apart from the NBT writer, which tests and tools use to
build fixtures, it never writes into a world folder.

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

The tool is then at `.build/release/mcworld`.

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
- Release order: tag MCWorldKit first, then bump the MCWorld app's pin.
- The first release is `v0.1.0`, made after fahlman/MCWorldKit#2 merges.

## Toolchain and platforms

On 2026-10-09 these were verified as the newest non-beta releases on Apple's and Swift's release
pages, then compared with what this Mac uses.

- **Compiler:** Xcode 27.0 (`27A266a`) and Apple Swift 6.4 (`swiftlang-6.4.0.34.1`). The
  package requires `swift-tools-version: 6.4`.
- **Swift language mode:** 6, set explicitly with `swiftLanguageModes: [.v6]`.
- **SDK:** macOS 27.0 SDK. The package doesn't pin an SDK version.
- **Minimum macOS:** 27, set with `platforms: [.macOS(.v27)]`. The package is Mac only.
