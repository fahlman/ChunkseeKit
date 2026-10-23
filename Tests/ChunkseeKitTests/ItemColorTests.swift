import Foundation
import ChunkseeKit
import Testing

@Suite struct ItemColorTests {
    private func item(_ components: [String: NBT]) -> ItemStack {
        ItemStack(id: "minecraft:leather_helmet", components: .compound(components))
    }

    @Test func savedOverridesShareRGBAndNumericNarrowing() {
        let samples: [(NBT, UInt32)] = [
            (.int(0x123456), 0x123456), (.int(-1), 0xffffff), (.int(-6265536), 0xa06540),
            (.byte(-1), 0xffffff), (.short(-2), 0xfffffe), (.long(0x1_00123456), 0x123456),
            (.double(0x123456 + 0.75), 0x123456), (.float(.nan), 0),
            (.double(.infinity), 0xffffff), (.double(-.infinity), 0)
        ]
        for (saved, expected) in samples {
            let stack = item(["minecraft:dyed_color": saved,
                              "minecraft:potion_contents": .compound(["custom_color": saved])])
            #expect(stack.dyedColor == expected)
            #expect(stack.customPotionColor == expected)
        }
        #expect(item(["minecraft:dyed_color": .int(0)]).dyedColor == 0)
    }

    @Test func dyeVectorUsesGameFloatPrecisionAndFloor() {
        let half: NBT = .list(.float, [.float(1), .float(0.5), .float(0)])
        #expect(item(["minecraft:dyed_color": half]).dyedColor == 0xff7f00)
        let blue: NBT = .list(.double, [.double(0), .double(0), .double(1)])
        #expect(item(["minecraft:dyed_color": blue]).dyedColor == 0x0000ff)
        for array in [NBT.intArray([0, 1, 0]), .longArray([0, 1, 0]), .byteArray([0, 1, 0])] {
            #expect(item(["minecraft:dyed_color": array]).dyedColor == 0x00ff00)
        }
        // PotionContents.custom_color uses Codec.INT, not the dye's vector alternative.
        #expect(item(["minecraft:potion_contents": .compound(["custom_color": half])]).customPotionColor == nil)
    }

    @Test func unknownAndRemovedComponentsDoNotInventOrRecoverAnOverride() {
        #expect(item([:]).dyedColor == nil)
        #expect(item([:]).customPotionColor == nil)
        #expect(item(["minecraft:potion_contents": .string("minecraft:healing")]).customPotionColor == nil)
        #expect(item(["minecraft:potion_contents": .compound(["potion": .string("minecraft:healing")])]).customPotionColor == nil)
        let legacy: [String: NBT] = ["display": .compound(["color": .int(0x123456)]), "CustomPotionColor": .int(0xabcdef)]
        var fields = legacy
        fields["!minecraft:dyed_color"] = .compound([:])
        fields["!minecraft:potion_contents"] = .compound([:])
        fields["minecraft:dyed_color"] = .int(0)
        fields["minecraft:potion_contents"] = .compound(["custom_color": .int(0)])
        #expect(item(fields).dyedColor == nil)
        #expect(item(fields).customPotionColor == nil)
        fields = legacy
        fields["minecraft:dyed_color"] = .string("bad")
        fields["minecraft:potion_contents"] = .compound(["custom_color": .string("bad")])
        #expect(item(fields).dyedColor == nil)
        #expect(item(fields).customPotionColor == nil)
    }

    @Test func malformedDyeShapesStayUnavailable() {
        let values: [NBT] = [
            .string("#ff0000"), .compound([:]), .compound(["rgb": .string("bad")]),
            .list(.float, [.float(0), .float(1)]), .intArray([0, 1, 0, 1]),
            .list(.string, [.string("1"), .string("0"), .string("0")]),
            .list(.float, [.float(.nan), .float(0), .float(1)]),
            .list(.double, [.double(.infinity), .double(0), .double(1)]),
            .list(.float, [.float(-1), .float(0), .float(1)]),
            .list(.float, [.float(2), .float(0), .float(1)])
        ]
        for value in values { #expect(item(["minecraft:dyed_color": value]).dyedColor == nil) }
    }

    @Test func legacyTagsWrappedComponentsAndCachedStacksShareAccessors() throws {
        let old = try #require(ItemStack(.compound([
            "id": .string("minecraft:leather_helmet"), "Count": .byte(1),
            "tag": .compound(["display": .compound(["color": .int(0x345678)]), "CustomPotionColor": .int(0x123456)])
        ])))
        #expect(old.dyedColor == 0x345678)
        #expect(old.customPotionColor == 0x123456)
        let wrapped = item(["minecraft:dyed_color": .compound(["rgb": .int(0xabc123), "show_in_tooltip": .byte(0)])])
        #expect(wrapped.dyedColor == 0xabc123)
        for stack in [old, wrapped] {
            let data = try JSONEncoder().encode(stack)
            let cached = try JSONDecoder().decode(ItemStack.self, from: data)
            #expect(cached == stack)
            #expect(cached.dyedColor == stack.dyedColor)
            #expect(cached.customPotionColor == stack.customPotionColor)
            let object = try JSONSerialization.jsonObject(with: data)
            let keys = try #require(object as? [String: Any]).keys
            #expect(!keys.contains("dyedColor") && !keys.contains("customPotionColor"))
        }
    }
}
