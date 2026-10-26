import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct ItemModelTests {
    private func stack(_ components: NBT? = nil, id: String = "minecraft:stone") -> ItemStack {
        ItemStack(id: id, components: components)
    }

    @Test func defaultAndSavedReferencesUseTheSharedIdentifierCodec() {
        #expect(stack().itemModelID?.description == "minecraft:stone")
        #expect(stack(.compound([:]), id: "stone").itemModelID?.description == "minecraft:stone")
        #expect(stack(id: "example:item").itemModelID?.description == "example:item")
        for (saved, expected) in [("diamond", "minecraft:diamond"), (":stick", "minecraft:stick"),
                                  ("pack:alternate/picture", "pack:alternate/picture")] {
            let item = stack(.compound(["minecraft:item_model": .string(saved)]))
            #expect(item.itemModelID?.description == expected)
            #expect(item.id == "minecraft:stone")
        }
    }

    @Test func removedAndMalformedReferencesNeverRecoverTheOrdinaryPicture() {
        let removed = NBT.compound([:])
        #expect(stack(.compound(["!minecraft:item_model": removed])).itemModelID == nil)
        #expect(stack(.compound(["!minecraft:item_model": removed,
                                "minecraft:item_model": .string("diamond")])).itemModelID == nil)
        for value in [NBT.int(1), .compound([:]), .list(.string, [.string("diamond")]),
                      .string("Uppercase"), .string("two:colons:invalid"), .string("not an id")] {
            #expect(stack(.compound(["minecraft:item_model": value])).itemModelID == nil)
        }
        #expect(stack(.string("malformed components")).itemModelID == nil)
        #expect(stack(id: "not an id").itemModelID == nil)
        // Codec-valid does not imply an installed or file-safe resource. Asset lookup owns that check.
        #expect(stack(.compound(["minecraft:item_model": .string("pack:../missing")]))
            .itemModelID?.description == "pack:../missing")
    }

    @Test func savedAndCachedStacksKeepTheReferenceWithoutNewStoredFields() throws {
        let modern = try #require(ItemStack(.compound([
            "id": .string("minecraft:stone"), "count": .int(1),
            "components": .compound(["minecraft:item_model": .string("pack:alternate")])
        ])))
        let legacy = try #require(ItemStack(.compound([
            "id": .string("minecraft:stone"), "Count": .byte(1),
            "tag": .compound(["CustomModelData": .int(7)])
        ])))
        #expect(modern.itemModelID?.description == "pack:alternate")
        #expect(legacy.itemModelID?.description == "minecraft:stone")
        for item in [modern, legacy, stack(.compound(["!minecraft:item_model": .compound([:])]))] {
            let data = try JSONEncoder().encode(item)
            let restored = try JSONDecoder().decode(ItemStack.self, from: data)
            #expect(restored == item && restored.itemModelID == item.itemModelID)
            let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(!fields.keys.contains("itemModelID"))
        }
    }

    @Test func savedReferenceSelectsAnItemDefinitionThroughTheExistingAssetReader() throws {
        let assets = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#),
            .init(path: "assets/pack/items/alternate.json", text: #"{"model":{"type":"model","model":"pack:item/alternate"}}"#),
            .init(path: "assets/pack/models/item/alternate.json", text: #"{"parent":"minecraft:builtin/generated","textures":{"layer0":"pack:item/picture"}}"#)
        ]))))
        let item = stack(.compound(["minecraft:item_model": .string("pack:alternate")]))
        let reference = try #require(item.itemModelID)
        let picture = try #require(assets.defaultItemModel(reference.description))
        guard case .layers(let layers) = picture.parts.first?.model.geometry else { Issue.record("Missing selected layers"); return }
        #expect(layers.first?.material.texture.description == "pack:item/picture")
        #expect(assets.defaultItemModel(item.id) == nil)
        #expect(assets.defaultItemModel("pack:../alternate") == nil)
    }
}
