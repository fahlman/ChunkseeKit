import ChunkseeKit
import Foundation
import Testing

@Suite struct ItemCustomModelDataTests {
    private func item(_ value: NBT?, extra: [String: NBT] = [:]) -> ItemStack {
        var components = extra
        components["minecraft:custom_model_data"] = value
        return ItemStack(id: "stone", components: .compound(components))
    }

    @Test func currentListsRetainNumericFlagsStringsAndSharedColors() throws {
        let fields: [String: NBT] = [
            "floats": .list(.compound, [.compound(["": .byte(1)]), .compound(["": .double(2.5)])]),
            "flags": .list(.compound, [.compound(["": .int(256)]), .compound(["": .double(0.25)]), .compound(["": .float(0)])]),
            "strings": .list(.string, [.string(""), .string("Rare")]),
            "colors": .list(.compound, [.compound(["": .int(-1)]), .compound(["": .list(.float, [.float(1), .float(0.5), .float(0)])])])
        ]
        let data = try #require(item(.compound(fields)).customModelData)
        #expect(data.floats == [1, 2.5])
        #expect(data.flags == [true, true, false])
        #expect(data.strings == ["", "Rare"])
        #expect(data.colors == [0xffffff, 0xff7f00])
        let key = try #require(item(.compound(fields)).itemModelSelection)
        #expect(key.customModelData == data)
    }

    @Test func numericArrayTagsHaveTheSameListSemantics() throws {
        for array in [NBT.byteArray([0, 1]), .intArray([0, 1]), .longArray([0, 1])] {
            let data = try #require(item(.compound(["floats": array, "flags": array, "colors": array])).customModelData)
            #expect(data.floats == [0, 1])
            #expect(data.flags == [false, true])
            #expect(data.colors == [0, 1])
        }
        #expect(item(.compound(["strings": .intArray([1])])).customModelData == nil)
    }

    @Test func absentAndRemovedAreKnownEmptyWhileMalformedDoesNotFallBack() throws {
        let empty = try #require(item(nil).customModelData)
        #expect(empty.floats.isEmpty && empty.flags.isEmpty && empty.strings.isEmpty && empty.colors.isEmpty)
        #expect(item(.compound([:])).customModelData == empty)
        #expect(item(.compound(["unknown": .int(1)])).customModelData == empty)
        #expect(item(.int(9), extra: ["!minecraft:custom_model_data": .compound([:]), "CustomModelData": .int(7)]).customModelData == empty)
        for bad in [NBT.string("bad"), .compound(["flags": .string("true")]),
                    .compound(["floats": .list(.string, [.string("3")])]),
                    .compound(["colors": .list(.string, [.string("red")])])] {
            let stack = item(bad, extra: ["CustomModelData": .int(7)])
            #expect(stack.customModelData == nil)
            #expect(stack.itemModelSelection == nil)
        }
        #expect(ItemStack(id: "stone", components: .int(4)).customModelData == nil)
    }

    @Test func olderNumericComponentsAndLegacyTagsShareTheFloatConversion() throws {
        let legacy = try #require(ItemStack(.compound([
            "id": .string("stone"), "Count": .byte(1), "tag": .compound(["CustomModelData": .int(16_777_217)])
        ])))
        #expect(legacy.itemModelSelection == item(.int(16_777_217)).itemModelSelection)
        #expect(legacy.customModelData?.floats == [16_777_216])
        #expect(item(.int(2), extra: ["CustomModelData": .int(7)]).customModelData?.floats == [2])
        // Going through Double first rounds this long to the wrong adjacent Float.
        #expect(item(.long(9_223_371_487_098_961_919)).customModelData?.floats.first?.bitPattern == 1_593_835_519)
    }

    @Test func cacheIdentityKeepsGameFloatAndStringSemantics() throws {
        func float(_ value: NBT) throws -> ItemModelSelection {
            try #require(item(.compound(["floats": .list(value.tagType, [value])])).itemModelSelection)
        }
        let nan = try float(.float(.nan)), otherNaN = try float(.float(Float(bitPattern: 0xffc0_0042)))
        #expect(nan == otherNaN)
        #expect(Set([nan, otherNaN]).count == 1)
        // The NBT tag factory normalizes signed zero, but a nonzero Double can round to -0f.
        #expect(try float(.float(-0.0)) == float(.float(0)))
        let negative = try float(.double(-1e-300)), positive = try float(.float(0))
        #expect(negative != positive)
        #expect(Set([negative, positive]).count == 2)
        let composed = item(.compound(["strings": .list(.string, [.string("é")])]))
        let decomposed = item(.compound(["strings": .list(.string, [.string("e\u{301}")])]))
        #expect(composed.itemModelSelection != decomposed.itemModelSelection)
        #expect(Set([composed.itemModelSelection, decomposed.itemModelSelection]).count == 2)
    }

    @Test func customColorsChangeTheModelKeyButUnrelatedFieldsDoNot() throws {
        let one = item(.compound(["colors": .intArray([1])]))
        var two = one
        two.count = 50; two.customName = "Another name"
        #expect(one.itemModelSelection == two.itemModelSelection)
        #expect(one.itemModelSelection != item(.compound(["colors": .intArray([2])])).itemModelSelection)
        let encoded = try JSONEncoder().encode(one)
        let decoded = try JSONDecoder().decode(ItemStack.self, from: encoded)
        #expect(decoded.itemModelSelection == one.itemModelSelection)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["customModelData"] == nil && fields["itemModelSelection"] == nil)
    }

    @Test func listsAreBoundedTogetherAndUnsupportedColorsStayUnavailable() throws {
        #expect(item(.compound(["flags": .byteArray(Array(repeating: 1, count: 4096))])).customModelData?.flags.count == 4096)
        #expect(item(.compound(["flags": .byteArray(Array(repeating: 1, count: 4097))])).customModelData == nil)
        #expect(item(.compound(["floats": .intArray(Array(repeating: 1, count: 4096)), "flags": .byteArray([1])])).customModelData == nil)
        for bad in [NBT.list(.float, [.float(2), .float(0), .float(0)]), .list(.float, [.float(.nan), .float(0), .float(0)]), .intArray([1, 2])] {
            #expect(item(.compound(["colors": .list(bad.tagType, [bad])])).customModelData == nil)
        }
    }
}
