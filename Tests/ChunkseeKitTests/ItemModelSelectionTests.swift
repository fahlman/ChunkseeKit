import ChunkseeKit
import Foundation
import Testing

@Suite struct ItemModelSelectionTests {
    private let plain = #"{"type":"model","model":"item/plain"}"#
    private let trimmed = #"{"type":"model","model":"item/trimmed","tints":[{"type":"dye","default":123}]}"#

    private func stack(_ material: NBT? = nil, extra: [String: NBT] = [:]) -> ItemStack {
        var components = extra
        if let material { components["minecraft:trim"] = .compound([
            "material": material, "pattern": .string("minecraft:sentry")
        ]) }
        return ItemStack(id: "sample", components: .compound(components))
    }

    private func selector(_ cases: String, fallback: String? = nil) -> String {
        "{\"type\":\"select\",\"property\":\"trim_material\",\"cases\":\(cases),\"fallback\":\(fallback ?? plain)}"
    }

    private func assets(_ definition: String, version: String = "26.3", dataVersion: Int = 5023) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: "{\"id\":\"\(version)\",\"world_version\":\(dataVersion)}"),
            .init(path: "assets/minecraft/items/sample.json", text: "{\"model\":\(definition)}"),
            .init(path: "assets/pack/items/override.json", text: "{\"model\":\(definition)}"),
            .init(path: "assets/minecraft/models/item/plain.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"item/plain"}}"#),
            .init(path: "assets/minecraft/models/item/trimmed.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"item/plain","layer1":"trims/items/custom"}}"#)
        ]))))
    }

    private func picture(_ item: ItemStack, in assets: GameAssets) throws -> AssetItem? {
        assets.itemModel(for: try #require(item.itemModelSelection))
    }

    @Test func savedAndLegacyMaterialKeysShareIdentifierAndModelReferenceOwners() throws {
        let modern = stack(.string(":quartz"), extra: ["minecraft:item_model": .string("pack:override")])
        let key = try #require(modern.itemModelSelection)
        #expect(key.modelID.description == "pack:override")
        #expect(key.trimMaterialID?.description == "minecraft:quartz")
        let legacy = try #require(ItemStack(.compound([
            "id": .string("sample"), "Count": .byte(1),
            "tag": .compound(["Trim": .compound(["material": .string("quartz"), "pattern": .string("sentry")])])
        ])))
        #expect(legacy.itemModelSelection == stack(.string("minecraft:quartz")).itemModelSelection)
        let removed = stack(.string("quartz"), extra: ["!minecraft:trim": .compound([:]),
                            "Trim": .compound(["material": .string("diamond")])])
        #expect(removed.itemModelSelection == stack().itemModelSelection)
        let overridden = stack(.string("gold"), extra: ["Trim": .compound(["material": .string("diamond")])])
        #expect(overridden.itemModelSelection?.trimMaterialID?.description == "minecraft:gold")
        for value in [NBT.string("broken"), .compound([:]), .compound(["material": .int(3)]),
                      .compound(["material": .string("Not valid")])] {
            let item = ItemStack(id: "sample", components: .compound([
                "minecraft:trim": value, "Trim": .compound(["material": .string("quartz")])
            ]))
            #expect(item.itemModelSelection == nil)
        }
        for key in ["minecraft:item_model", "!minecraft:item_model"] {
            #expect(stack(.string("quartz"), extra: [key: .compound([:])]).itemModelSelection == nil)
        }
        #expect(ItemStack(id: "sample", components: .int(3)).itemModelSelection == nil)
    }

    @Test func materialIdentityDoesNotInventAKeyFromAnInlineHolderOrUseThePattern() throws {
        let inline = NBT.compound(["palette_id": .string("quartz"), "description": .string("Quartz")])
        #expect(stack(inline).itemModelSelection == stack().itemModelSelection)
        let first = stack(.string("pack:custom"))
        let second = ItemStack(id: "sample", count: 99, customName: "Different name", components: .compound([
            "minecraft:trim": .compound(["material": .string("pack:custom"), "pattern": .string("coast")]),
            "minecraft:dyed_color": .int(0x123456)
        ]))
        #expect(first.itemModelSelection == second.itemModelSelection)
        #expect(first.itemModelSelection != stack(.string("quartz")).itemModelSelection)
        #expect(first.itemModelSelection != stack().itemModelSelection)
        #expect(Set([first.itemModelSelection, second.itemModelSelection, stack().itemModelSelection]).count == 2)
    }

    @Test func savedKeysSelectStringOrListCasesAndRetainTrimLayersAndTints() throws {
        for when in [#""quartz""#, #"["pack:other",":quartz"]"#] {
            let reader = try assets(selector("[{\"when\":\(when),\"model\":\(trimmed)}]"))
            let item = stack(.string("minecraft:quartz"), extra: ["minecraft:item_model": .string("pack:override")])
            let part = try #require(try picture(item, in: reader)?.parts.first)
            guard case .layers(let layers) = part.model.geometry else { Issue.record("Missing layers"); return }
            #expect(layers.map { $0.material.texture.description } == ["minecraft:item/plain", "minecraft:trims/items/custom"])
            #expect(part.tints == [.dye(defaultColor: 123)])
            #expect(try picture(stack(), in: reader) == reader.defaultItemModel("sample"))
            #expect(try picture(stack(.string("pack:unknown")), in: reader) == reader.defaultItemModel("sample"))
        }
    }

    @Test func nestedGUIAndCompositeBranchesUseTheSameSavedSelection() throws {
        let trim = selector("[{\"when\":\"pack:custom\",\"model\":\(trimmed)}]")
        let gui = "{\"type\":\"select\",\"property\":\"display_context\",\"cases\":[{\"when\":\"gui\",\"model\":\(trim)}],\"fallback\":{\"type\":\"empty\"}}"
        let live = "{\"type\":\"condition\",\"property\":\"using_item\",\"on_true\":{\"type\":\"unavailable\"},\"on_false\":\(gui)}"
        let reader = try assets("{\"type\":\"composite\",\"models\":[\(live),\(trim)]}")
        let selected = try #require(try picture(stack(.string("pack:custom")), in: reader))
        #expect(selected.parts.count == 2)
        #expect(selected.parts[0] == selected.parts[1])
        #expect(selected.parts.allSatisfy { $0.tints == [.dye(defaultColor: 123)] })
    }

    @Test func unsupportedSelectedModelsDoNotSilentlyRecoverTheFallback() throws {
        for child in [#"{"type":"model","model":"item/missing"}"#, #"{"type":"pack:unsupported"}"#] {
            let reader = try assets(selector("[{\"when\":\"quartz\",\"model\":\(child)}]"))
            #expect(try picture(stack(.string("quartz")), in: reader) == nil)
            #expect(try picture(stack(), in: reader) != nil)
            #expect(reader.defaultItemModel("sample") != nil)
        }
        let empty = try assets(selector(#"[{"when":"quartz","model":{"type":"empty"}}]"#))
        #expect(try picture(stack(.string("quartz")), in: empty)?.parts.isEmpty == true)
    }

    @Test func malformedAndUnboundedCaseTablesAreRejectedAfterIdentifierNormalization() throws {
        let one = "{\"when\":\"quartz\",\"model\":\(trimmed)}"
        let duplicate = "{\"when\":\"minecraft:quartz\",\"model\":\(plain)}"
        for cases in ["[]", "null", "{}", "[{}]", "[\(one),\(duplicate)]",
                      #"[{"when":["quartz",false]}]"#, #"[{"when":"Not valid"}]"#,
                      "[\(Array(repeating: one, count: 4097).joined(separator: ","))]"] {
            #expect(try picture(stack(.string("quartz")), in: assets(selector(cases))) == nil)
        }
        var nested = selector("[\(one)]")
        for _ in 0..<64 { nested = "{\"type\":\"condition\",\"property\":\"using_item\",\"on_false\":\(nested)}" }
        #expect(try picture(stack(.string("quartz")), in: assets(nested)) == nil)
    }

    @Test func unverifiedTrimVersionsStayUnavailableWithoutChangingTheDefaultReader() throws {
        let definition = selector("[{\"when\":\"quartz\",\"model\":\(trimmed)}]")
        for (name, version) in [("fixture", 5023), ("26.3", 5000)] {
            let reader = try assets(definition, version: name, dataVersion: version)
            #expect(try picture(stack(.string("quartz")), in: reader) == nil)
            #expect(reader.defaultItemModel("sample") != nil)
            #expect(try picture(stack(), in: assets(plain, version: name, dataVersion: version)) != nil)
        }
        let unrelated = definition.replacingOccurrences(of: "\"trim_material\"", with: "\"pack:trim_material\"")
        let reader = try assets(unrelated)
        #expect(try picture(stack(.string("quartz")), in: reader) == reader.defaultItemModel("sample"))
    }

    @Test func cachedStacksRetainTheirSelectionWithoutAddingSerializedFields() throws {
        let item = stack(.string("quartz"), extra: ["minecraft:item_model": .string("pack:override")])
        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(ItemStack.self, from: data)
        #expect(restored == item)
        #expect(restored.itemModelSelection == item.itemModelSelection)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(!fields.keys.contains("itemModelSelection"))
    }
}
