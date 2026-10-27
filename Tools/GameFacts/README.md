# Code-only game facts

This is the release regeneration entrypoint for facts that Minecraft keeps in code rather
than save files, data packs, registries or language files. Do not copy game-content inventories
into the reader. Saved variant strings are read directly, without consulting this output.

The current categories are mob appearance, shared dye identities/texture RGB, enchantment
effect format associations, code-only item prototype facts needed by model selectors, and
registered block default properties, spawn-egg and block-item relationships, saved equipment attachment identities
and block seed methods, tints, fluid states, upper-face support, air flags, block entity renderer registrations, static special-item models
and profession trade-set associations, natural-spawn defaults, statistic formatter units, potion-color defaults,
absent block-light defaults, and non-block rendering definitions.
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
writes `DyeColor.swift`, `GeneratedMobAppearance.swift`, `GeneratedCreatureColors.swift`, `GeneratedEnchantmentEffects.swift`,
`GeneratedItemModelFacts.swift`, `GeneratedBlockDefaults.swift`, `GeneratedSpawnEggs.swift`, `GeneratedBlockItems.swift`,
`GeneratedEquipmentFacts.swift`, `GeneratedBlockModelSeeds.swift`, `GeneratedBlockTints.swift`, `GeneratedBlockFluids.swift`, `GeneratedAirBlocks.swift`, `GeneratedBlockEntityRenderers.swift`, `GeneratedSpecialItemModels.swift`, `GeneratedTradingFacts.swift`, `GeneratedMobSpawnFacts.swift`, `GeneratedNonBlockDefinitions.swift`, `GeneratedSaveRenames.swift`, and test-only `GeneratedSaveRenameProofs.swift`
plus `GeneratedLegacyChunkFacts.swift`, the test-only `GeneratedCreatureColorProofs.swift` and
`GeneratedLegacyChunkProofs.swift`, `GeneratedStatisticUnits.swift`, the test-only
`GeneratedStatisticUnitProofs.swift`, `GeneratedPotionColors.swift`, the test-only
`GeneratedPotionColorProofs.swift`, `GeneratedLightStorage.swift`, the test-only
`GeneratedLightStorageProofs.swift`, and `Tools/GameFacts/source.json`.
Use another new evidence directory with `--check` to regenerate and compare every output byte
without changing tracked files. Java compilation/extraction commands and logs, library hashes,
raw extracted JSON and generated copies stay in each evidence directory, including failed runs.
No world or installed game file is written. Run this only when the shared Mac is not reserved.

The extractor's original output is retained as `facts.raw.json` and `entity-types.raw.json`.
Their `facts.json` and `entity-types.json` counterparts use sorted JSON object keys before
`source.json` records their SHA-256 hashes. Object iteration order from the game's fixers is
not stable; array order and all values are preserved, so meaningful extraction changes still
fail `--check`. The focused provenance regression checks run with
`python3 -m unittest discover -s Tools/GameFacts -p 'test_*.py'`.

Sources and interpretation:

- `BlockLightSectionStorage.getLightValue` supplies the value for an absent block-light layer.
  A small subclass exposes the protected read on normally constructed empty storage; its chunk
  source is unused. The extractor verifies the same result at varied positive/negative block
  coordinates and emits those actual reads as test fixtures. It creates no world and performs
  no light propagation. SerializableChunkData's null/empty layer omission establishes the saved
  format association. This supplies no missing sky-light value and does not validate stale or
  malformed light data.

- `MobEffect.getColor` supplies effect RGB defaults; `Potion.getEffects` supplies base potion
  ingredients. Only visible ingredients contribute, as in `PotionContents.getColorOptional`.
  These built-in registries have no data-pack definitions for their colors/ingredients; potion
  tags describe membership, not these defaults. Independent `PotionContents.getColorOr` calls
  produce test-only expected colors for every base potion, base/custom mixture, single effect,
  weighted adjacent pair and hidden-particle pair. Registry order does not choose the pairs:
  the extractor sorts actual IDs first. No potion/effect ID list is maintained by hand.

