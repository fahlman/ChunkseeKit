import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct HeadItemModelTests {
    private let transform: [String: Any] = ["left_rotation": [1, 0, 0, 0], "right_rotation": [0, 0, 0, 1],
                                           "scale": [1, 1, 1], "translation": [0.5, 0, 0.5]]

    private func node(_ kind: Any = "skeleton", extra: [String: Any] = [:]) -> [String: Any] {
        ["type": "special", "base": "item/skull", "transformation": transform,
         "model": ["type": "head", "kind": kind].merging(extra) { _, replacement in replacement }]
    }

    private func assets(_ node: [String: Any], version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/pack/items/sample.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": node]), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/skull.json", text:
                #"{"display":{"gui":{"rotation":[30,45,0],"translation":[0,3,0],"scale":[1,1,1]}}}"#),
            .init(path: "assets/pack/textures/entity/heads/custom.png", text: "supplied skin bytes")
        ]))))
    }

    private func boxes(_ item: AssetItem) throws -> [AssetModel.Element] {
        guard item.parts.count == 1, case .elements(let value) = item.parts[0].model.geometry else { throw Invalid.model }
        return value
    }

    @Test func selectedKindsShareGeometryMaterialsAndTheSuppliedGUI() throws {
        for (kind, count, path) in [("skeleton", 1, "skeleton/skeleton"), ("wither_skeleton", 1, "skeleton/wither_skeleton"),
                                   ("zombie", 2, "zombie/zombie"), ("creeper", 1, "creeper/creeper"),
                                   ("dragon", 7, "enderdragon/dragon"), ("piglin", 6, "piglin/piglin")] {
            let reader = try assets(node(kind)), item = try #require(reader.defaultItemModel("pack:sample"))
            let elements = try boxes(item), model = item.parts[0].model
            #expect(elements.count == count && elements.allSatisfy { $0.faces.count == 6 })
            #expect(elements.flatMap { $0.faces.values }.allSatisfy {
                $0.material.texture.description == "minecraft:entity/\(path)" && $0.material.overlays.isEmpty
                    && !$0.material.forceTranslucent && $0.tintIndex == nil && $0.cullFace == nil
            })
            #expect(model.guiTransform.rotation == SIMD3(30, 45, 0))
            #expect(model.guiTransform.translation == SIMD3(0, 0.1875, 0) && model.guiTransform.scale == .one)
            #expect(elements.contains { $0.rotation != nil } == (kind == "dragon" || kind == "piglin"))
            // Absent skin bytes remain the client's usual picture fallback, without changing geometry.
            #expect(reader.texture("minecraft:entity/\(path)") == nil)
            let selection = try #require(ItemStack(id: "unrelated", components: .compound([
                "minecraft:item_model": .string("pack:sample")
            ])).itemModelSelection)
            #expect(reader.itemModel(for: selection) == item)
        }
    }

    @Test func rectangularSkinsAndInflatedLayersKeepTheirNominalUVs() throws {
        let skeleton = try boxes(#require(assets(node()).defaultItemModel("pack:sample")))[0]
        #expect(skeleton.from == SIMD3(4, 0, 4) && skeleton.to == SIMD3(12, 8, 12))
        #expect(skeleton.faces[.up]?.uv == SIMD4(2, 0, 4, 4))
        let zombie = try boxes(#require(assets(node("zombie")).defaultItemModel("pack:sample")))
        #expect(zombie[0].faces[.up]?.uv == SIMD4(2, 0, 4, 2))
        #expect(zombie[1].from == SIMD3(3.75, -0.25, 3.75) && zombie[1].to == SIMD3(12.25, 8.25, 12.25))
        #expect(zombie[1].faces[.up]?.uv == SIMD4(10, 0, 12, 2))
    }

    @Test func mirroredDragonSkinsAndPhaseZeroRotationsComposeWithTheItem() throws {
        let dragon = try boxes(#require(assets(node("dragon")).defaultItemModel("pack:sample")))
        let horn = dragon[2]
        #expect(horn.faces[.east]?.textureCoordinates == [SIMD2<Float>(0.375, 0.375), SIMD2(0.375, 0.625),
            SIMD2(0, 0.625), SIMD2(0, 0.375)].map { $0 / 16 })
        #expect(horn.faces[.west]?.textureCoordinates == [SIMD2<Float>(0.875, 0.375), SIMD2(0.875, 0.625),
            SIMD2(0.5, 0.625), SIMD2(0.5, 0.375)].map { $0 / 16 })
        #expect(horn.faces[.up]?.textureCoordinates == [SIMD2<Float>(0.5, 0), SIMD2(0.5, 0.375),
            SIMD2(0.375, 0.375), SIMD2(0.375, 0)].map { $0 / 16 })
        #expect(dragon[4].faces[.west]?.uv == SIMD4(0, 0.375, 0.375, 0.625))
        let jaw = try #require(dragon.last?.rotation)
        guard case .axis(.x, let jawAngle) = jaw.angles else { throw Invalid.model }
        #expect(abs(jawAngle - 0.2 * 180 / .pi) < 0.00001 && !jaw.rescale)
        #expect(abs(jaw.origin.y - 2.99) < 0.00001 && jaw.origin.x == 8 && jaw.origin.z == 14)
        let piglin = try boxes(#require(assets(node("piglin")).defaultItemModel("pack:sample")))
        for (originX, expectedAngle): (Float, Float) in [(3.5, -0.7 * 180 / .pi), (12.5, 0.7 * 180 / .pi)] {
            let ear = try #require(piglin.first { $0.rotation?.origin == SIMD3(originX, 6, 8) }?.rotation)
            guard case .axis(.z, let angle) = ear.angles else { throw Invalid.model }
            #expect(abs(angle - expectedAngle) < 0.00001)
        }
    }

    @Test func textureOverridesKeepTheirNamespaceAndInvalidDefinitionsStayUnavailable() throws {
        let reader = try assets(node("piglin", extra: ["texture": "pack:heads/custom", "animation": 0]))
        let model = try #require(reader.defaultItemModel("pack:sample"))
        #expect(try boxes(model).flatMap { $0.faces.values }.allSatisfy {
            $0.material.texture.description == "pack:entity/heads/custom"
        })
        #expect(reader.texture("pack:entity/heads/custom") == Data("supplied skin bytes".utf8))
        for kind: Any in ["player", "minecraft:skeleton", "SKELETON", "unknown", 4, NSNull()] {
            #expect(try assets(node(kind)).defaultItemModel("pack:sample") == nil)
        }
        for value: Any in [1, -1, 0.5, "0", true, NSNull()] {
            #expect(try assets(node(extra: ["animation": value])).defaultItemModel("pack:sample") == nil)
        }
        for value: Any in ["../secret", "pack:../secret", "", 4, NSNull()] {
            #expect(try assets(node(extra: ["texture": value])).defaultItemModel("pack:sample") == nil)
        }
        var missing = node(); missing["model"] = ["type": "head"]
        #expect(try assets(missing).defaultItemModel("pack:sample") == nil)
    }

    @Test func versionsTransformsAndWholeItemBudgetsUseTheExistingLimits() throws {
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(node(), version: name, dataVersion: version).defaultItemModel("pack:sample") != nil)
        }
        var changed = node("piglin"), unsupported = transform
        unsupported["scale"] = [2, 1, 1]; changed["transformation"] = unsupported
        #expect(try assets(changed).defaultItemModel("pack:sample") == nil)
        unsupported = transform; unsupported["translation"] = [100, 0, 0]; changed["transformation"] = unsupported
        #expect(try assets(changed).defaultItemModel("pack:sample") == nil)
        changed = node(); changed["base"] = "item/absent"
        #expect(try assets(changed).defaultItemModel("pack:sample") == nil)
        #expect(try assets(["type": "composite", "models": Array(repeating: node(), count: 33)])
            .defaultItemModel("pack:sample") == nil)
    }

    private enum Invalid: Error { case model }
}
