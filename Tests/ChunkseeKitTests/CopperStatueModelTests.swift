import ChunkseeKit
import Foundation
import Testing

@Suite struct CopperStatueModelTests {
    private func node(_ pose: Any = "standing", texture: Any = "pack:textures/statues/green.png") -> [String: Any] {
        ["type": "special", "base": "item/statue", "model": ["type": "copper_golem_statue", "pose": pose, "texture": texture]]
    }

    private let transform: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                           "scale": [1, -1, -1], "translation": [0.5, 1.5, 0.5]]

    private func assets(_ node: [String: Any], version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        let root: [String: Any] = ["model": ["type": "composite", "models": [node], "transformation": transform]]
        let entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/test.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: root), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/statue.json", text:
                #"{"gui_light":"front","display":{"gui":{"rotation":[30,45,180],"translation":[0,2,0],"scale":[0.55,0.55,0.55]}}}"#),
            .init(path: "assets/pack/textures/statues/green.png", text: "supplied texture bytes")
        ]
        return try #require(GameAssets(data: Data(TestZIP.zip(entries))))
    }

    private func elements(_ item: AssetItem) throws -> [AssetModel.Element] {
        guard item.parts.count == 1, case .elements(let value) = item.parts[0].model.geometry else { throw Invalid.model }
        return value
    }

    @Test func posesShareTheCuboidUVAndMaterialPath() throws {
        for (pose, count) in [("standing", 9), ("sitting", 11), ("running", 9), ("star", 9)] {
            let reader = try assets(node(pose)), item = try #require(reader.defaultItemModel("test"))
            let boxes = try elements(item), model = item.parts[0].model
            #expect(boxes.count == count && boxes.allSatisfy { $0.faces.count == 6 })
            #expect(model.guiTransform.rotation == SIMD3(30, 45, 180))
            #expect(model.guiTransform.translation == SIMD3(0, 0.125, 0))
            #expect(model.guiTransform.scale == SIMD3(repeating: 0.55) && model.guiLight == .front)
            #expect(boxes.allSatisfy { box in
                [box.from, box.to].allSatisfy { value in (0..<3).allSatisfy { value[$0].isFinite && (-16...32).contains(value[$0]) } }
            })
            #expect(boxes.flatMap { $0.faces.values }.allSatisfy {
                $0.material.texture.description == "pack:statues/green" && $0.material.overlays.isEmpty && !$0.material.forceTranslucent
                    && $0.tintIndex == nil && $0.cullFace == nil
            })
            #expect(reader.texture("pack:statues/green") == Data("supplied texture bytes".utf8))
            #expect(boxes.contains { $0.rotation != nil } == (pose != "standing"))
        }
    }

    @Test func standingModelComposesTheRootAndItemTransformWithItsInflations() throws {
        let boxes = try elements(#require(assets(node()).defaultItemModel("test")))
        #expect(boxes[0].from == SIMD3(4, 19, 6) && boxes[0].to == SIMD3(8, 24, 10))
        #expect(boxes[0].faces[.down]?.uv == SIMD4(5, 6.75, 6, 7.75))
        let head = boxes[3]
        #expect((0..<3).allSatisfy { abs(head.from[$0] - SIMD3<Float>(3.985, 7.985, 2.985)[$0]) < 0.00001 })
        #expect((0..<3).allSatisfy { abs(head.to[$0] - SIMD3<Float>(12.015, 13.015, 13.015)[$0]) < 0.00001 })
        #expect(head.faces[.north]?.uv == SIMD4(7, 2.5, 9, 3.75))
    }

    @Test func unknownPoseOrUnrepresentableFullImageResourceStaysUnavailable() throws {
        for pose: Any in ["walking", "STANDING", "", 7] {
            #expect(try assets(node(pose)).defaultItemModel("test") == nil)
        }
        for texture: Any in ["pack:statues/green", "pack:textures/.png", "pack:textures/../secret.png", "pack:images/green.png", "pack:textures/green.jpg", 4] {
            #expect(try assets(node(texture: texture)).defaultItemModel("test") == nil)
        }
        var missing = node(); var definition = try #require(missing["model"] as? [String: Any])
        definition.removeValue(forKey: "pose"); missing["model"] = definition
        #expect(try assets(missing).defaultItemModel("test") == nil)
    }

    @Test func selectedDefinitionUsesSavedPoseAndKeepsCommonBounds() throws {
        let select: [String: Any] = ["type": "select", "property": "block_state", "block_state_property": "copper_golem_pose",
                                    "cases": [["when": "sitting", "model": node("sitting")]], "fallback": node()]
        let reader = try assets(select), plain = try assets(node()).defaultItemModel("test")
        let stack = ItemStack(id: "test", components: .compound([
            "minecraft:block_state": .compound(["copper_golem_pose": .string("sitting")])]))
        #expect(reader.defaultItemModel("test") == plain)
        #expect(try reader.itemModel(for: #require(stack.itemModelSelection)) == assets(node("sitting")).defaultItemModel("test"))
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(node(), version: name, dataVersion: version).defaultItemModel("test") == nil)
        }
        #expect(try assets(["type": "composite", "models": Array(repeating: node(), count: 33)]).defaultItemModel("test") == nil)
        var scaled = node("running"); var nonuniform = transform; nonuniform["scale"] = [2, 1, 1]
        scaled["transformation"] = nonuniform
        #expect(try assets(scaled).defaultItemModel("test") == nil)
        var missing = node(); missing["base"] = "item/missing"
        #expect(try assets(missing).defaultItemModel("test") == nil)
    }

    private enum Invalid: Error { case model }
}