- `Stats.makeCustomStat` registers each general statistic with its actual `StatFormatter`.
  The extractor matches formatter identity to DEFAULT, DISTANCE, TIME or DIVIDE_BY_TEN and
  fails on an unsupported formatter. The scale contracts are centimeters, ticks and tenths
  of a damage point; unscaled counts have no unit. Independent public `Stat.format` samples
  at 20, 100 and 155 become test-only proofs for every registered statistic. Historical unit
  queries reuse the existing generated statistic rename chain; saved values stay unchanged.
  No version gate or statistic-name suffix rule establishes a unit.

- `BlockEntityRenderers.PROVIDERS` and `BlockEntityType.isValid` identify blocks with a registered
  code renderer. Every registered state is independently checked by creating its actual block
  entity and looking up that entity's type, as the dispatcher does. If the block factory returns
  null because creation needs a world operation, the registered type factory supplies the entity;
  raw samples distinguish that narrower check. Generation fails if these
  paths disagree or if registration depends on state properties. These facts say nothing about
  saved entity presence, texture/model coverage or visibility; clients read those resources at runtime.

- `ColorLerper.Type.SHEEP.getColor` supplies the wool multiplier for each actual DyeColor,
  independently checked through `SheepRenderState.getWoolColor` with live animation disabled.
  It is not the raw dye texture multiplier. `AxolotlRenderer.TEXTURE_BY_TYPE` supplies adult
  variant texture IDs, checked through the real renderer's `getTextureLocation` with a baked
  vanilla model set and no world/window/GPU. The extracted entity ancestry assigns these code
  rules to their species. These facts identify color sources, not a complete entity picture;
  PNG bytes remain runtime resources, and clients own representative color sampling and UI contrast.
  Every mapping has a generated Swift test case from the game's actual method output.

- `ChunkHeightAndBiomeFix` supplies numeric biome-code meanings, geometry and omitted defaults;
  the default block is read from actual output. `ChunkStatusFix`/`ChunkStatusFix2` and
  `HeightmapRenamingFix` supply historical metadata rewrites. Repeated `ChunkDeleteLightFix`
  instances establish when light must be recomputed. Actual whole CHUNK upgrades prove spanning
  and aligned block/heightmap storage, horizontal/volume numeric biomes (including unknown and
  negative codes), omitted biome storage, uniform and wider palettes, embedded entities and
  block containers. The reader compares decoded saved blocks/biomes/heights and metadata rather
  than requiring identical serialized palette padding. These proofs omit loader-only generation
  context and describe the original saved build range; contextual below-zero regeneration remains
  separate #255 work. Runtime decoding has no Java dependency and never rewrites a save.

- `DataFixers` supplies its ordered `LegacyBlockRenameFix`, `ItemRenameFix` and biome
  `NamespacedTypeRenameFix` instances. Captured equality maps/strings and the class's literal
  string pool supply inputs; the real rename functions supply outputs and DataFix version keys
  supply applicability. Every emitted transition must also match the real fix chain across
  that boundary. Unsupported captures, subversions, empty steps or malformed IDs fail generation.
  The test-only proofs run the complete remaining game chain before/at each boundary and at
  the selected release. Additional chunk, entity, item, player and level examples compare the
  exposed names/counts, allowing unrelated game layout changes. `LevelDat.read` runs LEVEL;
  `LevelDatToSavedDataFileFix.extractPlayerDataToFile` then runs PLAYER using the embedded
  player's own DataVersion. String item IDs also use `ItemStackTheFlatteningFix.MAP/updateItem`
  before later aliases, including its saved Damage variant and zero fallback. The preceding
  `BedItemColorFix` is sampled for its original default variant; its identity comes from its
  class constants. All table entries and version boundaries have independent complete-game
  ITEM_STACK proofs. This prevents old grass blocks from being mistaken for newer short grass.
  `ItemIdFix` supplies its complete numeric-to-named item map, unknown-number fallback and
  applicability boundary. Every entry and absent-number probes run through the real ITEM_STACK
  boundary upgrade; the test suite composes that result with the existing named-item pipeline.
  Additional ordinary variant and player-inventory records compare the complete remaining
  game upgrade. Numeric tags use the same Java Number.intValue codec as the game. This only
  restores numeric identities: field-sensitive potion/spawn-egg/banner conversions, numeric
  blocks and other identifier/field formats remain separate adapters. Nothing writes a world.
  This does not implement every data-fixer class;
  those remain on #255. These rename facts are not registry membership lists.

