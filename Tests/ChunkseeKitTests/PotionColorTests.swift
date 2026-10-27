import ChunkseeKit
import Testing

@Suite struct PotionColorTests {
    private let version: Int32 = 5023
    private let fallback: UInt32 = 0x385dc6

    private func item(_ value: NBT) -> ItemStack {
        ItemStack(id: "minecraft:potion", components: .compound(["minecraft:potion_contents": value]))
    }

    private func color(_ value: NBT) -> UInt32? {
        item(value).potionColor(gameDataVersion: version, defaultColor: fallback)
    }

    private func effect(_ id: String, amplifier: NBT = .byte(0), visible: NBT? = nil) -> NBT {
        var fields: [String: NBT] = ["id": .string(id), "amplifier": amplifier, "duration": .int(0)]
        if let visible { fields["show_particles"] = visible }
        return .compound(fields)
    }

    @Test func ordinaryPotionsUseTheirEffectsAndTurtleMasterUsesBoth() {
        #expect(color(.compound(["potion": .string("healing")])) == 0xf82423)
        #expect(color(.string("minecraft:strong_swiftness")) == 0x33ebff)
        #expect(color(.compound(["potion": .string("turtle_master")])) == 9274086)
        #expect(color(.string("strong_turtle_master")) == 9274854)
        #expect(color(.string("water")) == fallback)
        #expect(color(.compound(["potion": .string("awkward")])) == fallback)
    }

    @Test func customEffectsUseLevelWeightsEvenWithZeroOrMissingDuration() {
        let effects: NBT = .list(.compound, [effect("speed", amplifier: .byte(1)), effect("poison")])
        #expect(color(.compound(["custom_effects": effects])) == 0x4fd3cb)
        #expect(color(.compound(["custom_effects": .list(.compound, [.compound(["id": .string("speed")])])])) == 0x33ebff)
        // The same unsigned-byte decoder is used for active effects and potion colors.
        let wrapped: NBT = .list(.compound, [effect("speed", amplifier: .int(257)), effect("poison")])
        #expect(color(.compound(["custom_effects": wrapped])) == 0x4fd3cb)
        let baseAndCustom: NBT = .compound(["potion": .string("strong_swiftness"), "custom_effects": .list(.compound, [effect("poison")])])
        #expect(color(baseAndCustom) == 0x4fd3cb)
    }

    @Test func hiddenParticlesDoNotContributeAndNumericVisibilityMatchesNBT() {
        let hidden: NBT = .compound(["custom_effects": .list(.compound, [effect("mod:unknown", visible: .byte(0)), effect("speed")])])
        #expect(color(hidden) == 0x33ebff)
        #expect(color(.compound(["custom_effects": .list(.compound, [effect("speed", visible: .double(0))])])) == fallback)
        #expect(color(.compound(["custom_effects": .list(.compound, [effect("speed", visible: .double(0.5))])])) == 0x33ebff)
        #expect(color(.compound(["custom_effects": .list(.compound, [effect("speed", visible: .double(.nan))])])) == 0x33ebff)
    }

    @Test func explicitOverridePrecedesRecipesAndUnknownGameVersions() {
        let stack = item(.compound(["custom_color": .int(-1), "potion": .string("mod:unknown")]))
        #expect(stack.customPotionColor == 0xffffff)
        #expect(stack.potionColor(gameDataVersion: 9999, defaultColor: fallback) == 0xffffff)
        #expect(color(.compound(["custom_color": .string("red"), "potion": .string("healing")])) == nil)
    }

    @Test func legacyTagsAndCurrentComponentsSharePrecedence() {
        let legacy = ItemStack(id: "minecraft:potion", components: .compound([
            "Potion": .string("strong_swiftness"),
            "CustomPotionEffects": .list(.compound, [.compound(["Id": .byte(19), "Amplifier": .byte(0), "Duration": .int(0)])])]))
        #expect(legacy.potionColor(gameDataVersion: version, defaultColor: fallback) == 0x4fd3cb)
        for current in [NBT.compound([:]), .int(0)] {
            let stack = ItemStack(id: "minecraft:potion", components: .compound([
                "minecraft:potion_contents": current, "CustomPotionColor": .int(123), "Potion": .string("healing")]))
            #expect(stack.customPotionColor == nil)
            #expect(stack.potionColor(gameDataVersion: version, defaultColor: fallback) == (current.compound == nil ? nil : fallback))
        }
        let removed = ItemStack(id: "minecraft:potion", components: .compound([
            "!minecraft:potion_contents": .compound([:]), "minecraft:potion_contents": .compound(["custom_color": .int(123)]),
            "Potion": .string("healing"), "CustomPotionColor": .int(456)]))
        #expect(removed.potionColor(gameDataVersion: version, defaultColor: fallback) == fallback)
        #expect(removed.customPotionColor == nil)
    }

    @Test func unknownOrMalformedNeededFactsStayUnavailable() {
        #expect(item(.compound([:])).potionColor(gameDataVersion: 5024, defaultColor: 0xff123456) == 0x123456)
        for value in [NBT.string("mod:healing"), .compound(["potion": .int(0)]), .compound(["custom_effects": .int(0)]),
                      .compound(["custom_effects": .list(.compound, [effect("mod:unknown")])]),
                      .compound(["custom_effects": .list(.compound, [effect("speed", amplifier: .string("two"))])]),
                      .compound(["custom_effects": .list(.compound, [effect("speed", visible: .string("yes"))])])] {
            #expect(color(value) == nil)
        }
    }

    @Test func generatedDefaultsMatchTheGamesColorMethodAcrossVersionLabels() {
        for sample in GeneratedPotionColorProofs.cases {
            var fields: [String: NBT] = [:]
            if let potion = sample.potion { fields["potion"] = .string(potion) }
            fields["custom_effects"] = .list(.compound, sample.effects.map {
                effect($0.id, amplifier: .int($0.amplifier), visible: .byte($0.visible ? 1 : 0))
            })
            let stack = item(.compound(fields))
            for version in [-1, 1, 5023, 1_000_000] as [Int32] {
                #expect(stack.potionColor(gameDataVersion: version, defaultColor: GeneratedPotionColorProofs.defaultColor) == sample.color)
            }
            #expect(stack.components == .compound(["minecraft:potion_contents": .compound(fields)]))
        }
    }

    @Test func effectCountIsBoundedBeforeWeightedSums() {
        #expect(color(.compound(["custom_effects": .list(.compound, Array(repeating: effect("speed"), count: 4097))])) == nil)
        #expect(color(.compound(["custom_effects": .list(.compound, Array(repeating: effect("speed", amplifier: .byte(-1)), count: 4096))])) == 0x33ebff)
    }
}
