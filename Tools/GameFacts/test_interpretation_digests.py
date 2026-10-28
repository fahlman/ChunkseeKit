import unittest
from pathlib import Path

from interpretation_digests import FACT_DOMAINS, interpretation_digests, interpretation_digest_source


class InterpretationDigestTests(unittest.TestCase):
    def sources(self):
        return {"Sources/ChunkseeKit/" + name: "original " + name for name in FACT_DOMAINS}

    def test_reordered_outputs_and_provenance_or_proofs_reuse_identity(self):
        first = self.sources()
        second = dict(reversed(list(first.items())))
        second["Tools/GameFacts/source.json"] = "changed extraction/tool metadata"
        second["Tests/ChunkseeKitTests/GeneratedMapColorProofs.swift"] = "changed proof"
        self.assertEqual(interpretation_digests(first), interpretation_digests(second))

    def test_light_default_changes_only_light_generated_identity(self):
        first = self.sources()
        second = dict(first)
        second["Sources/ChunkseeKit/GeneratedLightStorage.swift"] = "different absent light"
        before, after = interpretation_digests(first), interpretation_digests(second)
        self.assertEqual({key for key in before if before[key] != after[key]}, {"light"})

    def test_map_palette_changes_asset_identity_without_rescanning_region_facts(self):
        first = self.sources()
        second = dict(first)
        second["Sources/ChunkseeKit/GeneratedMapColors.swift"] = "different palette"
        before, after = interpretation_digests(first), interpretation_digests(second)
        self.assertEqual({key for key in before if before[key] != after[key]}, {"assets"})

    def test_legacy_chunk_facts_reach_terrain_light_and_region_facts(self):
        first = self.sources()
        second = dict(first)
        second["Sources/ChunkseeKit/GeneratedLegacyChunkFacts.swift"] = "different legacy format"
        before, after = interpretation_digests(first), interpretation_digests(second)
        self.assertEqual({key for key in before if before[key] != after[key]},
                         {"terrain", "light", "regionFacts"})

    def test_new_or_missing_production_output_requires_a_dependency_decision(self):
        extra = self.sources()
        extra["Sources/ChunkseeKit/GeneratedNewFact.swift"] = "new fact"
        with self.assertRaises(ValueError):
            interpretation_digests(extra)
        missing = self.sources()
        del missing["Sources/ChunkseeKit/GeneratedLightStorage.swift"]
        with self.assertRaises(ValueError):
            interpretation_digests(missing)

    def test_checked_in_digests_cover_current_production_sources(self):
        root = Path(__file__).resolve().parents[2]
        sources = {"Sources/ChunkseeKit/" + name: (root / "Sources/ChunkseeKit" / name).read_text()
                   for name in FACT_DOMAINS}
        for path, expected in interpretation_digest_source(sources).items():
            self.assertEqual((root / path).read_text(), expected)


if __name__ == "__main__":
    unittest.main()
