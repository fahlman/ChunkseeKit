import ChunkseeKit
import Foundation
import Testing

@Suite struct ItemBannerDesignTests {
    private func stack(_ fields: [String: NBT]) -> ItemStack {
        ItemStack(id: "minecraft:shield", components: .compound(fields))
    }

    private func layer(_ pattern: NBT = .string("minecraft:creeper"), color: NBT = .string("red")) -> NBT {
        .compound(["pattern": pattern, "color": color])
    }

    @Test func currentComponentsPreserveOrderedPatternsAndOptionalBase() throws {
        let design = try #require(stack([
            "minecraft:base_color": .string("light_blue"),
            "minecraft:banner_patterns": .list(.compound, [layer(), layer(.string("pack:custom"), color: .string("white")), layer()])
        ]).bannerDesign)
        #expect(design.baseColor == .lightBlue)
        #expect(design.layers.map(\.color) == [.red, .white, .red])
        #expect(design.layers.map(\.pattern) == [.reference(try #require(Identifier("creeper"))),
            .reference(try #require(Identifier("pack:custom"))), .reference(try #require(Identifier("creeper")))])
        #expect(stack(["minecraft:banner_patterns": .list(.compound, [layer()])]).bannerDesign?.baseColor == nil)
    }

    @Test func inlineHoldersRetainTheirAssetAndTranslationKey() throws {
        let inline = layer(.compound(["asset_id": .string("pack:my_pattern"), "translation_key": .string("")]))
        let design = try #require(stack(["minecraft:banner_patterns": .list(.compound, [.compound(["": inline])])]).bannerDesign)
        #expect(design.layers.first?.pattern == .inline(assetID: try #require(Identifier("pack:my_pattern")), translationKey: ""))
        for bad in [NBT.compound(["asset_id": .string("base")]),
                    .compound(["asset_id": .string("bad ID"), "translation_key": .string("test")]),
                    .compound(["asset_id": .string("base"), "translation_key": .int(1)]), .int(1)] {
            #expect(stack(["minecraft:banner_patterns": .list(.compound, [layer(bad)])]).bannerDesign == nil)
        }
    }

    @Test func missingRemovedAndMalformedFieldsRemainDistinct() throws {
        let plain = try #require(ItemStack(id: "minecraft:shield").bannerDesign)
        #expect(plain.baseColor == nil && plain.layers.isEmpty)
        #expect(stack([:]).bannerDesign == plain)
        let legacy: NBT = .compound(["Base": .int(14), "Patterns": .list(.compound, [.compound(["Pattern": .string("cre"), "Color": .int(3)])])])
        let removed = stack(["!minecraft:base_color": .compound([:]), "!minecraft:banner_patterns": .compound([:]),
            "minecraft:base_color": .int(1), "minecraft:banner_patterns": .int(1), "BlockEntityTag": legacy])
        #expect(removed.bannerDesign == plain)
        #expect(stack(["!minecraft:base_color": .compound([:]), "BlockEntityTag": legacy]).bannerDesign?.layers.first?.color == .lightBlue)
        #expect(stack(["!minecraft:banner_patterns": .compound([:]), "BlockEntityTag": legacy]).bannerDesign?.baseColor == .red)
        #expect(stack(["minecraft:base_color": .string("black"), "minecraft:banner_patterns": .list(.end, []), "BlockEntityTag": legacy]).bannerDesign?.baseColor == .black)
        for bad in [NBT.string("Red"), .string("minecraft:red"), .string("unknown"), .int(14)] {
            #expect(stack(["minecraft:base_color": bad, "BlockEntityTag": legacy]).bannerDesign == nil)
        }
        for bad in [NBT.int(1), .intArray([1]), .list(.compound, [layer(color: .int(0))]),
                    .list(.compound, [layer(.string("bad ID"))]), .list(.compound, [.compound([:])])] {
            #expect(stack(["minecraft:banner_patterns": bad, "BlockEntityTag": legacy]).bannerDesign == nil)
        }
        #expect(ItemStack(id: "shield", components: .int(1)).bannerDesign == nil)
        #expect(stack(["BlockEntityTag": .int(1)]).bannerDesign == nil)
    }

    @Test func legacyTagsAndIntermediateFieldsUseTheSharedColorAndMigrationRules() throws {
        let old = try #require(ItemStack(.compound(["id": .string("minecraft:shield"), "Count": .byte(1),
            "tag": .compound(["BlockEntityTag": .compound(["Base": .double(14.75), "Patterns": .list(.compound, [
                .compound(["Pattern": .string("sku"), "Color": .byte(15)]),
                .compound(["Pattern": .string("moj")]),
                .compound(["Pattern": .string("pack:future"), "Color": .int(3)])])])])
        ])))
        let design = try #require(old.bannerDesign)
        #expect(design.baseColor == .red && design.layers.map(\.color) == [.black, .white, .lightBlue])
        #expect(design.layers.map(\.pattern) == [.reference(try #require(Identifier("skull"))),
            .reference(try #require(Identifier("mojang"))), .reference(try #require(Identifier("pack:future")))])
        let intermediate = stack(["BlockEntityTag": .compound(["Base": .int(4), "patterns": .list(.compound, [layer()])])])
        #expect(intermediate.bannerDesign?.baseColor == .yellow && intermediate.bannerDesign?.layers.first?.color == .red)
        for bad in [NBT.int(-1), .int(16), .string("red")] {
            #expect(stack(["BlockEntityTag": .compound(["Base": bad])]).bannerDesign == nil)
            #expect(stack(["BlockEntityTag": .compound(["Patterns": .list(.compound, [.compound(["Pattern": .string("cre"), "Color": bad])])])]).bannerDesign == nil)
        }
        #expect(stack(["BlockEntityTag": .compound(["patterns": .list(.end, []), "Patterns": .list(.end, [])])]).bannerDesign == nil)
    }

    @Test func dyeNamesAndLegacyIDsHaveOneCanonicalOrder() {
        let names = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                     "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"]
        #expect(DyeColor.allCases.map(\.rawValue) == names)
        for (id, name) in names.enumerated() {
            #expect(DyeColor(legacyID: id)?.rawValue == name)
            #expect(stack(["minecraft:base_color": .string(name)]).bannerDesign ==
                    stack(["BlockEntityTag": .compound(["Base": .int(Int32(id))])]).bannerDesign)
        }
        for invalid in [Int.min, -1, 16, Int.max] { #expect(DyeColor(legacyID: invalid) == nil) }
    }

    @Test func boundedListsRetainAllLayersAndAcceptEmptyNbtCollections() {
        for empty in [NBT.list(.end, []), .byteArray([]), .intArray([]), .longArray([])] {
            #expect(stack(["minecraft:banner_patterns": empty]).bannerDesign?.layers.isEmpty == true)
        }
        #expect(stack(["minecraft:banner_patterns": .list(.compound, Array(repeating: layer(), count: 4096))]).bannerDesign?.layers.count == 4096)
        #expect(stack(["minecraft:banner_patterns": .list(.compound, Array(repeating: layer(), count: 4097))]).bannerDesign == nil)
        let large = String(repeating: "a", count: 8 * 1024 * 1024)
        let inline = layer(.compound(["asset_id": .string(large), "translation_key": .string(large)]))
        #expect(stack(["minecraft:banner_patterns": .list(.compound, [inline])]).bannerDesign == nil)
    }

    @Test func existingItemArchivesRetainTheDesignWithoutANewStoredField() throws {
        let one = stack(["minecraft:base_color": .string("red"), "minecraft:banner_patterns": .list(.compound, [layer()])])
        var two = one
        two.count = 3; two.customName = "Renamed shield"
        #expect(one.bannerDesign == two.bannerDesign)
        let data = try JSONEncoder().encode(one)
        #expect(try JSONDecoder().decode(ItemStack.self, from: data).bannerDesign == one.bannerDesign)
        #expect(try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])["bannerDesign"] == nil)
    }
}
