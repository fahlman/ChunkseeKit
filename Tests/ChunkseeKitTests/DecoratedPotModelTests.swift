import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct DecoratedPotModelTests {
    private let patterns = ["angler", "archer", "arms_up", "blade", "brewer", "burn", "danger", "explorer",
                            "flow", "friend", "guster", "heart", "heartbreak", "howl", "miner", "mourner",
                            "plenty", "prize", "scrape", "sheaf", "shelter", "skull", "snort"]

    private func node() -> [String: Any] {
        ["type": "special", "base": "item/pot", "model": ["type": "decorated_pot"]]
    }

    private func assets(_ value: [String: Any]? = nil, version: String = "26.3", dataVersion: Int = 5023,
                        extras: [TestZIP.Entry] = [], includePatterns: Bool = true) throws -> GameAssets {
        var entries: [TestZIP.Entry] = [
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/decorated_pot.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": value ?? node()]), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/pot.json", text:
                #"{"gui_light":"front","display":{"gui":{"rotation":[30,45,0],"scale":[0.6,0.6,0.6]}}}"#),
            .init(path: "assets/minecraft/items/stone.json", text: #"{"model":{"type":"empty"}}"#)
        ]
        if includePatterns {
            entries += patterns.map { .init(path: "data/minecraft/decorated_pot_pattern/\($0).json",
                                            text: "{\"asset_id\":\"minecraft:\($0)_pottery_pattern\"}") }
        }
        return try #require(GameAssets(data: Data(TestZIP.zip(entries + extras))))
    }

    private func selection(_ sides: [String: NBT]) throws -> ItemModelSelection {
        try #require(ItemStack(id: "decorated_pot", components: .compound([
            "minecraft:pot_decorations": .compound(sides)])).itemModelSelection)
    }

    private func elements(_ item: AssetItem) throws -> [AssetModel.Element] {
        guard item.parts.count == 1, case .elements(let elements) = item.parts[0].model.geometry else { throw Invalid.model }
        return elements
    }

    private func sideFace(_ direction: AssetModel.Direction, in boxes: [AssetModel.Element]) throws -> AssetModel.Face {
        let sides = boxes.filter { $0.faces.count == 1 && $0.faces[direction] != nil }
        #expect(sides.count == 1)
        return try #require(sides.first?.faces[direction])
    }

    @Test func plainPotKeepsItsNeckRimCapsAndFourOutwardSides() throws {
        let reader = try assets(), item = try #require(reader.defaultItemModel("decorated_pot"))
        let boxes = try elements(item)
        #expect(boxes.count == 8 && boxes.reduce(0, { $0 + $1.faces.count }) == 28)
        #expect(item.parts[0].model.guiLight == .front)
        #expect(item.parts[0].model.guiTransform.rotation == SIMD3(30, 45, 0))
        #expect(item.parts[0].model.guiTransform.scale == SIMD3(repeating: 0.6))
        let neck = try #require(boxes.first { abs($0.from.y - 17.1) < 0.00001 })
        #expect((0..<3).allSatisfy { abs(neck.from[$0] - SIMD3<Float>(4.1, 17.1, 4.1)[$0]) < 0.00001 })
        #expect((0..<3).allSatisfy { abs(neck.to[$0] - SIMD3<Float>(11.9, 19.9, 11.9)[$0]) < 0.00001 })
        #expect(boxes.contains { $0.from == SIMD3(1, 16, 1) && $0.to == SIMD3(15, 16, 15) })
        #expect(boxes.contains { $0.from == SIMD3(1, 0, 1) && $0.to == SIMD3(15, 0, 15) })
        #expect(boxes.filter { $0.faces.count == 6 }.flatMap { $0.faces.values }.allSatisfy {
            $0.material.texture.description == "minecraft:entity/decorated_pot/decorated_pot_base"
        })
        for direction in [AssetModel.Direction.north, .west, .east, .south] {
            let face = try sideFace(direction, in: boxes)
            #expect(face.material.texture.description == "minecraft:entity/decorated_pot/decorated_pot_side")
            #expect(face.uv == SIMD4(1, 0, 15, 16) && face.rotation == 0)
            #expect(face.tintIndex == nil && face.cullFace == nil && face.material.overlays.isEmpty)
        }
        #expect(reader.itemModel(for: try selection([:])) == item)
        #expect(reader.texture("entity/decorated_pot/decorated_pot_base") == nil)
    }

    @Test func allVerifiedDefaultSherdsResolveThroughTheJarOnTheRequestedSide() throws {
        let reader = try assets()
        for pattern in patterns {
            let item = try #require(reader.itemModel(for: selection(["back": .string(pattern + "_pottery_sherd")])))
            let boxes = try elements(item)
            #expect(try sideFace(.north, in: boxes).material.texture.description == "minecraft:entity/decorated_pot/\(pattern)_pottery_pattern")
            #expect(try sideFace(.south, in: boxes).material.texture.description == "minecraft:entity/decorated_pot/decorated_pot_side")
        }
        #expect(try assets(includePatterns: false).itemModel(for: selection(["front": .string("angler_pottery_sherd")])) == nil)
        #expect(reader.itemModel(for: try selection(["front": .string("pack:unknown")])) == nil)
        #expect(reader.itemModel(for: try selection(["front": .string("unknown_pottery_sherd")])) == nil)
        #expect(reader.itemModel(for: try selection(["front": .string("stone")])) == reader.defaultItemModel("decorated_pot"))
    }

    @Test func explicitNamedInlineAndRemovedPatternsReplaceItemDefaults() throws {
        let reader = try assets(extras: [.init(path: "data/pack/decorated_pot_pattern/sky.json", text: #"{"asset_id":"pack:stars"}"#)])
        func side(_ id: String, _ pattern: NBT) -> NBT {
            .compound(["id": .string(id), "components": .compound(["minecraft:provides_pottery_pattern": pattern])])
        }
        let item = try #require(reader.itemModel(for: selection([
            "left": side("brick", .string("pack:sky")),
            "right": side("angler_pottery_sherd", .compound(["asset_id": .string("pack:moon")])),
            "front": .compound(["id": .string("archer_pottery_sherd"), "components": .compound([
                "!minecraft:provides_pottery_pattern": .compound([:])])])
        ])))
        let boxes = try elements(item)
        #expect(try sideFace(.west, in: boxes).material.texture.description == "pack:entity/decorated_pot/stars")
        #expect(try sideFace(.east, in: boxes).material.texture.description == "pack:entity/decorated_pot/moon")
        #expect(try sideFace(.south, in: boxes).material.texture.description == "minecraft:entity/decorated_pot/decorated_pot_side")
        for pattern in [NBT.string("pack:missing"), .string("pack:../unsafe"), .compound(["asset_id": .string("../unsafe")])] {
            #expect(reader.itemModel(for: try selection(["front": side("brick", pattern)])) == nil)
        }
        let bad = try assets(extras: [.init(path: "data/pack/decorated_pot_pattern/sky.json", text: #"{"asset_id":17}"#)])
        #expect(bad.itemModel(for: try selection(["front": side("brick", .string("pack:sky"))])) == nil)
    }

    @Test func inheritedTransformsAndCommonBudgetsStillApply() throws {
        let transform: [String: Any] = ["left_rotation": [0, 0, 0, 1], "right_rotation": [0, 0, 0, 1],
                                        "scale": [0.5, 0.5, 0.5], "translation": [0.25, 0, 0]]
        let ordinary = try elements(#require(assets().defaultItemModel("decorated_pot")))
        let reader = try assets(["type": "composite", "models": [node()], "transformation": transform])
        let scaled = try elements(#require(reader.defaultItemModel("decorated_pot")))
        for (a, b) in zip(ordinary, scaled) {
            #expect(b.from == a.from * 0.5 + SIMD3(4, 0, 0))
            #expect(b.to == a.to * 0.5 + SIMD3(4, 0, 0))
            #expect(b.faces == a.faces)
        }
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(version: name, dataVersion: version).defaultItemModel("decorated_pot") != nil)
        }
        #expect(try assets(["type": "composite", "models": Array(repeating: node(), count: 33)]).defaultItemModel("decorated_pot") == nil)
        var invalid = node(); invalid["base"] = "item/missing"
        #expect(try assets(invalid).defaultItemModel("decorated_pot") == nil)
    }

    private enum Invalid: Error { case model }
}
