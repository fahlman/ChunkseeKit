import Foundation
import ChunkseeKit
import Testing

@Suite struct ShieldItemModelTests {
    private let halfTurn: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                          "scale": [1, -1, -1], "translation": [0, 0, 0]]
    private let special: [String: Any] = ["type": "special", "base": "item/shield", "model": ["type": "shield"]]

    private func assets(_ node: [String: Any], version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        let definition = String(decoding: try JSONSerialization.data(withJSONObject: ["model": node]), as: UTF8.self)
        return try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/shield.json", text: definition),
            .init(path: "assets/minecraft/models/item/shield.json", text:
                #"{"gui_light":"front","display":{"gui":{"rotation":[15,-25,-5],"translation":[2,3,0],"scale":[0.65,0.65,0.65]}}}"#)
        ]))))
    }

    private func selected(_ child: [String: Any]) -> [String: Any] {
        ["type": "condition", "property": "using_item", "transformation": halfTurn,
         "on_true": ["type": "unsupported", "transformation": NSNull()], "on_false": child]
    }

    private func elements(_ node: [String: Any]) throws -> [AssetModel.Element] {
        let item = try #require(assets(node).defaultItemModel("shield"))
        guard case .elements(let boxes) = item.parts.first?.model.geometry else { throw Invalid.geometry }
        return boxes
    }

    @Test func shieldUsesItsParentTransformPlateHandleAndPlainSkin() throws {
        let reader = try assets(selected(special)), item = try #require(reader.defaultItemModel("shield"))
        #expect(item.parts.count == 1 && item.parts[0].tints.isEmpty)
        let model = item.parts[0].model
        #expect(model.guiTransform == reader.model("item/shield")?.guiTransform)
        #expect(model.guiLight == .front)
        let boxes = try elements(selected(special))
        #expect(boxes.map(\.from) == [SIMD3(-6, -11, 1), SIMD3(-1, -3, -5)])
        #expect(boxes.map(\.to) == [SIMD3(6, 11, 2), SIMD3(1, 3, 1)])
        #expect(boxes.allSatisfy { $0.faces.count == 6 && $0.rotation == nil })
        #expect(boxes.flatMap { $0.faces.values }.allSatisfy {
            $0.material.texture.description == "minecraft:entity/shield/shield_base_nopattern"
                && $0.tintIndex == nil && $0.rotation == 0
        })
        #expect(boxes[0].faces[.south]?.uv == SIMD4(0.25, 0.25, 3.25, 5.75))
        #expect(boxes[1].faces[.south]?.uv == SIMD4(8, 1.5, 8.5, 3))
        // Texture access is still independent; a missing skin is the client's usual fallback.
        #expect(reader.texture("entity/shield/shield_base_nopattern") == nil)
    }

    @Test func everySelectedNodeCarriesItsTransformIntoTheSameSpecialReader() throws {
        let wrappers: [[String: Any]] = [
            ["type": "composite", "models": [special]],
            ["type": "condition", "property": "using_item", "on_false": special],
            ["type": "select", "property": "display_context", "cases": [["when": "gui", "model": special]]],
            ["type": "range_dispatch", "property": "damage", "fallback": special],
            ["type": "range_dispatch", "property": "damage", "entries": [["threshold": 0, "model": special]]]
        ]
        let expected = try elements(selected(special))
        for var wrapper in wrappers {
            wrapper["transformation"] = halfTurn
            #expect(try elements(wrapper) == expected)
        }
    }

    @Test func composedTranslationsUseTheParentScaleAndHalfTurnsCanCancel() throws {
        var child = special, childTransform = halfTurn
        childTransform["translation"] = [0.125, 0, 0]
        child["transformation"] = childTransform
        var parent = halfTurn
        parent["scale"] = [2, 1, 1]
        parent["translation"] = [0.25, 0.25, 0]
        let boxes = try elements(["type": "composite", "models": [child], "transformation": parent])
        #expect(boxes[0].from == SIMD3(-4, -7, 1))
        #expect(boxes[0].to == SIMD3(20, 15, 2))

        child["transformation"] = halfTurn
        #expect(try elements(selected(child)) == elements(special))
        var quaternionTurn = halfTurn
        quaternionTurn["left_rotation"] = [-1, 0, 0, 0]
        quaternionTurn["scale"] = [1, 1, 1]
        child["transformation"] = quaternionTurn
        #expect(try elements(child) == elements(selected(special)))
    }

    @Test func siblingTransformsDoNotLeakAndOrdinaryPartsDoNotDiscardThem() throws {
        let reader = try assets(["type": "composite", "models": [selected(special), special]])
        let parts = try #require(reader.defaultItemModel("shield")).parts
        #expect(parts.count == 2)
        #expect(parts[0].model.geometry != parts[1].model.geometry)
        let ordinary: [String: Any] = ["type": "model", "model": "item/shield"]
        #expect(try assets(ordinary).defaultItemModel("shield") != nil)
        #expect(try assets(selected(ordinary)).defaultItemModel("shield") == nil)
        #expect(try assets(selected(["type": "composite", "models": [special, ordinary]])).defaultItemModel("shield") == nil)
    }

    @Test func malformedOrUnrepresentableAncestorTransformsStayUnavailable() throws {
        var invalid: [Any] = [NSNull(), [], [:]]
        for (key, value) in [("scale", [1, -1, 1]), ("scale", [0, 1, 1]), ("scale", [-1, 1, 1]),
                              ("scale", [100, 1, 1]), ("translation", [100, 0, 0]),
                              ("left_rotation", [0, 1, 0, 0]), ("right_rotation", [1, 0, 0, 0])] {
            var transform = halfTurn
            transform[key] = value
            invalid.append(transform)
        }
        var boolean = halfTurn
        boolean["scale"] = [true, false, true]
        invalid.append(boolean)
        for value in invalid {
            var node = selected(special)
            node["transformation"] = value
            #expect(try assets(node).defaultItemModel("shield") == nil)
        }
    }

    @Test func shieldUsesTheSameVerifiedVersionAndPartLimitsAsContainers() throws {
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(selected(special), version: name, dataVersion: version).defaultItemModel("shield") == nil)
        }
        #expect(try assets(["type": "composite", "models": Array(repeating: selected(special), count: 33)]).defaultItemModel("shield") == nil)
        var missing = special
        missing["base"] = "item/missing"
        #expect(try assets(selected(missing)).defaultItemModel("shield") == nil)
    }

    private enum Invalid: Error { case geometry }
}
