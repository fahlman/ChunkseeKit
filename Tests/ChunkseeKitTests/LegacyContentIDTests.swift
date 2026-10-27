import ChunkseeKit
import Foundation
import Testing

@Suite struct LegacyContentIDTests {
    @Test func savedEffectIDsMatchWholeNativePlayerUpgrades() {
        for sample in GeneratedLegacyContentProofs.effects {
            let effect: NBT = .compound(["Id": sample.tag, "Amplifier": .int(2), "Duration": .int(200)])
            for version in [nil, -1, 100, 5023, 5119, 9999] as [Int32?] {
                var fields: [String: NBT] = ["ActiveEffects": .list([effect])]
                if let version { fields["DataVersion"] = .int(version) }
                let player = PlayerInfo(uuid: UUID(), nbt: .compound(fields))
                let expected = sample.id.map { [StatusEffect(id: $0, amplifier: 2, durationTicks: 200)] } ?? []
                #expect(player.activeEffects == expected, "Legacy effect ID \(sample.tag)")
            }

            let legacy = ItemStack(id: "minecraft:potion", components: .compound([
                "CustomPotionEffects": .list([effect]),
            ]))
            let expectedColor = sample.id.flatMap { id in
                ItemStack(id: "minecraft:potion", components: .compound([
                    "minecraft:potion_contents": .compound(["custom_effects": .list([
                        .compound(["id": .string(id), "amplifier": .int(2)]),
                    ])]),
                ])).potionColor(gameDataVersion: 9999, defaultColor: 0x123456)
            }
            #expect(legacy.potionColor(gameDataVersion: 9999, defaultColor: 0x123456) == expectedColor,
                    "Potion effect ID \(sample.tag)")
        }
    }

    @Test func savedBannerIDsMatchWholeNativeBlockEntityUpgrades() throws {
        for sample in GeneratedLegacyContentProofs.patterns {
            let item = try #require(ItemStack(.compound([
                "id": .string("minecraft:shield"), "Count": .byte(1),
                "tag": .compound(["BlockEntityTag": .compound(["Patterns": .list([
                    .compound(["Pattern": .string(sample.before), "Color": .int(14)]),
                ])])]),
            ])))
            let design = try #require(item.bannerDesign)
            #expect(design.layers.count == 1)
            #expect(design.layers.first?.pattern == .reference(try #require(Identifier(sample.id))))
            #expect(design.layers.first?.color == .red)
        }
    }
}
