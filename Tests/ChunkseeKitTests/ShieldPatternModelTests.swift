import ChunkseeKit
import Foundation
import Testing

@Suite struct ShieldPatternModelTests {
    private func assets(patterns: [String: String] = [:], version: String = "26.3", dataVersion: Int = 5023,
                        transform: Bool = false) throws -> GameAssets {
        let transformation = transform ? #", "transformation":{"left_rotation":[0,0,0,1],"right_rotation":[0,0,0,1],"scale":[1,-1,-1],"translation":[0,0,0]}"# : ""
        var entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/shield.json", text: "{\"model\":{\"type\":\"special\",\"base\":\"item/shield\",\"model\":{\"type\":\"shield\"}\(transformation)}}"),
            .init(path: "assets/minecraft/models/item/shield.json", text: #"{"gui_light":"front","display":{"gui":{"rotation":[15,-25,-5],"translation":[2,3,0],"scale":[0.65,0.65,0.65]}}}"#)
        ]
        for (name, text) in patterns {
            let id = try #require(Identifier(name))
            entries.append(.init(path: "data/\(id.namespace)/banner_pattern/\(id.path).json", text: text))
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func layer(_ pattern: NBT = .string("pack:stripe"), color: String = "red") -> NBT {
        .compound(["pattern": pattern, "color": .string(color)])
    }

    private func stack(base: String? = nil, layers: [NBT] = []) -> ItemStack {
        var fields: [String: NBT] = ["minecraft:banner_patterns": .list(.compound, layers)]
        if let base { fields["minecraft:base_color"] = .string(base) }
        return ItemStack(id: "shield", components: .compound(fields))
    }

    private func picture(_ stack: ItemStack, in assets: GameAssets) throws -> AssetItem? {
        assets.itemModel(for: try #require(stack.itemModelSelection))
    }

    private func material(_ item: AssetItem) throws -> AssetModel.Material {
        guard case .elements(let boxes) = try #require(item.parts.first).model.geometry else {
            throw Invalid.geometry
        }
        let material = try #require(boxes.first?.faces[.north]?.material)
        #expect(boxes.flatMap { $0.faces.values }.allSatisfy { $0.material == material })
        #expect(item.parts.count == 1 && item.parts[0].tints.isEmpty && boxes.count == 2)
        return material
    }

    @Test func emptyAndRemovedDesignsKeepTheExactPlainModel() throws {
        let reader = try assets(), plain = try #require(reader.defaultItemModel("shield"))
        #expect(try picture(ItemStack(id: "shield"), in: reader) == plain)
        #expect(try picture(stack(), in: reader) == plain)
        let removed = ItemStack(id: "shield", components: .compound([
            "minecraft:base_color": .string("red"), "minecraft:banner_patterns": .list(.compound, [layer()]),
            "!minecraft:base_color": .compound([:]), "!minecraft:banner_patterns": .compound([:])
        ]))
        #expect(try picture(removed, in: reader) == plain)
        let skin = try material(plain)
        #expect(skin.texture.description == "minecraft:entity/shield/shield_base_nopattern" && skin.overlays.isEmpty)
    }

    @Test func namedAndInlinePatternsUseTheirAssetNamespacesAndSavedOrder() throws {
        let reader = try assets(patterns: ["pack:stripe": #"{"asset_id":"different:lines/angled","translation_key":"banner.stripe"}"#])
        let inline: NBT = .compound(["asset_id": .string("custom:own"), "translation_key": .string("")])
        let item = try #require(try picture(stack(base: "blue", layers: [layer(), layer(inline, color: "magenta"), layer()]), in: reader))
        let skin = try material(item)
        #expect(skin.texture.description == "minecraft:entity/shield/shield_base" && !skin.forceTranslucent)
        #expect(skin.overlays.map { $0.texture.description } == ["minecraft:entity/shield/base", "different:entity/shield/lines/angled", "custom:entity/shield/own", "different:entity/shield/lines/angled"])
        #expect(skin.overlays.map(\.color) == [0x3c44aa, 0xb02e26, 0xc74ebd, 0xb02e26])
        // Resolving a recipe does not decode or silently replace missing picture resources.
        #expect(reader.texture(skin.overlays[1].texture.description) == nil)
        let withoutBase = try material(#require(try picture(stack(layers: [layer()]), in: reader)))
        #expect(withoutBase.overlays.first?.color == 0xf9fffe)
    }

    @Test func baseOnlyAndTransformedShieldsShareTheirExistingGeometry() throws {
        for transformed in [false, true] {
            let reader = try assets(transform: transformed)
            let plain = try #require(reader.defaultItemModel("shield"))
            let colored = try #require(try picture(stack(base: "green"), in: reader))
            let skin = try material(colored)
            #expect(skin.overlays.count == 1 && skin.overlays[0].color == 0x5e7c16)
            let a = plain.parts[0].model, b = colored.parts[0].model
            #expect(a.guiTransform == b.guiTransform && a.guiLight == b.guiLight && a.ambientOcclusion == b.ambientOcclusion)
            guard case .elements(let old) = a.geometry, case .elements(let new) = b.geometry else { throw Invalid.geometry }
            for (old, new) in zip(old, new) {
                #expect(old.from == new.from && old.to == new.to && old.rotation == new.rotation)
                for direction in AssetModel.Direction.allCases {
                    #expect(old.faces[direction]?.uv == new.faces[direction]?.uv)
                    #expect(old.faces[direction]?.rotation == new.faces[direction]?.rotation)
                    #expect(old.faces[direction]?.tintIndex == new.faces[direction]?.tintIndex)
                }
            }
        }
    }

    @Test func renderingCapsAtSixteenPatternsWithoutTruncatingSavedFacts() throws {
        let reader = try assets(patterns: ["pack:stripe": #"{"asset_id":"stripe","translation_key":"stripe"}"#])
        let many = stack(layers: Array(repeating: layer(), count: 16) + [layer(.string("missing:outside_drawn_range"))])
        #expect(many.bannerDesign?.layers.count == 17)
        let skin = try material(#require(try picture(many, in: reader)))
        #expect(skin.overlays.count == 17 && skin.overlays.dropFirst().allSatisfy { $0.color == 0xb02e26 })
        #expect(try picture(stack(layers: [layer(.string("missing:inside_drawn_range"))]), in: reader) == nil)
    }

    @Test func unreadableDefinitionsAndUnsafeAssetsNeverBecomeAPlainShield() throws {
        for json in ["null", "[]", "{}", #"{"asset_id":"stripe"}"#, #"{"asset_id":false,"translation_key":"x"}"#,
                     #"{"asset_id":"stripe","translation_key":false}"#, #"{"asset_id":"../outside","translation_key":"x"}"#,
                     #"{"asset_id":".:stripe","translation_key":"x"}"#, #"{"asset_id":"","translation_key":"x"}"#] {
            let reader = try assets(patterns: ["pack:stripe": json])
            #expect(try picture(stack(layers: [layer()]), in: reader) == nil)
            #expect(try picture(stack(), in: reader) == reader.defaultItemModel("shield"))
        }
        let reader = try assets()
        for id in ["../outside", ".:stripe", ""] {
            let inline: NBT = .compound(["asset_id": .string(id), "translation_key": .string("x")])
            #expect(try picture(stack(layers: [layer(inline)]), in: reader) == nil)
        }
        #expect(stack(base: "unknown").itemModelSelection == nil)
        #expect(stack(layers: [layer(.int(1))]).itemModelSelection == nil)
    }

    @Test func patternResourcesShareTheWholeItemBudgetAndVersionGate() throws {
        let filler = String(repeating: "x", count: 1024 * 1024)
        let reader = try assets(patterns: ["pack:stripe": "{\"asset_id\":\"stripe\",\"translation_key\":\"\(filler)\"}"])
        #expect(try picture(stack(layers: [layer()]), in: reader) != nil)
        #expect(try picture(stack(layers: Array(repeating: layer(), count: 16)), in: reader) == nil)
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try picture(stack(base: "blue"), in: assets(version: name, dataVersion: version)) == nil)
        }
    }

    @Test func modelKeysRetainDesignAndIgnoreUnrelatedCountAndName() throws {
        let red = stack(base: "red"), blue = stack(base: "blue")
        let first = stack(layers: [layer(color: "red"), layer(color: "blue")])
        let reversed = stack(layers: [layer(color: "blue"), layer(color: "red")])
        #expect(Set([red.itemModelSelection, blue.itemModelSelection, first.itemModelSelection, reversed.itemModelSelection]).count == 4)
        var renamed = first
        renamed.count = 64; renamed.customName = "same picture"
        #expect(first.itemModelSelection == renamed.itemModelSelection)
        let old = ItemStack(id: "shield", components: .compound(["BlockEntityTag": .compound(["Base": .int(14)])]))
        #expect(old.itemModelSelection == red.itemModelSelection)
        let reader = try assets()
        let plain = try material(#require(reader.defaultItemModel("shield")))
        let colored = try material(#require(try picture(red, in: reader)))
        #expect(Set([plain, colored, colored]).count == 2)
    }

    private enum Invalid: Error { case geometry }
}