- `SimplestEntityRenameFix` and `BlockEntityRenameFix` supply namespaced record aliases.
  The extractor calls their actual name functions over input-schema choices, verifies the real
  boundary upgrade, then records complete-chain results at every schema interval. Only changed
  names and their first applicable schema boundaries are emitted; these are rewrite facts, not
  a list of types the reader admits. Unknown records remain readable and unchanged. Whole-record
  proofs use ENTITY_TREE for passengers and PLAYER for shoulder/root-vehicle snapshots, plus
  spawn-egg and spawner records. Pre-namespace aliases need the earlier field-dependent entity
  splits and remain in the older-format slice; type-changing fixes are not inferred from an ID.

- `AttributesRenameLegacy` and `AttributesRenameFix` provide ordered attribute-name functions.
  Their captured maps/strings and class constants supply finite aliases. `AttributeIdPrefixFix`
  supplies its actual PREFIXES and replacement results, preserving its namespace handling and
  operation order for arbitrary names. `RenameEnchantmentsFix` supplies its alias map. Whole
  PLAYER and ITEM_STACK records are passed through the full game chain before/at each boundary
  and at the selected release, covering legacy attributes and both item-component layouts.
  These are identity rewrites, not attribute or enchantment membership lists. Modifier IDs,
  labels, numbers and unrelated fields stay unchanged; field/layout conversions remain separate.

- Recipe `NamespacedTypeRenameFix`, `AdvancementsRenameFix`/`AdvancementsFix` and
  `StatsRenameFix` supply player-progress identities. Captured maps/strings and both the
  registration and concrete fix classes' constants supply their inputs. Advancement aliases
  retain literal versus default-namespace behavior from the actual function. Every alias has
  full PLAYER/ADVANCEMENTS/STATS proofs before/at its boundary and at the selected release,
  including omitted-namespace spellings. Namespaced recipe/statistic identities compare by
  their resource IDs; an otherwise untouched spelling is retained by the reader. Criteria,
  dates, counts and recipe order remain data. Furnace recipe-use field conversions, older
  statistics formats and scoreboard criteria are separate #255 work.

- `BlockStateDefinitions.STATIC_DEFINITIONS` supplies synthetic rendering-only definition IDs.
  Registered blocks take precedence in definitionLocationToBlockStateMapper, so the extractor
  removes any such ID that has become a real block. It verifies mapper identity for the remaining
  exceptions. Blockstate-file contents and the registered-block inventory are never bundled;
  the reader uses file presence only as resource evidence, not as a live registry authority.
- `EnvironmentAttributes.NATURAL_MOB_SPAWNS.defaultValue` supplies the static default candidates,
  including known empty defaults. `Weighted.codec(MapCodec)` is probed for an omitted weight;
  if the game requires one, the reader leaves an unreadable/missing weight unknown. The tool
  records only these code facts. Dimension and biome contents are always read at runtime.
  `MobSpawnSettingsModifier.overlay` establishes replacement of named categories, including
  empty ones, and inheritance of unmentioned categories; it is not a list append operation.
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

- Block.asItem supplies the inventory item for each block, checked against Item.byBlock.
  Its no-item AIR result is omitted rather than treated as an inventory picture. The code's
  BlockItem and StandingAndWallBlockItem registrations establish differently named block/item
  pairs; resource filenames do not. Runtime lookup requires that item's readable definition
  in the selected jar. No no-item or custom-block catalog is generated, and the relationship
  is never used to determine block existence. Saved properties do not change this code lookup.

- SaddleEquipmentSlotFix.fixEntityWithSaddleFlag supplies the item/count represented by the
  old saved `Saddle` boolean. AbstractChestedHorse.mobInteract establishes Items.CHEST as the
  attached `ChestedHorse` item. These identities are extracted rather than copied into the reader;
  saved item compounds still supply their own IDs. A changed saddle shape fails generation for
  inspection. No species capability catalog is generated or needed for these saved fields.


- BlockState.getSeed supplies the position offset for every registered state. The adapter names
  BlockBehaviour, AbstractBedBlock, DoorBlock and DoublePlantBlock method formats; new method
  implementations fail generation for inspection. Actual inherited method ownership supplies
  each block's format, and direct calls determine its offsets. Four positions include opposite
  signed-coordinate boundaries; every candidate must have a unique matching adjacent offset.
  The raw evidence includes all checked blocks/states and official LegacyRandomSource weighted
  choices. No block IDs or offsets are hand-kept. These facts do not establish block existence.
  Resource selectors cannot replace them: changing a bed picture's selectors leaves its code's
  seed behavior unchanged. Unknown methods still allow deterministic models and overview parts.

