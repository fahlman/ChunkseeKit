import Foundation

struct AssetItemReader {
    let assets: GameAssets
    let selection: ItemModelSelection?

    func read(_ identifier: String) throws -> AssetItem {
        let data = try assets.requiredResource(identifier, directory: "items", extension: "json", missing: AssetReadError.missingModel)
        var budget = AssetReadBudget()
        try budget.consume(bytes: data.count)
        let root = try AssetJSON.object(from: data)
        var parts = [AssetItem.Part](), nodes = 0
        try visit(root["model"], inheritedTransform: .identity, parts: &parts, nodes: &nodes, budget: &budget)
        return .init(parts: parts)
    }

    private func visit(_ raw: Any?, inheritedTransform: AssetItemTransform,
                       parts: inout [AssetItem.Part], nodes: inout Int,
                       budget: inout AssetReadBudget) throws {
        guard nodes < 64 else { throw AssetReadError.limitExceeded }
        nodes += 1
        let node = try AssetJSON.object(raw), type = try AssetJSON.identifier(node["type"])
        let transform = try inheritedTransform.appending(node["transformation"])
        switch type.description {
        case "minecraft:model":
            guard parts.count < 32 else { throw AssetReadError.limitExceeded }
            let modelID = try AssetJSON.identifier(node["model"])
            let rawTints = try node["tints"].map(AssetJSON.array) ?? []
            guard rawTints.count <= 32 else { throw AssetReadError.limitExceeded }
            let tints = try rawTints.map(tint)
            let model = try AssetModelReader(assets: assets).read(modelID.description, budget: &budget)
            parts.append(.init(model: try transform.applying(to: model), tints: tints))
        case "minecraft:special":
            guard parts.count < 32 else { throw AssetReadError.limitExceeded }
            parts.append(.init(model: try special(node, transform: transform, budget: &budget), tints: []))
        case "minecraft:composite":
            let children = try AssetJSON.array(node["models"])
            guard children.count <= 64 else { throw AssetReadError.limitExceeded }
            for child in children { try visit(child, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget) }
        case "minecraft:condition", "minecraft:select", "minecraft:range_dispatch":
            let child = try selectedChild(node, type: type.description)
            try visit(child, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:empty": break
        default: throw AssetReadError.unsupportedFeature
        }
    }

    /// Resolve before recursing so selection temporaries do not accumulate on the thread stack.
    private func selectedChild(_ node: [String: Any], type: String) throws -> Any? {
        switch type {
        case "minecraft:condition":
            let property = try AssetJSON.identifier(node["property"])
            var flag = false
            if property.description == "minecraft:custom_model_data", selection != nil {
                let data = try customModelData(), index = try customIndex(node)
                flag = data.flags.indices.contains(index) && data.flags[index]
            } else if property.description == "minecraft:has_component", let selection {
                let id = try AssetJSON.identifier(node["component"])
                let ignoreDefault = try node["ignore_default"].map(AssetJSON.boolean) ?? false
                guard let value = selection.savedProperties.hasComponent(id.description, ignoringDefault: ignoreDefault) else {
                    throw AssetReadError.incompleteState
                }
                flag = value
            } else if property.description == "minecraft:broken", let selection {
                guard let value = selection.savedProperties.broken else { throw AssetReadError.incompleteState }
                flag = value
            }
            return node[flag ? "on_true" : "on_false"]
        case "minecraft:select":
            let property = try AssetJSON.identifier(node["property"])
            let child: Any?
            if property.description == "minecraft:display_context" {
                child = try selectedCase(node, value: "gui") { value in
                    guard !value.isEmpty else { throw AssetReadError.invalidData }
                    return value
                }
            } else if property.description == "minecraft:trim_material", let selection {
                child = try selectedCase(node, value: selection.trimMaterialID?.description) { value in
                    guard let identifier = Identifier(value) else { throw AssetReadError.invalidData }
                    return identifier.description
                }
            } else if property.description == "minecraft:custom_model_data", selection != nil {
                let data = try customModelData(), index = try customIndex(node)
                let value = data.strings.indices.contains(index) ? data.strings[index] : nil
                child = try selectedCase(node, value: value.map { Array($0.utf8) }) { Array($0.utf8) }
            } else if property.description == "minecraft:block_state", let selection {
                guard let propertyName = node["block_state_property"] as? String else { throw AssetReadError.invalidData }
                guard let properties = selection.savedProperties.blockState,
                      !selection.savedProperties.unreadableBlockProperties.contains(Array(propertyName.utf8)) else { throw AssetReadError.incompleteState }
                child = try selectedCase(node, value: properties[Array(propertyName.utf8)]) { Array($0.utf8) }
            } else if property.description == "minecraft:charge_type", let selection {
                guard let value = selection.savedProperties.charge else { throw AssetReadError.incompleteState }
                child = try selectedCase(node, value: Array(value.utf8)) { Array($0.utf8) }
            } else { child = node["fallback"] }
            return child
        case "minecraft:range_dispatch":
            let property = try AssetJSON.identifier(node["property"])
            if property.description == "minecraft:custom_model_data", selection != nil {
                let data = try customModelData(), index = try customIndex(node)
                let value = data.floats.indices.contains(index) ? data.floats[index] : 0
                return try customRange(node, value: value)
            } else if let fallback = node["fallback"] {
                return fallback
            } else {
                let entries = try AssetJSON.array(node["entries"])
                guard !entries.isEmpty else { throw AssetReadError.invalidData }
                guard entries.count <= 4096 else { throw AssetReadError.limitExceeded }
                var first: (threshold: Float, model: Any)?
                for rawEntry in entries {
                    let entry = try AssetJSON.object(rawEntry), threshold = try AssetJSON.number(entry["threshold"])
                    guard let model = entry["model"] else { throw AssetReadError.invalidData }
                    if first == nil || threshold < first!.threshold { first = (threshold, model) }
                }
                return first?.model
            }
        default: throw AssetReadError.unsupportedFeature
        }
    }

    private func special(_ node: [String: Any], transform: AssetItemTransform,
                         budget: inout AssetReadBudget) throws -> AssetModel {
        let model = try AssetJSON.object(node["model"]), type = try AssetJSON.identifier(model["type"])
        guard let shape = SpecialItemModel(rawValue: type.description) else { throw AssetReadError.unsupportedFeature }
        if shape == .chest || shape == .shulker,
           (try model["openness"].map(AssetJSON.number) ?? 0) != 0 { throw AssetReadError.unsupportedFeature }
        if shape == .chest, let type = model["chest_type"], type as? String != "single" { throw AssetReadError.unsupportedFeature }
        let elements = try shape.elements(transform: transform, definition: model, selection: selection,
                                          assets: assets, budget: &budget)
        try budget.consume(elements: elements.count)
        let base = try AssetModelReader(assets: assets).read(try AssetJSON.identifier(node["base"]).description, budget: &budget)
        return .init(geometry: .elements(elements), guiTransform: base.guiTransform,
                     guiLight: base.guiLight, ambientOcclusion: base.ambientOcclusion)
    }

    /// Inventory context, trim keys and saved strings are known, unlike live use or compass angle.
    /// Validate the case table but resolve only its selected model, as for other static branches.
    private func selectedCase<Key: Hashable>(_ node: [String: Any], value selectedValue: Key?,
                                            normalize: (String) throws -> Key) throws -> Any? {
        let cases = try AssetJSON.array(node["cases"])
        guard !cases.isEmpty else { throw AssetReadError.invalidData }
        guard cases.count <= 4096 else { throw AssetReadError.limitExceeded }
        var selected = node["fallback"], seen = Set<Key>()
        for raw in cases {
            let entry = try AssetJSON.object(raw)
            let values: [String]
            if let value = entry["when"] as? String { values = [value] }
            else if let list = entry["when"] as? [String] { values = list }
            else { throw AssetReadError.invalidData }
            guard !values.isEmpty else { throw AssetReadError.invalidData }
            guard values.count <= 4096 - seen.count else { throw AssetReadError.limitExceeded }
            for rawValue in values {
                let value = try normalize(rawValue)
                guard seen.insert(value).inserted else { throw AssetReadError.invalidData }
                if value == selectedValue { selected = entry["model"] }
            }
        }
        return selected
    }

    private func customModelData() throws -> ItemCustomModelData {
        guard let selection else { throw AssetReadError.incompleteState }
        return selection.customModelData
    }

    private func customIndex(_ node: [String: Any]) throws -> Int {
        let index = try node["index"].map(AssetJSON.integer) ?? 0
        guard index >= 0 else { throw AssetReadError.invalidData }
        return index
    }

    /// Match RangeSelectItemModel's Float multiplication and stable sorted table. Its 26.3
    /// search changes at 16 entries; binary search can choose a middle duplicate, not the last.
    private func customRange(_ node: [String: Any], value: Float) throws -> Any? {
        let scale = try node["scale"].map(AssetJSON.number) ?? 1
        let rawEntries = try AssetJSON.array(node["entries"])
        guard rawEntries.count <= 4096 else { throw AssetReadError.limitExceeded }
        let entries = try rawEntries.enumerated().map { index, raw in
            let entry = try AssetJSON.object(raw)
            guard let model = entry["model"] else { throw AssetReadError.invalidData }
            return (threshold: try AssetJSON.number(entry["threshold"]), model: model, order: index)
        }.sorted {
            if Self.floatLess($0.threshold, $1.threshold) { return true }
            if Self.floatLess($1.threshold, $0.threshold) { return false }
            return $0.order < $1.order
        }
        let value = value * scale
        guard !value.isNaN else { return node["fallback"] }
        let index: Int
        if entries.count < 16 {
            index = (entries.firstIndex { $0.threshold > value } ?? entries.count) - 1
        } else {
            var low = 0, high = entries.count - 1
            while low <= high {
                let middle = (low + high) / 2
                if Self.floatLess(entries[middle].threshold, value) { low = middle + 1 }
                else if Self.floatLess(value, entries[middle].threshold) { high = middle - 1 }
                else { return entries[middle].model }
            }
            index = high
        }
        return index >= 0 ? entries[index].model : node["fallback"]
    }

    /// Java's total numeric ordering distinguishes signed zero. NaN is handled before lookup.
    private static func floatLess(_ lhs: Float, _ rhs: Float) -> Bool {
        lhs < rhs || (lhs == 0 && rhs == 0 && lhs.sign == .minus && rhs.sign == .plus)
    }

    private func tint(_ raw: Any) throws -> AssetItem.Tint {
        let value = try AssetJSON.object(raw), type = try AssetJSON.identifier(value["type"])
        switch type.description {
        case "minecraft:constant": return .constant(try AssetJSON.color(value["value"]))
        case "minecraft:custom_model_data":
            let data = try customModelData(), index = try customIndex(value)
            let fallback = try AssetJSON.color(value["default"])
            return .constant(data.colors.indices.contains(index) ? data.colors[index] : fallback)
        case "minecraft:dye": return .dye(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:potion": return .potion(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:firework": return .firework(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:grass":
            let temperature = try AssetJSON.number(value["temperature"]), downfall = try AssetJSON.number(value["downfall"])
            guard (0...1).contains(temperature), (0...1).contains(downfall),
                  let texture = GameAssets.resourceID("minecraft:colormap/grass") else { throw AssetReadError.invalidData }
            return .colorMap(texture: texture, pixel: ClimateColorMap.pixel(temperature: temperature, downfall: downfall))
        default: throw AssetReadError.unsupportedFeature
        }
    }
}
