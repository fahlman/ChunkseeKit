# Verified mob types

Ryan's rule is **WWMD: What Would Minecraft Do?** Minecraft resolves a saved entity's
`id` through its entity-type registry. The corresponding Java class determines whether
it is a `Mob`. `Health` and ownership do not establish that identity. Registered non-mobs
remain excluded even when an edited save gives them mob-like fields.

`ExtractEntityTypes.java` boots the official built-in registries without opening a world
or game window. It pairs every registered entity type with the concrete class declared
by its `EntityType<T>` constant, then asks Java whether that class extends `Mob`.
The constants live in `EntityType` in 26.1 and `EntityTypes` from 26.2. Extraction fails
on unaccounted-for entries, unresolved generic declarations or aliases. It records each
type's ID, declared class, full ancestry and membership, including all excluded types.

`generate.py` checks each installed client jar against the download SHA-1 in its launcher
metadata, runs the extractor, checks agreement for shared IDs across versions, and
generates `Sources/ChunkseeKit/MobTypes.swift`. No hand-maintained mob list, Java runtime
dependency, game artwork or world data is included in the library.

Run from the repository root, supplying the Minecraft installation, JDK home and a **new**
evidence directory. The installed versions must include 26.1, 26.1.1, 26.1.2, 26.2, 26.3
and 26.4-snapshot-5, with their launcher libraries. Java 25 is required by these jars.

```sh
python3 Tools/EntityTypes/generate.py "$MINECRAFT_DIR" "$MINECRAFT_JAVA_HOME" "$NEW_EVIDENCE_DIR"
```

The default checks the committed Swift output without changing it. Add `--write` to
regenerate it. Commands, hashes, registry JSON and stdout/stderr are retained in the
new evidence directory, including failed attempts. This is an optional source-verification
tool; normal `swift build` and `swift test` require neither Minecraft nor Java.

After the package's normal Release build, compare its public decoder with every registry
entry, including all non-mobs. This Mac's SwiftPM/Xcode build uses the paths below:

```sh
xcrun swiftc -O -swift-version 6 -parse-as-library \
  -I .build/out/Products/Release -I Sources/CZlib \
  Tools/EntityTypes/VerifyEntityTypes.swift .build/out/Products/Release/libChunkseeKit.a \
  -o "$NEW_EVIDENCE_DIR/verify-entity-types"
"$NEW_EVIDENCE_DIR/verify-entity-types" \
  4786 "$NEW_EVIDENCE_DIR/26.1/entity-types.json" \
  4788 "$NEW_EVIDENCE_DIR/26.1.1/entity-types.json" \
  4790 "$NEW_EVIDENCE_DIR/26.1.2/entity-types.json" \
  4903 "$NEW_EVIDENCE_DIR/26.2/entity-types.json" \
  5023 "$NEW_EVIDENCE_DIR/26.3/entity-types.json" \
  5125 "$NEW_EVIDENCE_DIR/26.4-snapshot-5/entity-types.json" \
  nil "$NEW_EVIDENCE_DIR/26.3/entity-types.json" \
  5124 "$NEW_EVIDENCE_DIR/26.3/entity-types.json" \
  9999 "$NEW_EVIDENCE_DIR/26.3/entity-types.json"
```

Every entry is checked with health present and absent, while ownership and mob-like
AI fields are present in both. The last three inputs check the approved 26.3 fallback.

Verified catalogs have 89 mobs in 26.1/26.1.1/26.1.2, 90 in 26.2/26.3, and 91 in
Snapshot 5. The additions are Sulfur Cube in 26.2 and Frostbite in Snapshot 5. The game
registers Giant and Illusioner as mobs even though they have no ordinary spawning route.
Players and armor stands inherit from `LivingEntity` but not `Mob`; items and experience
orbs inherit directly from `Entity`.

Missing or unverified saved versions use the 26.3 catalog: Minecraft resolves known IDs
through its own registry when reading other versions. Exact verified versions use their
own catalog. Neither grants unverified health defaults.

Ryan's follow-up on PR #221 asks Chunksee to display unfamiliar mobs too. Both the official
26.3 and Snapshot 5 `Mob.addAdditionalSaveData(ValueOutput)` unconditionally write
`CanPickUpLoot`, `PersistenceRequired` and `LeftHanded` via `putBoolean`. Optional fields
such as `NoAI` are not enough. The reader retains an unfamiliar ID only when all three
booleans are readable, including false, and marks its `isRecognizedType` false. This is
evidence from the saved mob format, not a verified class identity. Known non-mobs always
remain excluded. The generated catalog includes them so these cases stay distinct.

To reproduce the save-format check, use the same hash-checked client classpath in the
version's `commands.json` and run the JDK's `javap -c -p -classpath "$CLASSPATH" \
net.minecraft.world.entity.Mob`. Inspect `addAdditionalSaveData` and its three unconditional
`putBoolean` calls. The source checks for this change are retained under
`/Users/ryan/Developer/ChunkseeKit-runs/mob-classification-evidence/unknown-mob-source`.

Raw entity APIs keep every record. Missing health remains unavailable rather than
suppressing a recognized mob or inventing a saved value. These choices are recorded on
fahlman/ChunkseeKit#220 and the Claude-F221-2 review finding on #221.
