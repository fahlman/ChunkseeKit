import Foundation
import ChunkseeKit
import Testing

@Suite struct ItemModelTranslationTests {
    private func transform(_ translation: [Double], scale: [Double] = [1, 1, 1]) -> [String: Any] {
        ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1], "scale": scale, "translation": translation]
    }

    private func node(_ translation: [Double]? = nil, model: String = "block/piece") -> [String: Any] {
        var result: [String: Any] = ["type": "model", "model": model, "tints": [["type": "constant", "value": 0x123456]]]
        if let translation { result["transformation"] = transform(translation) }
        return result
    }

    private func assets(_ node: [String: Any], rotation: [String: Any]? = nil) throws -> GameAssets {
        var element: [String: Any] = ["from": [0, 3, 0], "to": [16, 9, 16], "light_emission": 3,
            "shade_direction_override": "up", "faces": ["up": ["texture": "#skin", "tintindex": 0],
                "north": ["texture": "#skin", "rotation": 90, "cullface": "north"]]]
        element["rotation"] = rotation
        let model: [String: Any] = ["textures": ["skin": "block/test"], "elements": [element],
            "ambientocclusion": false, "gui_light": "front", "display": ["gui": ["rotation": [20, 30, 40],
                "translation": [1, 2, 3], "scale": [0.5, 0.6, 0.7]]]]
        func json(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        return try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#),
            .init(path: "assets/minecraft/items/test.json", text: try json(["model": node])),
            .init(path: "assets/minecraft/models/block/piece.json", text: try json(model)),
            .init(path: "assets/minecraft/models/item/flat.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"item/test"}}"#)
        ]))))
    }

    private func firstElement(_ model: AssetModel) throws -> AssetModel.Element {
        guard case .elements(let elements) = model.geometry else { throw Invalid.geometry }
        return try #require(elements.first)
    }

    @Test func bedPartsAreAdjacentAndKeepTheirOriginalUVsAndPresentation() throws {
        let reader = try assets(["type": "composite", "models": [node(), node([0, 0, 1])]])
        let parts = try #require(reader.defaultItemModel("test")).parts
        #expect(parts.count == 2)
        let head = try firstElement(parts[0].model), foot = try firstElement(parts[1].model)
        #expect(head.from == SIMD3(0, 3, 0) && head.to == SIMD3(16, 9, 16))
        #expect(foot.from == SIMD3(0, 3, 16) && foot.to == SIMD3(16, 9, 32))
        #expect(foot.faces == head.faces && foot.faces[.up]?.uv == SIMD4(0, 0, 16, 16))
        #expect(foot.faces[.north]?.rotation == 90 && foot.faces[.north]?.cullFace == .north)
        #expect(foot.shadeDirectionOverride == .up && foot.lightEmission == 3)
        #expect(parts[0].model.guiTransform == parts[1].model.guiTransform)
        #expect(parts[1].model.guiLight == .front && !parts[1].model.ambientOcclusion)
        #expect(parts[0].tints == parts[1].tints && parts[1].tints == [.constant(0x123456)])
    }

    @Test func translationMovesAxisAndEulerRotationOriginsWithoutChangingTheirRules() throws {
        let rotations: [[String: Any]] = [
            ["origin": [8, 8, 8], "axis": "y", "angle": 45, "rescale": true],
            ["origin": [8, 8, 8], "x": 30, "y": 45, "z": 15, "rescale": true]
        ]
        for rotation in rotations {
            let reader = try assets(node([-0.25, 0.5, 1]), rotation: rotation)
            let original = try firstElement(#require(reader.model("block/piece")))
            let shifted = try firstElement(#require(reader.defaultItemModel("test")).parts[0].model)
            #expect(shifted.from == SIMD3(-4, 11, 16) && shifted.to == SIMD3(12, 17, 32))
            #expect(shifted.rotation?.origin == SIMD3(4, 16, 24))
            #expect(shifted.rotation?.angles == original.rotation?.angles && shifted.rotation?.rescale == true)
            #expect(shifted.faces == original.faces)
        }
    }

    @Test func nestedTranslationsComposeWithoutLeakingIntoSiblings() throws {
        let root: [String: Any] = ["type": "composite", "transformation": transform([0.25, 0, 0.5]),
            "models": [node([0.5, -0.25, 0.5]), node()]]
        let parts = try #require(assets(root).defaultItemModel("test")).parts
        #expect(try firstElement(parts[0].model).from == SIMD3(12, -1, 16))
        #expect(try firstElement(parts[1].model).from == SIMD3(4, 3, 8))
        #expect(try firstElement(parts[0].model).to == SIMD3(28, 5, 32))
        #expect(try firstElement(parts[1].model).to == SIMD3(20, 9, 24))
    }

    @Test func selectedBranchesUseTheSameTranslationOwner() throws {
        let child = node()
        let wrappers: [[String: Any]] = [
            ["type": "condition", "property": "using_item", "on_false": child],
            ["type": "select", "property": "display_context", "cases": [["when": "gui", "model": child]]],
            ["type": "range_dispatch", "property": "damage", "fallback": child]
        ]
        for var wrapper in wrappers {
            wrapper["transformation"] = transform([0, 0, 1])
            let part = try #require(assets(wrapper).defaultItemModel("test")).parts[0]
            #expect(try firstElement(part.model).from == SIMD3(0, 3, 16))
        }
    }

    @Test func unsupportedTransformsAndNonfiniteResultsKeepTheWholeItemUnavailable() throws {
        #expect(try assets(node(model: "item/flat")).defaultItemModel("test") != nil)
        #expect(try assets(node([0, 0, 1], model: "item/flat")).defaultItemModel("test") == nil)
        let scales: [[Double]] = [[2, 1, 1], [1, -2, -1]]
        for scale in scales {
            var ordinary = node(); ordinary["transformation"] = transform([0, 0, 0], scale: scale)
            #expect(try assets(ordinary).defaultItemModel("test") == nil)
        }
        #expect(try assets(node([1e38, 0, 0])).defaultItemModel("test") == nil)
        // Node transforms can move valid elements beyond the source JSON's coordinate bounds.
        let distant = try #require(assets(node([0, 0, 2])).defaultItemModel("test")).parts[0]
        #expect(try firstElement(distant.model).to == SIMD3(16, 9, 48))
        let oversized: [String: Any] = ["type": "composite", "models": Array(repeating: node([0, 0, 1]), count: 33)]
        #expect(try assets(oversized).defaultItemModel("test") == nil)
    }

    private enum Invalid: Error { case geometry }
}
