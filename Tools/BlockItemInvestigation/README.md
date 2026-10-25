# Block item/default-state investigation

Investigation for [Kit #227](https://github.com/fahlman/ChunkseeKit/issues/227).
Findings and the recommendation are in [REPORT.md](REPORT.md).
This changes no reader or renderer. It asks whether an inventory model can replace a
block's unknown default state without a block-name list. Product changes need Ryan's
decision after the report.

Use an installed stable release, the game's Java home, and a new evidence directory:

```sh
python3 Tools/BlockItemInvestigation/prepare.py "$MINECRAFT_DIR" "$MINECRAFT_JAVA" "$EVIDENCE_DIR" "$RELEASE_ID"
```

The tool verifies the client download hash, bootstraps its block registry without a world,
and records each actual default property. It then selects the corresponding blockstate
models independently from JSON and classifies the same-ID item definition. A second local
fixture retains original model/texture bytes but wraps plain item models as unrotated
block models. No installed file is modified. This fixture is evidence, never a shipped asset.

`CompareTopModels.swift` uses Kit's public block-model reader for both sides, with the
oracle's explicit default properties on the original side. Compile it in Release with exact
copies of the app's `GameModelRenderer.swift`, `ItemTexture.swift`, and the `MapColor` value
type from `BlockColors.swift`. Record the app commit, copied source hashes, Kit commit and
static-library hash with the compile command. This deliberately uses the production map
projection, not the inventory GUI transform or a second rasterizer.

The probe takes four arguments: original jar, prepared `item-blocks.zip`, `cases.json`, and
a new output JSON path. It compares the 64-pixel top projection's average color and every
possible 16-pixel close-up texture from the default state's weighted choices. Both paths
use white tint and the unchanged original texture bytes. Unavailable models/projections
stay separate from equal or unequal images; two absent colors do not count as a color match.
Plain generated item sprites therefore do not quietly become valid top-down block pictures.

The bounded initial investigation uses 26.3 and 26.2, one complete property-bearing-block
comparison per release. It retains per-block outcomes and illustrative raw RGBA pairs.
This is a component correctness comparison, not a timing benchmark, full-world rendering
test, biome-tint proof or resource-pack compatibility guarantee. Read the shared-Mac
reservation registry before compiling or running it. Preserve all commands, hashes and
failed/partial attempts. Do not rerun a completed comparison without a specific new reason.

`stateIndependent` is a deliberately narrow data-only proof: all variant entries are
identical with no multipart fallback, or every multipart entry is unconditional. It does
not infer legal property values or take an arbitrary first conditional branch. It also
does not prove that an independently authored item model equals that block model.
