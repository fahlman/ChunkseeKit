import ChunkseeKit
import Foundation
import Testing

@Suite struct ItemPotDecorationsTests {
    private func stack(_ raw: NBT, extra: [String: NBT] = [:]) -> ItemStack {
        var fields = extra; fields["minecraft:pot_decorations"] = raw
        return ItemStack(id: "decorated_pot", components: .compound(fields))
    }

    @Test func currentSideNamesKeepTemplatesAndPatternOverrides() throws {
        let value = stack(.compound([
            "back": .string("angler_pottery_sherd"),
            "left": .compound(["id": .string("stone"), "count": .int(2), "components": .compound([
                "minecraft:provides_pottery_pattern": .string("pack:stars")])]),
            "right": .compound(["id": .string("brick"), "components": .compound([
                "minecraft:provides_pottery_pattern": .compound(["asset_id": .string("pack:moon")])])]),
            "front": .compound(["id": .string("archer_pottery_sherd"), "components": .compound([
                "!minecraft:provides_pottery_pattern": .compound([:])])])
        ]))
        let design = try #require(value.potDecorations)
        #expect(design.back?.itemID.description == "minecraft:angler_pottery_sherd")
        #expect(design.back?.pattern == .itemDefault)
        #expect(design.left?.itemID.description == "minecraft:stone")
        #expect(design.left?.pattern == .reference(try #require(Identifier("pack:stars"))))
        #expect(design.right?.pattern == .inline(assetID: try #require(Identifier("pack:moon"))))
        #expect(design.front?.pattern == .removed)
        #expect(value.itemModelSelection?.potDecorations == design)
    }

    @Test func legacyListsUseBackLeftRightFrontAndPadWithBrick() throws {
        let list: NBT = .list(.string, [.string("angler_pottery_sherd"), .string("archer_pottery_sherd")])
        let modern = try #require(stack(list).potDecorations)
        let tag: NBT = .compound(["BlockEntityTag": .compound(["sherds": list])])
        let old = try #require(ItemStack(.compound(["id": .string("decorated_pot"), "Count": .byte(1),
                                                   "tag": tag])))
        #expect(old.potDecorations == modern)
        #expect(modern.back?.itemID.description == "minecraft:angler_pottery_sherd")
        #expect(modern.left?.itemID.description == "minecraft:archer_pottery_sherd")
        #expect(modern.right?.itemID.description == "minecraft:brick" && modern.front?.itemID.description == "minecraft:brick")
        for empty in [NBT.list(.end, []), .byteArray([]), .intArray([]), .longArray([])] {
            let design = try #require(stack(empty).potDecorations)
            #expect([design.back, design.left, design.right, design.front].allSatisfy { $0?.itemID.description == "minecraft:brick" })
        }
        let wrapped: NBT = .list(.compound, [.compound(["": .string("brick")])])
        #expect(stack(wrapped).potDecorations == stack(.list(.end, [])).potDecorations)
    }

    @Test func missingRemovedAndMalformedValuesStayDistinct() throws {
        let empty = try #require(ItemStack(id: "decorated_pot").potDecorations)
        #expect(empty.back == nil && empty.left == nil && empty.right == nil && empty.front == nil)
        #expect(stack(.compound([:])).potDecorations == empty)
        let legacy: NBT = .compound(["sherds": .list(.string, [.string("angler_pottery_sherd")])])
        #expect(stack(.compound([:]), extra: ["BlockEntityTag": legacy]).potDecorations == empty)
        #expect(stack(.int(1), extra: ["!minecraft:pot_decorations": .compound([:]), "BlockEntityTag": legacy]).potDecorations == empty)
        for bad in [NBT.int(1), .string("brick"), .intArray([1]), .list(.int, [.int(1)]),
                    .list(.string, Array(repeating: .string("brick"), count: 5)), .compound(["front": .int(1)]),
                    .compound(["back": .string("Bad ID")])] {
            #expect(stack(bad, extra: ["BlockEntityTag": legacy]).potDecorations == nil)
            #expect(stack(bad).itemModelSelection == nil)
        }
        #expect(ItemStack(id: "decorated_pot", components: .int(1)).potDecorations == nil)
        #expect(ItemStack(id: "decorated_pot", components: .compound(["BlockEntityTag": .int(1)])).potDecorations == nil)
    }

    @Test func templateCountsAndPatternHoldersAreValidatedWithoutReadingUnrelatedData() throws {
        func template(_ fields: [String: NBT]) -> ItemStack { stack(.compound(["front": .compound(fields)])) }
        for count in [NBT.int(0), .int(100), .int(-1), .string("1")] {
            #expect(template(["id": .string("brick"), "count": count]).potDecorations == nil)
        }
        for count in [NBT.byte(1), .int(99), .double(2.75)] {
            #expect(template(["id": .string("brick"), "count": count]).potDecorations?.front?.itemID.description == "minecraft:brick")
        }
        for bad in [NBT.int(1), .string("Bad ID"), .compound([:]), .compound(["asset_id": .int(1)])] {
            #expect(template(["id": .string("brick"), "components": .compound(["minecraft:provides_pottery_pattern": bad])]).potDecorations == nil)
        }
        #expect(template(["id": .string("brick"), "components": .int(1)]).potDecorations == nil)
        let removed = template(["id": .string("brick"), "components": .compound([
            "minecraft:provides_pottery_pattern": .int(1), "!minecraft:provides_pottery_pattern": .compound([:])])])
        #expect(removed.potDecorations?.front?.pattern == .removed)
        #expect(template(["components": .compound([:])]).potDecorations == nil)
        let large = String(repeating: "a", count: 16 * 1024 * 1024 + 1)
        #expect(stack(.compound(["front": .string(large)])).potDecorations == nil)
    }

    @Test func selectionIdentityIncludesTheSideAndPatternButNotCountOrTooltip() throws {
        func value(side: String = "front", asset: String = "pack:one", count: Int32 = 1) -> ItemStack {
            stack(.compound([side: .compound(["id": .string("brick"), "count": .int(count), "components": .compound([
                "minecraft:custom_name": .string("ignored"),
                "minecraft:provides_pottery_pattern": .compound(["asset_id": .string(asset)])])])]))
        }
        let first = value()
        #expect(first.itemModelSelection == value(count: 2).itemModelSelection)
        #expect(first.itemModelSelection != value(side: "back").itemModelSelection)
        #expect(first.itemModelSelection != value(asset: "pack:two").itemModelSelection)
        var renamed = first; renamed.count = 30; renamed.customName = "Keepsake"
        #expect(first.itemModelSelection == renamed.itemModelSelection)
        #expect(Set([try #require(first.itemModelSelection), try #require(value(count: 2).itemModelSelection)]).count == 1)
        let data = try JSONEncoder().encode(first)
        #expect(try JSONDecoder().decode(ItemStack.self, from: data).potDecorations == first.potDecorations)
        #expect(try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])["potDecorations"] == nil)
    }
}
