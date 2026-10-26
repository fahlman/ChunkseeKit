import ChunkseeKitTestSupport
import ChunkseeKit
import Foundation
import Testing

@Suite struct SavedItemModelPropertiesTests {
    private let plain = #"{"type":"model","model":"item/plain"}"#
    private let selected = #"{"type":"model","model":"item/selected"}"#

    private func assets(_ node: String) throws -> GameAssets {
        try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"future-format-fixture","world_version":999999}"#),
            .init(path: "assets/pack/items/picture.json", text: "{\"model\":\(node)}"),
            .init(path: "assets/minecraft/models/item/plain.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"item/plain"}}"#),
            .init(path: "assets/minecraft/models/item/selected.json", text: #"{"parent":"builtin/generated","textures":{"layer0":"item/selected"}}"#)
        ]))))
    }

    private func stack(_ components: [String: NBT] = [:], id: String = "minecraft:crossbow") -> ItemStack {
        var values = components
        values["minecraft:item_model"] = .string("pack:picture")
        return ItemStack(id: id, components: .compound(values))
    }

    private func picture(_ item: ItemStack, _ assets: GameAssets) throws -> String? {
        guard let part = assets.itemModel(for: try #require(item.itemModelSelection))?.parts.first,
              case .layers(let layers) = part.model.geometry else { return nil }
        return layers.first?.material.texture.path
    }

    private func condition(_ property: String, fields: String = "") -> String {
        "{\"type\":\"condition\",\"property\":\"\(property)\",\"on_true\":\(selected),\"on_false\":\(plain)\(fields)}"
    }

    private func select(_ property: String, when: String, fields: String = "") -> String {
        "{\"type\":\"select\",\"property\":\"\(property)\",\"cases\":[{\"when\":\"\(when)\",\"model\":\(selected)}],\"fallback\":\(plain)\(fields)}"
    }

    @Test func savedBlockPropertiesOverrideDefaultsAndKeepIndependentReadableValues() throws {
        let reader = try assets(select("block_state", when: "5", fields: #", "block_state_property":"honey_level""#))
        let full = stack(["minecraft:block_state": .compound(["honey_level": .string("5"), "unreadable": .int(1)])], id: "pack:hive")
        #expect(try picture(full, reader) == "item/selected")
        #expect(try picture(stack([:], id: "minecraft:beehive"), reader) == "item/plain")
        #expect(try picture(stack([:], id: "pack:unknown"), reader) == nil)
        #expect(try picture(stack(["BlockStateTag": .compound(["honey_level": .string("5")])]), reader) == "item/selected")
        #expect(try picture(stack(["minecraft:block_state": .compound(["honey_level": .int(5)])]), reader) == nil)
        #expect(try picture(stack(["minecraft:block_state": .int(5), "BlockStateTag": .compound(["honey_level": .string("5")])]), reader) == nil)
        #expect(try picture(stack(["!minecraft:block_state": .compound([:]), "minecraft:block_state": .int(5),
                                  "BlockStateTag": .compound(["honey_level": .string("5")])]), reader) == "item/plain")
        #expect(try picture(full, assets(select("block_state", when: "1", fields: #", "block_state_property":"unreadable""#))) == nil)
    }

    @Test func componentConditionsUsePrototypePresenceAndSavedAdditionsOrRemovals() throws {
        let dye = try assets(condition("has_component", fields: #", "component":"dyed_color""#))
        #expect(try picture(stack([:], id: "minecraft:wolf_armor"), dye) == "item/plain")
        #expect(try picture(stack(["minecraft:dyed_color": .int(0)], id: "minecraft:wolf_armor"), dye) == "item/selected")
        #expect(try picture(stack(["display": .compound(["color": .int(0)])], id: "minecraft:wolf_armor"), dye) == "item/selected")
        #expect(try picture(stack(["!minecraft:dyed_color": .compound([:]), "minecraft:dyed_color": .int(0)], id: "minecraft:wolf_armor"), dye) == "item/plain")
        let damage = try assets(condition("has_component", fields: #", "component":"damage""#))
        #expect(try picture(stack(), damage) == "item/selected")
        #expect(try picture(stack(["!minecraft:damage": .compound([:])]), damage) == "item/plain")
        #expect(try picture(stack([:], id: "pack:unknown"), damage) == nil)
        #expect(try picture(stack(["minecraft:damage": .int(0)], id: "pack:unknown"), damage) == "item/selected")
    }

    @Test func ignoringDefaultsOnlyClaimsWhatTheSavedPatchAndPrototypeEstablish() throws {
        let damage = try assets(condition("has_component", fields: #", "component":"damage", "ignore_default":true"#))
        #expect(try picture(stack(), damage) == "item/plain")
        #expect(try picture(stack(["!minecraft:damage": .compound([:])]), damage) == "item/selected")
        #expect(try picture(stack(["minecraft:damage": .int(0)]), damage) == nil)
        let dye = try assets(condition("has_component", fields: #", "component":"dyed_color", "ignore_default":true"#))
        #expect(try picture(stack(["minecraft:dyed_color": .int(0)]), dye) == "item/selected")
        #expect(try picture(stack(["!minecraft:dyed_color": .compound([:])]), dye) == "item/plain")
        #expect(try picture(stack(["minecraft:dyed_color": .int(0)], id: "pack:unknown"), dye) == nil)
        #expect(try picture(stack(), assets(condition("has_component", fields: #", "component":"damage", "ignore_default":1"#))) == nil)
    }

    @Test func brokenUsesTheNextDamageThresholdAndSharedDurabilityRules() throws {
        let reader = try assets(condition("broken"))
        for (damage, expected) in [(8, "item/plain"), (9, "item/selected"), (10, "item/selected")] {
            #expect(try picture(stack(["minecraft:max_damage": .int(10), "minecraft:damage": .int(Int32(damage))], id: "pack:wing"), reader) == expected)
        }
        #expect(try picture(stack(["minecraft:damage": .int(431)], id: "elytra"), reader) == "item/selected")
        #expect(try picture(stack(["minecraft:damage": .int(430)], id: "minecraft:elytra"), reader) == "item/plain")
        #expect(try picture(stack(["minecraft:damage": .int(431), "minecraft:unbreakable": .compound([:])], id: "minecraft:elytra"), reader) == "item/plain")
        #expect(try picture(stack(["minecraft:damage": .int(431), "Unbreakable": .byte(1),
                                  "!minecraft:unbreakable": .compound([:])], id: "minecraft:elytra"), reader) == "item/selected")
        #expect(try picture(stack(["minecraft:damage": .int(431), "!minecraft:max_damage": .compound([:])], id: "minecraft:elytra"), reader) == "item/plain")
        #expect(try picture(stack(["minecraft:damage": .string("bad")], id: "minecraft:elytra"), reader) == nil)
        #expect(try picture(stack([:], id: "pack:unknown"), reader) == nil)
    }

    @Test func chargedProjectilesUseSavedContentsWithoutAnArrowTypeInventory() throws {
        func projectile(_ id: String) -> NBT { .compound(["id": .string(id), "count": .int(1)]) }
        let rocket = try assets(select("charge_type", when: "rocket")), arrow = try assets(select("charge_type", when: "arrow"))
        let ordinary = stack(["minecraft:charged_projectiles": .list([projectile("pack:bolt")])])
        #expect(try picture(ordinary, arrow) == "item/selected")
        #expect(try picture(ordinary, rocket) == "item/plain")
        #expect(try picture(stack(["minecraft:charged_projectiles": .list([projectile("arrow"), projectile("firework_rocket")])]), rocket) == "item/selected")
        #expect(try picture(stack(["ChargedProjectiles": .list([projectile("firework_rocket")])]), rocket) == "item/selected")
        #expect(try picture(stack(["!minecraft:charged_projectiles": .compound([:]), "ChargedProjectiles": .list([projectile("firework_rocket")])]), rocket) == "item/plain")
        #expect(try picture(stack(), arrow) == "item/plain")
        #expect(try picture(stack(["minecraft:charged_projectiles": .list([])]), arrow) == "item/plain")
        #expect(try picture(stack(["minecraft:charged_projectiles": .int(1)]), arrow) == nil)
        #expect(try picture(stack(["minecraft:charged_projectiles": .list([.compound([:])])]), arrow) == nil)
        #expect(try picture(stack([:], id: "pack:unknown"), arrow) == nil)
    }

    @Test func modelKeysKeepExactSavedStringsAndIgnoreUnrelatedPresentationFields() throws {
        let composed = "é", decomposed = "e\u{301}"
        let reader = try assets(select("block_state", when: composed, fields: #", "block_state_property":"pose""#))
        let first = stack(["minecraft:block_state": .compound(["pose": .string(composed)])])
        let second = stack(["minecraft:block_state": .compound(["pose": .string(decomposed)])])
        #expect(try picture(first, reader) == "item/selected")
        #expect(try picture(second, reader) == "item/plain")
        #expect(first.itemModelSelection != second.itemModelSelection)
        #expect(Set([first.itemModelSelection, second.itemModelSelection]).count == 2)
        var renamed = first; renamed.count = 40; renamed.customName = "Same picture"
        #expect(first.itemModelSelection == renamed.itemModelSelection)
        let plain = stack(), dyed = stack(["minecraft:dyed_color": .int(1)])
        #expect(plain.itemModelSelection != dyed.itemModelSelection)
        #expect(try JSONDecoder().decode(ItemStack.self, from: JSONEncoder().encode(first)).itemModelSelection == first.itemModelSelection)
    }

    @Test func boundedUnknownFieldsOnlyPreventPicturesThatNeedThem() throws {
        let values = Dictionary(uniqueKeysWithValues: (0..<4097).map { ("k\($0)", NBT.string("v")) })
        let big = stack(["minecraft:block_state": .compound(values)])
        #expect(try picture(big, assets(plain)) == "item/plain")
        #expect(try picture(big, assets(select("block_state", when: "v", fields: #", "block_state_property":"k0""#))) == nil)
        let wide = stack(["minecraft:block_state": .compound(["k": .string(String(repeating: "x", count: 65537))])])
        #expect(try picture(wide, assets(select("block_state", when: "v", fields: #", "block_state_property":"k""#))) == nil)
        let components = stack(Dictionary(uniqueKeysWithValues: (0..<4097).map { ("pack:k\($0)", NBT.int(1)) }))
        #expect(try picture(components, assets(condition("has_component", fields: #", "component":"pack:k0""#))) == nil)
        #expect(try picture(components, assets(plain)) == "item/plain")
    }
}
