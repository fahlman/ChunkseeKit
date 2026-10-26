import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct StaticSkinLayoutTests {
    private let headTransform: [String: Any] = ["left_rotation": [1, 0, 0, 0], "right_rotation": [0, 0, 0, 1],
                                               "scale": [1, 1, 1], "translation": [0.5, 0, 0.5]]
    private let bannerTransform: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                                 "scale": [0.6666667, -0.6666667, -0.6666667], "translation": [0.5, 0, 0.5]]

    private func assets(_ root: [String: Any]) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#),
            .init(path: "assets/test/items/sample.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": root]), as: UTF8.self)),
            .init(path: "assets/test/models/item/base.json", text: "{}"),
            .init(path: "assets/test/models/item/flat.json", text:
                #"{"parent":"builtin/generated","textures":{"layer0":"test:plain"}}"#),
            .init(path: "assets/test/models/item/cube.json", text:
                ##"{"textures":{"plain":"test:plain"},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{"south":{"texture":"#plain"}}}]}"##)
        ]))))
    }

    private func node(_ definition: [String: Any], transform: [String: Any]? = nil) -> [String: Any] {
        var result: [String: Any] = ["type": "special", "base": "test:item/base", "model": definition]
        result["transformation"] = transform
        return result
    }

    private func materials(_ item: AssetItem) -> [AssetModel.Material] {
        item.parts.flatMap { part in
            switch part.model.geometry {
            case .layers(let layers): layers.map(\.material)
            case .elements(let elements): elements.flatMap { $0.faces.values.map(\.material) }
            }
        }
    }

    @Test func staticSpecialMaterialsExposeTheirVerifiedWholeSkinRatios() throws {
        var cases: [([String: Any], Float)] = [
            (node(["type": "conduit"]), 2),
            (node(["type": "chest", "texture": "normal"]), 1),
            (node(["type": "shulker_box", "texture": "shulker_red"]), 1),
            (node(["type": "shield"]), 1),
            (node(["type": "banner", "color": "blue"], transform: bannerTransform), 1),
            (node(["type": "decorated_pot"]), 1),
            (node(["type": "copper_golem_statue", "pose": "standing", "texture": "test:textures/statue.png"]), 1)
        ]
        for kind in ["skeleton", "wither_skeleton", "creeper", "zombie", "dragon", "piglin"] {
            let ratio: Float = ["skeleton", "wither_skeleton", "creeper"].contains(kind) ? 2 : 1
            cases.append((node(["type": "head", "kind": kind], transform: headTransform), ratio))
        }
        for (node, ratio) in cases {
            let surfaces = materials(try #require(assets(node).defaultItemModel("test:sample")))
            #expect(!surfaces.isEmpty && surfaces.allSatisfy { $0.staticTextureAspectRatio == ratio })
        }
    }

    @Test func plainElementAndGeneratedMaterialsDoNotClaimAStaticSkinLayout() throws {
        for model in ["test:item/flat", "test:item/cube"] {
            let reader = try assets(["type": "model", "model": model])
            let surfaces = materials(try #require(reader.defaultItemModel("test:sample")))
            #expect(!surfaces.isEmpty && surfaces.allSatisfy { $0.staticTextureAspectRatio == nil })
        }
    }

    @Test func composedTransformsPreserveSkinLayoutAndPatternRecipes() throws {
        let banner = node(["type": "banner", "color": "blue"], transform: bannerTransform)
        let reader = try assets(["type": "composite", "models": [banner], "transformation": [
            "left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
            "scale": [0.5, 0.5, 0.5], "translation": [0.25, 0, 0]
        ]])
        let stack = ItemStack(id: "test:sample", components: .compound([
            "minecraft:banner_patterns": .list(.compound, [.compound([
                "pattern": .compound(["asset_id": .string("test:stripe"), "translation_key": .string("stripe")]),
                "color": .string("red")
            ])])
        ]))
        let selection = try #require(stack.itemModelSelection)
        let surfaces = materials(try #require(reader.itemModel(for: selection)))
        #expect(surfaces.allSatisfy { $0.staticTextureAspectRatio == 1 })
        let cloth = try #require(surfaces.first { $0.overlays.count == 2 })
        #expect(cloth.overlays.map { $0.texture.description } == ["minecraft:entity/banner/base", "test:entity/banner/stripe"])
        #expect(cloth.overlays.map(\.color) == [0x3C44AA, 0xB02E26])
    }
}
