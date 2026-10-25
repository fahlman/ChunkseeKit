/// Immutable projections used only when an item definition asks for the corresponding fact.
/// Unreadable unrelated components must not discard an otherwise readable picture.
struct SavedItemModelProperties: Sendable, Hashable {
    let itemID: String
    let componentChanges: [String: Bool]?
    // Java compares strings without Unicode normalization; the cache key must do the same.
    let blockState: [[UInt8]: [UInt8]]?
    let unreadableBlockProperties: Set<[UInt8]>
    let broken: Bool?
    let charge: String?

    init(_ item: ItemStack) {
        itemID = Identifier(item.id)?.description ?? item.id
        let prototype = GeneratedItemModelFacts.prototypes[itemID]
        let fields = item.components?.compound ?? [:]
        var changes: [String: Bool] = [:]
        for name in fields.keys.prefix(4096) {
            let removed = name.hasPrefix("!"), raw = removed ? String(name.dropFirst()) : name
            guard raw.contains(":"), let id = Identifier(raw) else { continue }
            if changes[id.description] != false { changes[id.description] = !removed }
        }
        // ItemStack retains older tag fields. These are field-format aliases, not item IDs.
        for (old, current) in [("BlockStateTag", "block_state"), ("ChargedProjectiles", "charged_projectiles"),
                               ("Damage", "damage"), ("Trim", "trim"), ("CustomModelData", "custom_model_data"),
                               ("Enchantments", "enchantments")] {
            if changes["minecraft:" + current] == nil, fields[old] != nil { changes["minecraft:" + current] = true }
        }
        if changes["minecraft:dyed_color"] == nil, fields["display"]?["color"] != nil { changes["minecraft:dyed_color"] = true }
        if changes["minecraft:unbreakable"] == nil, fields["Unbreakable"]?.int == 1 { changes["minecraft:unbreakable"] = true }
        for (old, current) in [("Base", "base_color"), ("Patterns", "banner_patterns")] {
            if changes["minecraft:" + current] == nil, fields["BlockEntityTag"]?[old] != nil { changes["minecraft:" + current] = true }
        }
        if changes["minecraft:profile"] == nil, fields["SkullOwner"] != nil { changes["minecraft:profile"] = true }
        // Minecraft discards removal entries for components absent from the prototype.
        if let prototype { changes = changes.filter { $0.value || prototype.components.contains($0.key) } }
        let knownChanges = fields.count <= 4096 && changes.count <= 4096 && changes.keys.reduce(0, { $0 + $1.utf8.count }) <= 65536 ? changes : nil
        componentChanges = knownChanges

        let stateKey = "minecraft:block_state"
        var unreadable: Set<[UInt8]> = []
        if fields["!" + stateKey] != nil { blockState = [:] }
        else if let raw = fields[stateKey] ?? fields["BlockStateTag"] {
            if let values = raw.compound, values.count <= 4096 {
                var strings: [[UInt8]: [UInt8]] = [:], bytes = 0
                for (key, value) in values {
                    bytes += key.utf8.count
                    if let string = value.string { strings[Array(key.utf8)] = Array(string.utf8); bytes += string.utf8.count }
                    else { unreadable.insert(Array(key.utf8)) }
                    if bytes > 65536 { break }
                }
                blockState = bytes <= 65536 ? strings : nil
                if bytes > 65536 { unreadable = [] }
            } else { blockState = nil }
        } else {
            blockState = prototype.map { prototype in
                Dictionary(uniqueKeysWithValues: prototype.blockState.map { (Array($0.key.utf8), Array($0.value.utf8)) })
            }
        }
        unreadableBlockProperties = unreadable

        func has(_ name: String) -> Bool? {
            guard let knownChanges else { return nil }
            return knownChanges[name] ?? prototype.map { $0.components.contains(name) }
        }
        if has("minecraft:unbreakable") == true || has("minecraft:max_damage") == false || has("minecraft:damage") == false {
            broken = false
        } else { broken = item.durability.map { $0.remaining <= 1 } }

        let chargeKey = "minecraft:charged_projectiles"
        if fields["!" + chargeKey] != nil { charge = GeneratedItemModelFacts.noneCharge }
        else if let raw = fields[chargeKey] ?? fields["ChargedProjectiles"] {
            if let entries = raw.list, entries.count <= 4096 {
                var unknown = false, rocket = false
                for entry in entries {
                    guard let projectile = ItemStack(entry), let id = Identifier(projectile.id) else { unknown = true; continue }
                    rocket = rocket || id.description == GeneratedItemModelFacts.rocketItem
                }
                charge = rocket ? GeneratedItemModelFacts.rocketCharge : unknown ? nil
                    : entries.isEmpty ? GeneratedItemModelFacts.noneCharge : GeneratedItemModelFacts.arrowCharge
            } else { charge = nil }
        } else { charge = prototype?.charge }
    }

    func hasComponent(_ id: String, ignoringDefault: Bool) -> Bool? {
        guard let componentChanges else { return nil }
        let prototype = GeneratedItemModelFacts.prototypes[itemID]
        guard let changed = componentChanges[id] else {
            return ignoringDefault ? false : prototype.map { $0.components.contains(id) }
        }
        if !ignoringDefault { return changed }
        guard let prototype else { return nil }
        if !changed { return prototype.components.contains(id) }
        // Minecraft sanitizes a saved value equal to its prototype out of the patch. Presence
        // alone cannot establish equality for an arbitrary component's value/codec.
        return prototype.components.contains(id) ? nil : true
    }

    var storageCost: Int {
        128 + itemID.utf8.count
            + (componentChanges?.reduce(0) { $0 + 48 + $1.key.utf8.count } ?? 0)
            + (blockState?.reduce(0) { $0 + 64 + $1.key.count + $1.value.count } ?? 0)
            + unreadableBlockProperties.reduce(0) { $0 + 32 + $1.count }
            + (charge?.utf8.count ?? 0)
    }
}