- BlockColors.createDefault supplies each block's actual tint-source registrations. The extractor
  calls BlockTintSource.colorInWorld for every registered state. A recording BlockAndTintGetter
  proxy identifies the actual BiomeColors resolver and vertical offset; two marker colors must
  pass through unchanged, while fixed colors must make no world query. Other operations fail
  generation. The tool checks the source's relevantProperties against every state, then removes
  particle-only dependencies that do not affect in-world colors. ModelBlockRenderer.computeTintColor
  supplies the result for an index without a source. Known empty registrations are distinct from
  unknown block code; neither is used to decide existence or picture availability. Raw samples
  retain official method results for public-API verification. No color formulas or block IDs
  are maintained by hand, and the generated facts have no runtime version gate.

- BlockState.isAir supplies the code flag initialized from BlockBehaviour.Properties.isAir.
  Every registered state is checked against Heightmap.NOT_AIR and its block's default flag;
  a changed predicate or new state-dependent format fails generation for inspection. The air
  tag stays runtime data for consumers that need tag membership, but cannot replace this
  surface-height rule. Missing code flags remain unknown; there is no manually maintained list.

- BlockState.getFluidState supplies every registered state's contained fluid identity or known
  emptiness. Membership in the water tag is not generated; the caller supplies that composed
  runtime tag. BlockState.isFaceSturdy(UP), used by MapItem.getCorrectStateForFluidBlock, supplies
  the independent full upper-face support fact. A BlockGetter proxy refuses world queries, so
  a shape needing neighbors or block entities remains unknown rather than using an empty world.
  Every possible state is sampled. Properties are removed from each result only when all
  registered combinations prove them irrelevant; this keeps unrelated saved errors independent.
  The shared generated block defaults supply omitted properties at runtime. These facts are not
  an existence catalog, texture-coverage estimate, fluid simulation or version gate.

- LayerDefinitions and the game's special-renderer model builders supply baked model polygons,
  UVs, skin dimensions and static inventory poses. The extractor calls each supported model's
  actual setupAnim method, walks its transformed ModelPart tree and records the original and
  posed vertices. Skull kinds and copper-statue poses come from their enums; skin IDs come from
  the game's texture owners. The shulker box uses its own renderer model, not the entity model.
  Generated cuboids must reproduce every posed vertex and UV rectangle; unsupported transforms,
  scales or UV layouts fail generation. Ground/wall banner parts retain cloth/support material
  roles, and decorated-pot sides retain their named sides for runtime pattern resolution.
  No artwork or item definitions are generated. Runtime selection and materials still come from
  the supplied jar and saved components, with no game-version gate.

Generated entries name these sources, and `source.json` records the release, client/tool hashes
and extracted-output hashes. Missing/ambiguous classes or mappings fail generation visibly.
Inspect the diff before committing; a real save-format change may need an adapter change, while
new enum values flow through the tool. The public `DyeColor` enum also requires normal API review
if the game adds a color. Check the committed Swift output with the repository's required build
and test commands before publishing it.

- BuiltInRegistries.VILLAGER_PROFESSION exposes each profession's `tradeSetsByLevel` map.
  Every registered link is checked against `getTrades`, which Villager.updateTrades calls for
  the current level. VillagerData supplies its minimum-level clamp, checked at integer boundaries.
  Only this code association (including empty maps) is generated. Trade sets, their candidate
  tags and trade definitions are read at runtime, not inferred from folder names or copied
  from the jar. The public query describes potential trading, not rolled or currently usable offers.

Portal travel facts are extracted by ExtractPortalFacts through the JDK class-file API and
actual game fields. It verifies the NetherPortalBlock dimension-selection instruction format,
extracts PortalForcer search radii, DimensionType coordinate-scale codec bounds, and WorldBorder
clamp margin, absolute limit and default size. Dimension scale values and saved borders remain
runtime inputs. A changed code format fails regeneration for inspection; no version gate or
dimension registry is generated.
