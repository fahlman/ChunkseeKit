import ChunkseeKit
import Foundation
import Testing

@Suite struct ConduitItemModelTests {
    private let transform: [String: Any] = [
        "left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
        "scale": [1, 1, 1], "translation": [0.5, 0.5, 0.5]
    ]

    private func node(type: String = "conduit") -> [String: Any] {
        ["type": "special", "base": "item/base", "model": ["type": type], "transformation": transform]
    }

    private func assets(_ node: [String: Any], version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/pack/items/sample.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": node]), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/base.json", text:
                #"{"gui_light":"side","display":{"gui":{"rotation":[30,45,0],"scale":[1,1,1]}}}"#)
        ]))))
    }

    private func boxes(_ model: AssetModel) throws -> [AssetModel.Element] {
        guard case .elements(let elements) = model.geometry else { throw Invalid.geometry }
        return elements
    }

    @Test func selectedSpecialTypeUsesTheClosedShellAndRectangularSkin() throws {
        let reader = try assets(node()), item = try #require(reader.defaultItemModel("pack:sample"))
        #expect(item.parts.count == 1 && item.parts[0].tints.isEmpty)
        let model = item.parts[0].model, elements = try boxes(model), shell = try #require(elements.first)
        #expect(elements.count == 1 && shell.rotation == nil)
        #expect(shell.from == SIMD3(repeating: 5) && shell.to == SIMD3(repeating: 11))
        #expect(model.guiTransform.rotation == SIMD3(30, 45, 0))
        #expect(model.guiTransform.translation == .zero && model.guiTransform.scale == SIMD3(repeating: 1))
        #expect(model.guiLight == .side)
        let expected: [AssetModel.Direction: SIMD4<Float>] = [
            .down: SIMD4(3, 0, 6, 6), .up: SIMD4(6, 6, 9, 0), .west: SIMD4(0, 6, 3, 12),
            .north: SIMD4(3, 6, 6, 12), .east: SIMD4(6, 6, 9, 12), .south: SIMD4(9, 6, 12, 12)
        ]
        #expect(shell.faces.count == 6)
        for (direction, uv) in expected {
            let face = try #require(shell.faces[direction])
            #expect(face.uv == uv)
            #expect(face.rotation == (direction == .down || direction == .up ? 0 : 180))
            #expect(face.material.texture.description == "minecraft:entity/conduit/base")
            #expect(face.material.overlays.isEmpty && !face.material.forceTranslucent)
            #expect(face.tintIndex == nil && face.cullFace == nil)
        }
        // Selection follows the supplied definition, including another item's model override.
        let selection = try #require(ItemStack(id: "unrelated", components: .compound([
            "minecraft:item_model": .string("pack:sample")
        ])).itemModelSelection)
        #expect(reader.itemModel(for: selection) == item)
        // Geometry stays readable without images; clients retain their usual missing-image fallback.
        #expect(reader.texture("entity/conduit/base") == nil)
    }

    @Test func composedTransformsAndSiblingMaterialsUseTheSharedOwner() throws {
        let parent: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                    "scale": [0.5, 0.5, 0.5], "translation": [0.25, 0, 0]]
        let reader = try assets(["type": "composite", "models": [
            ["type": "composite", "models": [node()], "transformation": parent], node()
        ]])
        let item = try #require(reader.defaultItemModel("pack:sample"))
        #expect(item.parts.count == 2)
        let scaled = try #require(boxes(item.parts[0].model).first)
        let ordinary = try #require(boxes(item.parts[1].model).first)
        #expect(scaled.from == SIMD3(6.5, 2.5, 2.5) && scaled.to == SIMD3(9.5, 5.5, 5.5))
        #expect(ordinary.from == SIMD3(repeating: 5) && ordinary.to == SIMD3(repeating: 11))
        #expect(scaled.faces == ordinary.faces)
    }

    @Test func versionsRenderWhileInvalidDefinitionsAndCommonLimitsStayUnavailable() throws {
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(node(), version: name, dataVersion: version).defaultItemModel("pack:sample") != nil)
        }
        for type in ["different:conduit", "unknown", "../conduit"] {
            #expect(try assets(node(type: type)).defaultItemModel("pack:sample") == nil)
        }
        var missing = node()
        missing["base"] = "item/absent"
        #expect(try assets(missing).defaultItemModel("pack:sample") == nil)
        missing = node()
        var outside = transform
        outside["translation"] = [100, 0, 0]
        missing["transformation"] = outside
        #expect(try assets(missing).defaultItemModel("pack:sample") == nil)
        #expect(try assets(["type": "composite", "models": Array(repeating: node(), count: 33)])
            .defaultItemModel("pack:sample") == nil)
    }

    private enum Invalid: Error { case geometry }
}
