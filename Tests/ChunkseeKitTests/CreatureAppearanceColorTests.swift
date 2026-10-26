import ChunkseeKit
import ChunkseeKitTestSupport
import Testing

@Suite struct CreatureAppearanceColorTests {
    @Test(arguments: GeneratedCreatureColorProofs.cases)
    func matchesActualGameRenderer(_ example: GeneratedCreatureColorProofs.Case) {
        let appearance = CreatureAppearance(variant: example.variant)
        #expect(appearance.colorSource(for: example.species) == example.expected)
    }

    @Test func savedWoolAndAxolotlVariantsReachTheirColorSources() throws {
        let versions: [Int?] = [nil, 0, Int(Int32.max)]
        for version in versions {
            let wool = try #require(Creature(Fixtures.mob([
                "id": .string("minecraft:sheep"), "Color": .byte(15),
            ]), dataVersion: version)?.appearance)
            let axolotl = try #require(Creature(Fixtures.mob([
                "id": .string("minecraft:axolotl"), "Variant": .int(4),
            ]), dataVersion: version)?.appearance)
            #expect(wool.colorSource(for: "sheep") == CreatureAppearance(variant: "black").colorSource(for: "minecraft:sheep"))
            #expect(axolotl.colorSource(for: "axolotl") == CreatureAppearance(variant: "blue").colorSource(for: "minecraft:axolotl"))
            #expect(wool.colorSource(for: "sheep") != nil && axolotl.colorSource(for: "axolotl") != nil)
        }
    }

    @Test func unavailableSourcesPreserveKnownAppearanceFacts() {
        let appearance = CreatureAppearance(variant: "example:blue", markings: "spots", traits: ["base_color": "blue"])
        #expect(appearance.colorSource(for: "minecraft:axolotl") == nil)
        #expect(appearance.variant == "example:blue" && appearance.markings == "spots" && appearance.traits?["base_color"] == "blue")
        #expect(CreatureAppearance(variant: "blue").colorSource(for: "example:axolotl") == nil)
        #expect(CreatureAppearance(variant: "future").colorSource(for: "axolotl") == nil)
        #expect(CreatureAppearance(variant: "Blue").colorSource(for: "axolotl") == nil)
        #expect(CreatureAppearance(markings: "spots").colorSource(for: "sheep") == nil)
    }
}
