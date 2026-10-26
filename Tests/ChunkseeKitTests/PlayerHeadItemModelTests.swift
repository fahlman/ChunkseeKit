import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct PlayerHeadItemModelTests {
    private let transform: [String: Any] = ["left_rotation": [1, 0, 0, 0], "right_rotation": [0, 0, 0, 1],
                                           "scale": [1, 1, 1], "translation": [0.5, 0, 0.5]]

    private func node() -> [String: Any] {
        ["type": "special", "base": "item/skull", "transformation": transform,
         "model": ["type": "player_head"]]
    }

    private func assets(_ node: [String: Any]? = nil, version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/pack/items/sample.json", text: String(decoding:
                try JSONSerialization.data(withJSONObject: ["model": node ?? self.node()]), as: UTF8.self)),
            .init(path: "assets/minecraft/models/item/skull.json", text:
                #"{"display":{"gui":{"rotation":[30,45,0],"translation":[0,3,0],"scale":[1,1,1]}}}"#),
            .init(path: "assets/minecraft/models/item/plain.json", text:
                #"{"parent":"builtin/generated","textures":{"layer0":"item/plain"}}"#),
            .init(path: "assets/minecraft/textures/entity/player/slim/steve.png", text: "default skin"),
            .init(path: "assets/pack/textures/heads/custom.png", text: "local profile skin")
        ]))))
    }

    private func stack(_ profile: NBT? = nil, extra: [String: NBT] = [:]) -> ItemStack {
        var components = extra
        components["minecraft:item_model"] = .string("pack:sample")
        if let profile { components["minecraft:profile"] = profile }
        return ItemStack(id: "unrelated_item", components: .compound(components))
    }

    private func picture(_ stack: ItemStack, in assets: GameAssets) -> AssetItem? {
        stack.itemModelSelection.flatMap { assets.itemModel(for: $0) }
    }

    private func boxes(_ item: AssetItem?) throws -> [AssetModel.Element] {
        let item = try #require(item)
        guard item.parts.count == 1, case .elements(let result) = item.parts[0].model.geometry else { throw Invalid.model }
        return result
    }

    @Test func missingRemovedAndLegacyProfilesRemainDistinct() throws {
        #expect(ItemStack(id: "player_head").headSkin == .defaultSkin)
        for profile: NBT in [.string("Someone"), .compound([:]),
                             .compound(["id": .intArray([1, 2, 3, 4])]),
                             .compound(["properties": .list(.compound, [.compound(["name": .string("textures"),
                                                                                   "value": .string("saved URL data")])])])] {
            #expect(stack(profile).headSkin == .unresolved)
            #expect(picture(stack(profile), in: try assets()) == nil)
        }
        let legacy = try #require(ItemStack(.compound([
            "id": .string("minecraft:player_head"), "Count": .byte(1),
            "tag": .compound(["SkullOwner": .compound(["Name": .string("Someone")])])
        ])))
        #expect(legacy.headSkin == .unresolved)
        let removed = stack(.int(3), extra: ["!minecraft:profile": .compound([:]), "SkullOwner": .int(4)])
        #expect(removed.headSkin == .defaultSkin)
        #expect(removed.itemModelSelection != stack().itemModelSelection)
        #expect(try picture(removed, in: assets()) == picture(stack(), in: assets()))
        #expect(stack(.compound(["texture": .string("pack:heads/custom")]),
                      extra: ["SkullOwner": .int(4)]).headSkin == .resource(try #require(Identifier("pack:heads/custom"))))
        #expect(stack(extra: ["SkullOwner": .int(4)]).headSkin == nil)
    }

    @Test func onlyTheBodyResourceChangesLocalSkinIdentity() throws {
        let first = stack(.compound(["texture": .string("entity/player/slim/steve")]))
        let same = stack(.compound(["texture": .string("minecraft:entity/player/slim/steve"),
                                   "name": .string("Different name"), "cape": .string("pack:cape"),
                                   "elytra": .string("pack:wings"), "model": .string("wide")]))
        #expect(first.itemModelSelection == same.itemModelSelection)
        let other = stack(.compound(["texture": .string("pack:heads/custom")]))
        #expect(first.itemModelSelection != other.itemModelSelection)
        #expect(Set([first.itemModelSelection, same.itemModelSelection, other.itemModelSelection]).count == 2)
        #expect(first.itemModelSelection?.headSkin == first.headSkin)
    }

    @Test func defaultAndLocalHeadsUseTheSuppliedSkinAndSharedHumanoidGeometry() throws {
        let reader = try assets()
        let plain = try #require(reader.defaultItemModel("pack:sample"))
        #expect(picture(stack(), in: reader) == plain)
        let local = stack(.compound(["texture": .string("pack:heads/custom")]))
        for (item, path, data) in [(plain, "minecraft:entity/player/slim/steve", "default skin"),
                                   (try #require(picture(local, in: reader)), "pack:heads/custom", "local profile skin")] {
            let elements = try boxes(item), model = item.parts[0].model
            #expect(elements.count == 2)
            #expect(elements[0].from == SIMD3(4, 0, 4) && elements[0].to == SIMD3(12, 8, 12))
            #expect(elements[1].from == SIMD3(3.75, -0.25, 3.75) && elements[1].to == SIMD3(12.25, 8.25, 12.25))
            #expect(elements[0].faces[.up]?.uv == SIMD4(2, 0, 4, 2))
            #expect(elements[1].faces[.up]?.uv == SIMD4(10, 0, 12, 2))
            for face in elements.flatMap({ $0.faces.values }) {
                #expect(face.material.texture.description == path)
                #expect(face.material.forceTranslucent && face.material.staticTextureAspectRatio == 1)
                #expect(face.material.overlays.isEmpty && face.tintIndex == nil && face.cullFace == nil)
            }
            #expect(reader.texture(path) == Data(data.utf8))
            #expect(model.guiTransform.rotation == SIMD3(30, 45, 0))
            #expect(model.guiTransform.translation == SIMD3(0, 0.1875, 0) && model.guiTransform.scale == .one)
        }
    }

    @Test func unresolvedSkinsDoNotPreventUnrelatedModelsAndMissingImagesKeepTheFallback() throws {
        let ordinary = try assets(["type": "model", "model": "item/plain"])
        #expect(picture(stack(.string("Someone")), in: ordinary) == ordinary.defaultItemModel("pack:sample"))
        let missing = stack(.compound(["texture": .string("pack:heads/missing")]))
        let reader = try assets(), elements = try boxes(picture(missing, in: reader))
        #expect(elements[0].faces[.up]?.material.texture.description == "pack:heads/missing")
        #expect(reader.texture("pack:heads/missing") == nil)
    }

    @Test func malformedProfilesAndUnsafeResourcePathsDoNotProducePictures() throws {
        let reader = try assets()
        for raw: NBT in [.int(4), .list(.string, []), .compound(["texture": .int(4)]),
                         .compound(["texture": .string("Not a resource")]),
                         .compound(["texture": .string(String(repeating: "a", count: 16 * 1024 * 1024 + 1))])] {
            #expect(stack(raw).headSkin == nil && stack(raw).itemModelSelection == nil)
            #expect(picture(stack(raw), in: reader) == nil)
        }
        #expect(ItemStack(id: "player_head", components: .int(3)).headSkin == nil)
        for path in ["", "../secret", "pack:../secret", "/absolute", "pack:a//b"] {
            let item = stack(.compound(["texture": .string(path)]))
            // Identifier syntax is separate from safe resource paths, owned by GameAssets.
            #expect(item.headSkin != nil)
            #expect(picture(item, in: reader) == nil)
        }
    }

    @Test func playerHeadsIgnoreVersionLabelsAndKeepTransformAndItemLimits() throws {
        for (name, version) in [("26.2", 4903), ("26.4", 5023), ("26.3", 9999)] {
            #expect(try assets(version: name, dataVersion: version).defaultItemModel("pack:sample") != nil)
        }
        var changed = node(), unsupported = transform
        unsupported["translation"] = [100, 0, 0]; changed["transformation"] = unsupported
        #expect(try assets(changed).defaultItemModel("pack:sample") == nil)
        changed = node(); changed["base"] = "item/absent"
        #expect(try assets(changed).defaultItemModel("pack:sample") == nil)
        #expect(try assets(["type": "composite", "models": Array(repeating: node(), count: 33)])
            .defaultItemModel("pack:sample") == nil)
    }

    private enum Invalid: Error { case model }
}
