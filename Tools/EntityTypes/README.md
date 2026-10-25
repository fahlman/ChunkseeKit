# Verifying Minecraft's saved mob format

The reader follows Ryan's rule: **read, interpret, display**. Minecraft's `Mob` serializer
always writes `CanPickUpLoot`, `PersistenceRequired` and `LeftHanded` as booleans, including
false values. These fields establish a saved mob record. `Health` is shared with non-mobs
and does not. An ID absent from a built-in list is not a reason to suppress readable data.
The production reader therefore has no mob list or catalog of game versions to maintain.

This directory contains optional source-verification tools, not runtime dependencies or
production data generators. Normal builds/tests need neither Minecraft nor Java.

`ExtractEntityTypes.java` boots the official registries without opening a world or game
window, resolves each registered `EntityType<T>` declaration and records its actual Mob
ancestry. It fails on unaccounted entries, unresolved declarations or aliases. These facts
serve as an independent check of the real-world reader; they are never shipped as a catalog.

`verify.py` checks the installed client jar's download SHA-1, collects that class evidence,
and saves `javap` output for Mob. Specify whichever installed versions are being checked;
there is no built-in version inventory. For example:

```sh
python3 Tools/EntityTypes/verify.py "$MINECRAFT_DIR" "$MINECRAFT_JAVA_HOME" \
  "$NEW_EVIDENCE_DIR" 26.3 26.4-snapshot-5
```

The evidence directory must be new. Every command, jar hash, registry JSON and tool log is
retained, including failed attempts. The supplied Java runtime must support the chosen jars.
Inspect `addAdditionalSaveData` in each version's `2.log`: the three unconditional
`putBoolean` calls belong to Mob, whereas NoAI and several other fields are optional.
The format was checked against official 26.1, 26.1.1, 26.1.2, 26.2, 26.3 and Snapshot 5 code;
these checks do not become a version restriction in the reader.

After the normal Release build, the public decoder can be checked against every registered
class using its saved record shape. Both health-present and health-absent cases are checked;
ownership alone is insufficient for non-mobs. This Mac's SwiftPM/Xcode output paths are:

```sh
xcrun swiftc -O -swift-version 6 -parse-as-library \
  -I .build/out/Products/Release -I Sources/CZlib \
  Tools/EntityTypes/VerifyEntityTypes.swift .build/out/Products/Release/libChunkseeKit.a \
  -o "$NEW_EVIDENCE_DIR/verify-entity-types"
"$NEW_EVIDENCE_DIR/verify-entity-types" \
  5023 "$NEW_EVIDENCE_DIR/26.3/entity-types.json" \
  5125 "$NEW_EVIDENCE_DIR/26.4-snapshot-5/entity-types.json" \
  nil "$NEW_EVIDENCE_DIR/26.3/entity-types.json" \
  999999 "$NEW_EVIDENCE_DIR/26.4-snapshot-5/entity-types.json"
```

A separate copied-world comparison checks the actual saved fields against the extracted
class ancestry, not just synthetic shapes. Original/copy hashes are checked afterward.
The reader retains new or modded IDs with the same saved format and preserves their readable
facts; it does not grant missing health defaults or simulate entity loading. Incomplete or
hand-edited records without these fields cannot establish mob membership. A record deliberately
given the mob format is interpreted as such; raw entity APIs preserve every record.
