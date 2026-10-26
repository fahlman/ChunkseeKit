import ChunkseeKitTestSupport
import Foundation
import ChunkseeKit
import Testing

@Suite struct ItemModelHalfTurnTests {
    private func transform(_ turn: [Int], _ translation: [Double] = [1, 0, 1]) -> [String: Any] {
        ["left_rotation": turn, "right_rotation": [0, 0, 0, 1],
         "scale": [1, 1, 1], "translation": translation]
    }

    private func node(_ transform: [String: Any]? = nil) -> [String: Any] {
        var node: [String: Any] = ["type": "model", "model": "block/piece",
                                  "tints": [["type": "constant", "value": 0x123456]]]
        node["transformation"] = transform
        return node
    }

    private func assets(_ node: [String: Any], rotation: [String: Any]? = nil,
                        inverted: Bool = false) throws -> GameAssets {
        let faces = Dictionary(uniqueKeysWithValues: AssetModel.Direction.allCases.map { direction in
            (direction.rawValue, ["texture": "#" + direction.rawValue, "uv": [1, 2, 13, 11],
                                 "rotation": 90, "cullface": direction.rawValue, "tintindex": 0] as [String: Any])
        })
        var element: [String: Any] = ["from": inverted ? [5, 7, 11] : [1, 2, 3],
            "to": inverted ? [1, 2, 3] : [5, 7, 11], "faces": faces,
            "shade_direction_override": "west", "light_emission": 3]
        element["rotation"] = rotation
        func json(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }
        return try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#),
            .init(path: "assets/minecraft/items/test.json", text: try json(["model": node])),
            .init(path: "assets/minecraft/models/block/piece.json", text: try json([
                "elements": [element], "gui_light": "front", "ambientocclusion": false,
                "textures": Dictionary(uniqueKeysWithValues: AssetModel.Direction.allCases.map {
                    ($0.rawValue, "block/" + $0.rawValue)
                })])),
            .init(path: "assets/minecraft/models/item/flat.json", text:
                #"{"parent":"builtin/generated","textures":{"layer0":"item/test"}}"#)
        ]))))
    }

    private func element(_ item: AssetItem, part: Int = 0) throws -> AssetModel.Element {
        guard case .elements(let elements) = item.parts[part].model.geometry else { throw Invalid.geometry }
        return try #require(elements.first)
    }

    @Test func yHalfTurnKeepsStrawBedPartsAdjacentAndRotatesFacesWithTheirUVs() throws {
        let reader = try assets(["type": "composite", "models": [
            node(transform([0, 1, 0, 0])), node(transform([0, 1, 0, 0], [1, 0, 2]))]])
        let item = try #require(reader.defaultItemModel("test"))
        let head = try element(item), foot = try element(item, part: 1)
        #expect(head.from == SIMD3(11, 2, 5) && head.to == SIMD3(15, 7, 13))
        #expect(foot.from == SIMD3(11, 2, 21) && foot.to == SIMD3(15, 7, 29))
        #expect(head.faces == foot.faces && head.rotation == nil)
        for (target, source) in [("north", "south"), ("south", "north"), ("west", "east"),
                                 ("east", "west"), ("up", "up"), ("down", "down")] {
            let direction = try #require(AssetModel.Direction(rawValue: target))
            let face = try #require(head.faces[direction])
            #expect(face.material.texture.description == "minecraft:block/" + source)
            #expect(face.uv == SIMD4(1, 2, 13, 11) && face.tintIndex == 0)
            #expect(face.rotation == (["up", "down"].contains(target) ? 270 : 90))
            #expect(face.cullFace == direction)
        }
        #expect(head.shadeDirectionOverride == .east && head.lightEmission == 3)
        #expect(item.parts[0].tints == [.constant(0x123456)] && item.parts[0].tints == item.parts[1].tints)
        #expect(item.parts[0].model.guiLight == .front && !item.parts[0].model.ambientOcclusion)
    }

    @Test func halfTurnConjugatesExistingAxisAndEulerRotations() throws {
        let fixtures: [([String: Any], AssetModel.Rotation.Angles)] = [
            (["axis": "x", "angle": 45], .axis(.x, -45)),
            (["axis": "y", "angle": -22.5], .axis(.y, -22.5)),
            (["axis": "z", "angle": 45], .axis(.z, -45)),
            (["x": 30, "y": 45, "z": 15], .eulerXYZ(SIMD3(-30, 45, -15)))
        ]
        for (value, expected) in fixtures {
            var rotation = value; rotation["origin"] = [4, 5, 6]; rotation["rescale"] = true
            let item = try #require(assets(node(transform([0, -1, 0, 0])), rotation: rotation).defaultItemModel("test"))
            let transformed = try #require(element(item).rotation)
            #expect(transformed.origin == SIMD3(12, 5, 10))
            #expect(transformed.angles == expected && transformed.rescale)
        }
    }

    @Test func differentAxesComposeInParentOrderAndDoNotChangeSiblings() throws {
        let parent = transform([0, 1, 0, 0]), child = transform([1, 0, 0, 0], [0.25, 0.5, 0.75])
        let item = try #require(assets(["type": "composite", "transformation": parent,
                                       "models": [node(child), node()]]).defaultItemModel("test"))
        let composed = try element(item), sibling = try element(item, part: 1)
        #expect(composed.from == SIMD3(7, 1, 7) && composed.to == SIMD3(11, 6, 15))
        #expect(composed.faces[.down]?.material.texture.description == "minecraft:block/up")
        #expect(composed.faces[.east]?.material.texture.description == "minecraft:block/west")
        #expect(composed.faces[.north]?.material.texture.description == "minecraft:block/north")
        #expect(composed.faces.values.allSatisfy { $0.rotation == 270 })
        #expect(sibling.from == SIMD3(11, 2, 5) && sibling.to == SIMD3(15, 7, 13))
        let twice = try #require(assets(["type": "composite", "transformation": parent,
                                        "models": [node(parent)]]).defaultItemModel("test"))
        #expect(try twice == assets(node()).defaultItemModel("test"))
    }

    @Test func invertedSourceCornersKeepTheirOrderingThroughTranslationAndHalfTurn() throws {
        let shifted = try #require(assets(node(transform([0, 0, 0, 1])), inverted: true).defaultItemModel("test"))
        #expect(try element(shifted).from == SIMD3(21, 7, 27) && element(shifted).to == SIMD3(17, 2, 19))
        let turned = try #require(assets(node(transform([0, 1, 0, 0])), inverted: true).defaultItemModel("test"))
        #expect(try element(turned).from == SIMD3(15, 7, 13) && element(turned).to == SIMD3(11, 2, 5))
    }

    @Test func unsupportedRotationsScalesAndGeneratedLayersRemainUnavailable() throws {
        #expect(try assets(node()).defaultItemModel("test") != nil)
        for turn in [[0, 1, 0, 1], [1, 1, 0, 0], [0, 2, 0, 0]] {
            #expect(try assets(node(transform(turn))).defaultItemModel("test") == nil)
        }
        for scale in [[2, 1, 1], [1, 0, 1], [-1, 1, 1]] {
            var value = transform([0, 1, 0, 0]); value["scale"] = scale
            #expect(try assets(node(value)).defaultItemModel("test") == nil)
        }
        var right = transform([0, 1, 0, 0]); right["right_rotation"] = [0, 1, 0, 0]
        #expect(try assets(node(right)).defaultItemModel("test") == nil)
        var flat = node(transform([0, 1, 0, 0])); flat["model"] = "item/flat"
        #expect(try assets(flat).defaultItemModel("test") == nil)
    }

    private enum Invalid: Error { case geometry }
}
