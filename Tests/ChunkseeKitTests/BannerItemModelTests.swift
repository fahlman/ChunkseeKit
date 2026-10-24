import ChunkseeKit
import Foundation
import Testing

@Suite struct BannerItemModelTests {
    private let transform: [String: Any] = [
        "left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
        "scale": [0.6666667, -0.6666667, -0.6666667], "translation": [0.5, 0, 0.5]
    ]

    private func node(_ definition: [String: Any] = ["type": "banner", "color": "white"],
                      transformation: [String: Any]? = nil) -> [String: Any] {
        ["type": "special", "base": "item/banner", "model": definition,
         "transformation": transformation ?? transform]
    }

    private func assets(_ node: [String: Any], patterns: [String: String] = [:],
                        version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        var entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/sample.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": node]), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/banner.json", text:
                #"{"gui_light":"front","display":{"gui":{"rotation":[30,20,0],"translation":[0,-3.25,0],"scale":[0.5325,0.5325,0.5325]}}}"#)
        ]
        for (name, text) in patterns {
            let id = try #require(Identifier(name))
            entries.append(.init(path: "data/\(id.namespace)/banner_pattern/\(id.path).json", text: text))
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func boxes(_ item: AssetItem) throws -> [AssetModel.Element] {
        #expect(item.parts.count == 1 && item.parts[0].tints.isEmpty)
        guard case .elements(let boxes) = item.parts[0].model.geometry else { throw Invalid.geometry }
        return boxes
    }

    private func material(_ item: AssetItem) throws -> AssetModel.Material {
        let elements = try boxes(item), flag = try #require(elements.last)
        let skin = try #require(flag.faces[.south]?.material)
        #expect(flag.faces.values.allSatisfy { $0.material == skin && $0.tintIndex == nil })
        #expect(elements.dropLast().flatMap { $0.faces.values }.allSatisfy {
            $0.material.texture.description == "minecraft:entity/banner_base" && $0.material.overlays.isEmpty
        })
        return skin
    }

    private func layer(_ pattern: NBT = .string("pack:stripe"), color: String = "red") -> NBT {
        .compound(["pattern": pattern, "color": .string(color)])
    }

    private func selection(base: String = "blue", layers: [NBT] = []) throws -> ItemModelSelection {
        try #require(ItemStack(id: "sample", components: .compound([
            "minecraft:base_color": .string(base), "minecraft:banner_patterns": .list(.compound, layers)
        ])).itemModelSelection)
    }

    @Test func allDefinitionDyesPaintOnlyTheClothAndKeepNativeGUISettings() throws {
        // Independent DyeColor.getTextureDiffuseColor output from the official 26.3 classes.
        let colors: [UInt32] = [0xf9fffe, 0xf9801d, 0xc74ebd, 0x3ab3da, 0xfed83d, 0x80c71f,
                               0xf38baa, 0x474f52, 0x9d9d97, 0x169c9c, 0x8932b8, 0x3c44aa,
                               0x835432, 0x5e7c16, 0xb02e26, 0x1d1d21]
        for (dye, color) in zip(DyeColor.allCases, colors) {
            let reader = try assets(node(["type": "banner", "color": dye.rawValue]))
            let item = try #require(reader.defaultItemModel("sample")), skin = try material(item)
            #expect(skin.texture.description == "minecraft:entity/banner_base" && !skin.forceTranslucent)
            #expect(skin.overlays.count == 1 && skin.overlays[0].texture.description == "minecraft:entity/banner/base")
            #expect(skin.overlays[0].color == color)
            #expect(try reader.itemModel(for: selection(base: "magenta")) == item)
            #expect(item.parts[0].model.guiLight == .front)
            #expect(item.parts[0].model.guiTransform.rotation == SIMD3(30, 20, 0))
            #expect(item.parts[0].model.guiTransform.translation == SIMD3(0, -3.25 / 16, 0))
            #expect(item.parts[0].model.guiTransform.scale == SIMD3(repeating: 0.5325))
        }
    }

    @Test(arguments: ["ground", "wall"])
    func attachmentKeepsOfficialSupportsAndFixedClothPose(_ attachment: String) throws {
        let reader = try assets(node(["type": "banner", "color": "white", "attachment": attachment]))
        let item = try #require(reader.defaultItemModel("sample")), elements = try boxes(item)
        #expect(elements.count == (attachment == "ground" ? 3 : 2))
        #expect(elements.dropLast().allSatisfy { $0.rotation == nil })
        let flag = try #require(elements.last), rotation = try #require(flag.rotation)
        // The official baked ground/wall model, before its fixed phase-zero rotation.
        let from: SIMD3<Float> = attachment == "ground" ? SIMD3(1.333333, 2.666667, 8.666667) : SIMD3(1.333333, -13, 1.666667)
        let to: SIMD3<Float> = attachment == "ground" ? SIMD3(14.666667, 29.333334, 9.333334) : SIMD3(14.666667, 13.666667, 2.333334)
        let origin: SIMD3<Float> = attachment == "ground" ? SIMD3(8, 29.333334, 8) : SIMD3(8, 13.666667, 1)
        for axis in 0..<3 {
            #expect(abs(flag.from[axis] - from[axis]) < 0.00001)
            #expect(abs(flag.to[axis] - to[axis]) < 0.00001)
            #expect(abs(rotation.origin[axis] - origin[axis]) < 0.00001)
        }
        guard case .axis(.x, let angle) = rotation.angles else { throw Invalid.geometry }
        #expect(abs(angle - -0.4500001) < 0.00001 && !rotation.rescale)
        #expect(flag.faces[.south]?.uv == SIMD4(0.25, 0.25, 5.25, 10.25))
        #expect(flag.faces[.south]?.rotation == 0)
        _ = try material(item)
        if attachment == "ground" {
            let defaultReader = try assets(node())
            #expect(item == defaultReader.defaultItemModel("sample"))
        }
    }

    @Test func savedPatternsShareShieldRecipesButUseBannerTexturesAndDefinitionBase() throws {
        let reader = try assets(node(["type": "banner", "color": "green"]), patterns: [
            "pack:stripe": #"{"asset_id":"different:lines/angled","translation_key":"banner.stripe"}"#
        ])
        let inline: NBT = .compound(["asset_id": .string("custom:own"), "translation_key": .string("")])
        let selected = try selection(layers: [layer(), layer(inline, color: "magenta"), layer()])
        let skin = try material(#require(reader.itemModel(for: selected)))
        #expect(skin.overlays.map { $0.texture.description } == ["minecraft:entity/banner/base",
            "different:entity/banner/lines/angled", "custom:entity/banner/own", "different:entity/banner/lines/angled"])
        #expect(skin.overlays.map(\.color) == [0x5e7c16, 0xb02e26, 0xc74ebd, 0xb02e26])
        #expect(reader.texture(skin.overlays[1].texture.description) == nil)
        let removed = ItemStack(id: "sample", components: .compound([
            "minecraft:banner_patterns": .list(.compound, [layer()]), "!minecraft:banner_patterns": .compound([:])
        ]))
        #expect(try reader.itemModel(for: #require(removed.itemModelSelection)) == reader.defaultItemModel("sample"))
    }

    @Test func onlyTheFirstSixteenPatternsAreResolvedAndMalformedSelectedResourcesFail() throws {
        let reader = try assets(node(), patterns: ["pack:stripe": #"{"asset_id":"stripe","translation_key":"stripe"}"#])
        let many = try selection(layers: Array(repeating: layer(), count: 16) + [layer(.string("missing:outside_range"))])
        #expect(many.bannerDesign.layers.count == 17)
        #expect(try material(#require(reader.itemModel(for: many))).overlays.count == 17)
        #expect(try reader.itemModel(for: selection(layers: [layer(.string("missing:inside_range"))])) == nil)
        for json in ["{}", #"{"asset_id":"stripe"}"#, #"{"asset_id":"../outside","translation_key":"x"}"#] {
            let invalid = try assets(node(), patterns: ["pack:stripe": json])
            #expect(try invalid.itemModel(for: selection(layers: [layer()])) == nil)
            #expect(invalid.defaultItemModel("sample") != nil)
        }
    }

    @Test func invalidDefinitionsUnverifiedVersionsAndShearingTransformsStayUnavailable() throws {
        for definition: [String: Any] in [
            ["type": "banner"], ["type": "banner", "color": false], ["type": "banner", "color": "unknown"],
            ["type": "banner", "color": "white", "attachment": "ceiling"],
            ["type": "banner", "color": "white", "attachment": NSNull()]
        ] {
            #expect(try assets(node(definition)).defaultItemModel("sample") == nil)
        }
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(node(), version: name, dataVersion: version).defaultItemModel("sample") == nil)
        }
        var shear = transform
        shear["scale"] = [0.6666667, -0.6666667, -0.5]
        #expect(try assets(node(transformation: shear)).defaultItemModel("sample") == nil)
        let parent: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                    "scale": [0.5, 0.5, 0.5], "translation": [0.25, 0.25, 0.25]]
        let wrapped = try assets(["type": "composite", "models": [node()], "transformation": parent])
        let wrappedItem = try #require(wrapped.defaultItemModel("sample"))
        let wrappedBoxes = try boxes(wrappedItem), flag = try #require(wrappedBoxes.last)
        guard case .axis(.x, let angle) = flag.rotation?.angles else { throw Invalid.geometry }
        #expect(abs(angle - -0.4500001) < 0.00001, "Scaling the cloth must not scale its rotation angle")
    }

    private enum Invalid: Error { case geometry }
}
