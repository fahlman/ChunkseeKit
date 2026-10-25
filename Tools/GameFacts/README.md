# Code-only game facts

This is the release regeneration entrypoint for facts that Minecraft keeps in code rather
than save files, data packs, registries or language files. Do not copy game-content inventories
into the reader. Saved variant strings are read directly, without consulting this output.

The current categories are mob appearance, shared dye identities/texture RGB, enchantment
effect format associations, code-only item prototype facts needed by model selectors, and
registered block default properties, spawn-egg relationships and saved equipment attachment identities.
Enchantment IDs/contents and item-model definitions are always read at runtime from data.
The rest of the migration is tracked on fahlman/ChunkseeKit#222. This tool is used during
development/release preparation; ChunkseeKit has no Java or new package dependency at runtime.

Pass the Minecraft installation, its Java home, a **new** evidence directory, and an installed
stable release ID:

```sh
python3 Tools/GameFacts/regenerate.py "$MINECRAFT_DIR" "$MINECRAFT_JAVA" "$EVIDENCE_DIR" "$RELEASE_ID"
```

The tool checks the client SHA-1 against the launcher's download metadata and rejects snapshots.
It compiles the extractor, bootstraps the official registries without creating a world, and
writes `DyeColor.swift`, `GeneratedMobAppearance.swift`, `GeneratedEnchantmentEffects.swift`,
`GeneratedItemModelFacts.swift`, `GeneratedBlockDefaults.swift`, `GeneratedSpawnEggs.swift`,
`GeneratedEquipmentFacts.swift`
and `Tools/GameFacts/source.json`.
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
- EnchantmentEffectComponents' declared generic types associate registered component IDs with
  attribute, conditional-effect, numeric, unit and sound codecs. Registered entity/location
  effect codecs are matched by identity to the format-adapter classes. Attribute and all-of
  effects are interpreted; arbitrary RunFunction behavior stays unavailable. Other supported
  effect classes' apply/onChangedBlock methods do not add unsaved attribute modifiers.
  ApplyMobEffect uses MobEffect.addAttributeModifiers/addPermanentModifier: its attributes
  are already retained in the entity save. Generated entries name the exact classes/fields.
  A new unmapped code format fails generation instead of being silently treated as harmless.
  No enchantment definition or ID membership is copied into this output.
- Item.components supplies prototype component presence and the BLOCK_STATE/CHARGED_PROJECTILES
  defaults that item-model selectors need when the save omits them. The game's
  DataComponentInitializers bind these code defaults after VanillaRegistries.createWorldLookup;
  this builds a registry lookup, not a world. Identical prototypes share one generated value.
  ItemBlockState, HasComponent, Broken and Charge establish selection semantics. Charge's
  FIREWORK_ROCKET identity and CrossbowItem.ChargeType strings are extracted, not hand-copied.
  No item-model definitions or pictures are bundled. Arbitrary component value equality is
  not claimed from presence: ignore_default remains unknown for an explicit value whose
  prototype also has that component, since the game sanitizes equal values out of its patch.
- BuiltInRegistries.BLOCK supplies each block's actual defaultBlockState. Property.getName and
  BlockState.getValue serialize its default property names/values. Resource blockstate files
  enumerate choices but do not designate a default, as the #227 investigation established.
  Empty defaults need no generated entry; identical dictionaries share one value. Every group
  names the code source, and raw extracted facts retain each block's concrete class. This is
  not an existence catalog or a legal-value validator. Saved properties win; unknown IDs and
  properties remain unknown, while property-independent resource choices need no default.
  Generated defaults are available for any parseable asset version. Updating them requires
  this same release command, with no version-specific copy or hand-edited block list.
- SpawnEggItem.byId queries registered item ENTITY_DATA for a matching TypedEntityData.type.
  It supplies the entity-to-egg relationship after item prototypes are bound; neither a name
  suffix nor an item-picture definition establishes that fact. The extractor records its
  actual result for each entity, checking that a returned item is a SpawnEggItem. No explicit
  no-egg or custom-entity list is generated. Runtime lookup also requires a readable item
  definition in the supplied jar; model support and picture rendering remain separate.

- SaddleEquipmentSlotFix.fixEntityWithSaddleFlag supplies the item/count represented by the
  old saved `Saddle` boolean. AbstractChestedHorse.mobInteract establishes Items.CHEST as the
  attached `ChestedHorse` item. These identities are extracted rather than copied into the reader;
  saved item compounds still supply their own IDs. A changed saddle shape fails generation for
  inspection. No species capability catalog is generated or needed for these saved fields.

Generated entries name these sources, and `source.json` records the release, client/tool hashes
and extracted-output hashes. Missing/ambiguous classes or mappings fail generation visibly.
Inspect the diff before committing; a real save-format change may need an adapter change, while
new enum values flow through the tool. The public `DyeColor` enum also requires normal API review
if the game adds a color. Check the committed Swift output with the repository's required build
and test commands before publishing it.
