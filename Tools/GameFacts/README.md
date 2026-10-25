# Code-only game facts

This is the release regeneration entrypoint for facts that Minecraft keeps in code rather
than save files, data packs, registries or language files. Do not copy game-content inventories
into the reader. Saved variant strings are read directly, without consulting this output.

The current categories are mob appearance and the shared dye identities/texture RGB.
The rest of the migration is tracked on fahlman/ChunkseeKit#222. This tool is used during
development/release preparation; ChunkseeKit has no Java or new package dependency at runtime.

Pass the Minecraft installation, its Java home, a **new** evidence directory, and an installed
stable release ID:

```sh
python3 Tools/GameFacts/regenerate.py "$MINECRAFT_DIR" "$MINECRAFT_JAVA" "$EVIDENCE_DIR" "$RELEASE_ID"
```

The tool checks the client SHA-1 against the launcher's download metadata and rejects snapshots.
It compiles the extractor, bootstraps the official registries without creating a world, and
writes `DyeColor.swift`, `GeneratedMobAppearance.swift` and `Tools/GameFacts/source.json`.
Use another new evidence directory with `--check` to regenerate and compare every output byte
without changing tracked files. Java compilation/extraction commands and logs, library hashes,
raw extracted JSON and generated copies stay in each evidence directory, including failed runs.
No world or installed game file is written. Run this only when the shared Mac is not reserved.

Sources and interpretation:

- `DyeColor.getId`, `getSerializedName` and `getTextureDiffuseColor` supply dye identities and
  the texture multiplier used by banners/shields, collars and sheep.
- Axolotl, Parrot and Llama `Variant`, and equine `Variant`, supply `getId`/`getSerializedName`.
  Equine `Markings` has no serialized name; its enum symbols supply engine keys. `NONE` is
  represented by absent markings. Horse's saved integer packs coat and markings into bytes.
- Each class's `addAdditionalSaveData` establishes the saved field: `Variant` for those animals,
  `Color` for sheep. The adapters name formats/classes; IDs are derived from the actual entity
  registry and inheritance via the existing `Tools/EntityTypes` extractor.
- Legacy `CatType` integer keys come from the game's `EntityVariantFix` conversion map.
  The game then runs the complete data-fix chain for each key through the selected release,
  preserving later registry-ID renames. There is no copied alias table.
- Rabbit `Variant.id`/`getSerializedName` supply `RabbitType` codes, including noncontiguous IDs.
- TropicalFish `Pattern.getPackedId`/`getSerializedName` supply the low 16 bits of saved
  `Variant`; `Base.id` and code symbols supply its low-byte body shape. `packVariant`,
  `getBaseColor` and `getPatternColor` establish dye bytes 16–23 and 24–31. Each part is read
  independently, including a signed packed integer with an uninterpretable color byte.
- Fox and MushroomCow `addAdditionalSaveData` establish that their `Type` string is an
  appearance. Only their class/field association is generated; string values are not listed.
- Panda `Gene.getSerializedName`, `isRecessive` and `NORMAL` supply the code-only dominance
  facts. The reader follows `getVariantFromGenes` and retains MainGene/HiddenGene strings
  independently, including unknown genes. Villager style reuses the existing VillagerData
  reader and needs no generated table.

Generated entries name these sources, and `source.json` records the release, client/tool hashes
and extracted-output hashes. Missing/ambiguous classes or mappings fail generation visibly.
Inspect the diff before committing; a real save-format change may need an adapter change, while
new enum values flow through the tool. The public `DyeColor` enum also requires normal API review
if the game adds a color. Check the committed Swift output with the repository's required build
and test commands before publishing it.
