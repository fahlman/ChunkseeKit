# Item models do not establish default block states

Report for [Kit #227](https://github.com/fahlman/ChunkseeKit/issues/227), 2026-10-25.
Recommendation: retain Minecraft's actual default states and bring their mechanical extraction
into the single release tool on #222. Do not substitute inventory models for unknown block
states. Ryan's decision is required before changing product behavior.

## What was compared

The official registry supplied every property-bearing block's actual default state. Original
blockstate JSON selected its models. For each plain item definition, the same original model
and texture bytes were also drawn as an unrotated block. Both went through Chunksee's production
`topColor` and `topTexture` functions, using identical white tint. All weighted default choices
were checked; matching one possible picture is insufficient.

| Release and category | Blocks | Comparable top projections | Same average color | All close-up pixels identical |
|---|---:|---:|---:|---:|
| 26.3: same models, no rotations | 280 | 280 | 280 | 280 |
| 26.3: same models, rotated | 136 | 136 | 134 | 109 |
| 26.3: different models | 279 | 89 | 29 | 22 |
| 26.3: no item | 107 | 0 | — | — |
| 26.3: non-plain item definition | 82 | 0 | — | — |
| 26.2: same models, no rotations | 237 | 237 | 237 | 237 |
| 26.2: same models, rotated | 102 | 102 | 100 | 75 |
| 26.2: different models | 272 | 86 | 27 | 21 |
| 26.2: no item | 105 | 0 | — | — |
| 26.2: non-plain item definition | 81 | 0 | — | — |

Both color and every possible close-up picture match for 411/884 blocks in 26.3 (46.5%) and
333/797 in 26.2 (41.8%). These are observed matches in two frozen releases, not a data-derived
rule that proves a default state in another release or resource pack. No pair of absent colors
was counted as a match.

The initial issue's 26.3 counts reproduce exactly when only the first weighted alternative is
classified. Considering every alternative moves grass block, mycelium and podzol from “same”
to “rotated”; deepslate and infested deepslate move to “different” because their mirrored
alternatives are different models. This explains all five count differences.

## Concrete differences

- Oak slabs match in both releases. Oak stairs' top projections also match despite their
  block rotation; the top-down picture alone does not encode the step's height or facing.
- Anvils have equal average color (`484848`) but different close-up pixels after rotation.
- Oak buttons differ in position, coverage and color: default `997947`, item `a1824e`.
- An isolated oak fence's default is its post. The inventory picture includes side rails;
  their projections and average colors differ (`9e804d` versus `a1814e`).
- Barrel and grindstone rotations expose different faces, so even the average color changes.
  The claim that rotation cannot change the top color holds only for suitable rotations/geometry.
- Some differently named models happen to have equal top projections, including shelves and
  mushroom blocks. The naming suffix does not prove equality: `_inventory` is neither a safe
  acceptance rule nor a sufficient reason to reject a model.

Of the different-model group, 190/279 candidates in 26.3 and 186/272 in 26.2 do not provide a
comparable top projection through the current renderer (including generated flat item layers).
They are unavailable, not visually equal. Complex `special`/`composite`/`select` item roots and
missing items were classified separately; the experiment does not invent a static block model
for them or claim every complex item is inherently impossible to render.

## What the resource files can prove

155 property-bearing blocks in 26.3 and 151 in 26.2 have a blockstate choice independent of
properties: an unconditional variant or unconditional multipart entries. The current block
reader already resolves those without a default-state table. Their own blockstate model is the
answer; an inventory-model detour adds no information.

For the remaining blocks, the files enumerate model choices but do not mark which property
values the block's constructor makes default. An item file independently names its inventory
picture; it does not assert that a blockstate selector is the default. Choosing the selector
whose model resembles the inventory picture would therefore guess. Matching geometry by
inspection could establish a particular observed image, but cannot recover an unknown default
or justify another content inventory.

The installed jars have no `reports/blocks.json` default-state report. Their `blocks.json`
resources are an atlas definition and a jukebox song, not a registry/default-state source.
The registry bootstrap supplies the missing fact directly. `BlockProperties` also feeds block
tints and model-seed interpretation, so a matching inventory picture cannot replace those
property facts.

Use blockstate data wherever it already settles the choice. Generate the remaining code-only
default properties mechanically, with provenance, through #222's existing release entrypoint.
This avoids a hand-maintained list without pretending an item illustration defines world state.

## Reproduction and limits

- Kit comparison tools/source: `5300e2cb75c0c7b13a2edcced652a243552f0a05` on base
  `41b20fed4131ec9bf3db94c9d845eba3dc1cda5f`; no product source changed.
- App renderer: `cf6b414b7866f0e5fd736898949e49a8708e48c1`. Exact renderer/texture decoder
  copies and the unchanged MapColor value type were compiled with the Release Kit library.
- Xcode 27.1 / Swift 6.4, Swift language 6, macOS SDK/minimum 27. No new package dependency.
- Official 26.3 client SHA-1: `e877b6a07acd633fb3bb475002175cec036e7b87`.
- Official 26.2 client SHA-1: `2dc72797acbc1b63fc16a11c4ac393605f453754`.
- Evidence root: `/Users/ryan/Developer/ChunkseeKit-runs/block-item-default-investigation-evidence`.
  `preparation.json` records renderer hashes; `preparation-corrected.json` records extraction
  and Release build commands. `26.3-attempt-2` and `26.2-attempt-1` hold input hashes, defaults,
  cases, fixture archives, per-block `projections.json` and illustrative 16×16 RGBA pairs.
  `projection-attempt-1/results.json` records the compiler/probe/library identities and exits.
- Initial Java compilation failed because current `getValues()` returns a stream. Its source,
  failed log and API inspection remain in commit `e7aba8b` / `26.3-attempt-1`; the correction uses
  `getProperties`/`getValue`. No comparison ran in that failed attempt. Both final complete
  comparisons exited successfully; no completed measurement was repeated.

The evidence's `26.3-attempt-2/comparison-grid.png` shows default blocks on the left and item
models on the right. Rows: slab, stairs, anvil, button, fence, log, unavailable door pair,
trapdoor. Pixels were enlarged without smoothing and visually inspected; button/fence coverage
and anvil texture differences are visible. The absent door comparison is not an equal image.

This evaluates the existing renderer's component output with neutral tint. It does not measure
speed, full-world appearance, biome-dependent tint, lighting/relief, every runtime item branch,
resource-pack changes or game screenshots. All installed jars stayed unchanged; no world or
game client was opened, and no app dependency or product behavior was changed.
