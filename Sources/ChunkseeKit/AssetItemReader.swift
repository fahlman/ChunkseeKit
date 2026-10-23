import Foundation

struct AssetItemReader {
    let assets: GameAssets
    let selection: ItemModelSelection?

    func read(_ identifier: String) throws -> AssetItem {
        guard let data = assets.resource(identifier, directory: "items", extension: "json") else { throw Invalid.asset }
        var budget = AssetReadBudget()
        try budget.consume(bytes: data.count)
        let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
        var parts = [AssetItem.Part](), nodes = 0
        try visit(root["model"], inheritedTransform: .identity, parts: &parts, nodes: &nodes, budget: &budget)
        return .init(parts: parts)
    }

    private func visit(_ raw: Any?, inheritedTransform: AssetItemTransform,
                       parts: inout [AssetItem.Part], nodes: inout Int,
                       budget: inout AssetReadBudget) throws {
        guard nodes < 64 else { throw Invalid.asset }
        nodes += 1
        let node = try AssetJSON.object(raw), type = try AssetJSON.identifier(node["type"])
        let transform = try inheritedTransform.appending(node["transformation"])
        switch type.description {
        case "minecraft:model":
            guard parts.count < 32 else { throw Invalid.asset }
            let modelID = try AssetJSON.identifier(node["model"])
            let rawTints = try node["tints"].map(AssetJSON.array) ?? []
            guard rawTints.count <= 32 else { throw Invalid.asset }
            let tints = try rawTints.map(tint)
            let model = try AssetModelReader(assets: assets).read(modelID.description, budget: &budget)
            parts.append(.init(model: try transform.applying(to: model), tints: tints))
        case "minecraft:special":
            guard parts.count < 32 else { throw Invalid.asset }
            parts.append(.init(model: try special(node, transform: transform, budget: &budget), tints: []))
        case "minecraft:composite":
            let children = try AssetJSON.array(node["models"])
            guard children.count <= 64 else { throw Invalid.asset }
            for child in children { try visit(child, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget) }
        case "minecraft:condition":
            _ = try AssetJSON.identifier(node["property"])
            try visit(node["on_false"], inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:select":
            let property = try AssetJSON.identifier(node["property"])
            let child: Any?
            if property.description == "minecraft:display_context" {
                child = try selectedCase(node, value: "gui") { value in
                    guard !value.isEmpty else { throw Invalid.asset }
                    return value
                }
            } else if property.description == "minecraft:trim_material", let selection {
                guard selection.trimMaterialID == nil ||
                        (assets.version.id == "26.3" && Int(assets.version.dataVersion) == SaveVersion.java26_3) else {
                    throw Invalid.asset
                }
                child = try selectedCase(node, value: selection.trimMaterialID?.description) { value in
                    guard let identifier = Identifier(value) else { throw Invalid.asset }
                    return identifier.description
                }
            } else { child = node["fallback"] }
            try visit(child, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:range_dispatch":
            _ = try AssetJSON.identifier(node["property"])
            if let fallback = node["fallback"] {
                try visit(fallback, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget)
            } else {
                let entries = try AssetJSON.array(node["entries"])
                guard !entries.isEmpty, entries.count <= 4096 else { throw Invalid.asset }
                var first: (threshold: Float, model: Any)?
                for rawEntry in entries {
                    let entry = try AssetJSON.object(rawEntry), threshold = try AssetJSON.number(entry["threshold"])
                    guard let model = entry["model"] else { throw Invalid.asset }
                    if first == nil || threshold < first!.threshold { first = (threshold, model) }
                }
                try visit(first?.model, inheritedTransform: transform, parts: &parts, nodes: &nodes, budget: &budget)
            }
        case "minecraft:empty": break
        default: throw Invalid.asset
        }
    }

    private func special(_ node: [String: Any], transform: AssetItemTransform,
                         budget: inout AssetReadBudget) throws -> AssetModel {
        guard assets.version.id == "26.3", Int(assets.version.dataVersion) == SaveVersion.java26_3 else { throw Invalid.asset }
        let model = try AssetJSON.object(node["model"]), type = try AssetJSON.identifier(model["type"])
        guard let shape = SpecialItemModel(rawValue: type.description) else { throw Invalid.asset }
        let texture = try shape.texture(model)
        if shape != .shield, (try model["openness"].map(AssetJSON.number) ?? 0) != 0 { throw Invalid.asset }
        if shape == .chest, let type = model["chest_type"], type as? String != "single" { throw Invalid.asset }
        guard let elements = shape.elements(texture: texture, transform: transform) else { throw Invalid.asset }
        try budget.consume(elements: elements.count)
        let base = try AssetModelReader(assets: assets).read(try AssetJSON.identifier(node["base"]).description, budget: &budget)
        return .init(geometry: .elements(elements), guiTransform: base.guiTransform,
                     guiLight: base.guiLight, ambientOcclusion: base.ambientOcclusion)
    }

    /// Inventory context and saved trim keys are known, unlike live use state or compass angle.
    /// Validate the case table but resolve only its selected model, as for other static branches.
    private func selectedCase(_ node: [String: Any], value selectedValue: String?,
                              normalize: (String) throws -> String) throws -> Any? {
        let cases = try AssetJSON.array(node["cases"])
        guard !cases.isEmpty, cases.count <= 4096 else { throw Invalid.asset }
        var selected = node["fallback"], seen = Set<String>()
        for raw in cases {
            let entry = try AssetJSON.object(raw)
            let values: [String]
            if let value = entry["when"] as? String { values = [value] }
            else if let list = entry["when"] as? [String] { values = list }
            else { throw Invalid.asset }
            guard !values.isEmpty, values.count <= 4096 - seen.count else { throw Invalid.asset }
            for rawValue in values {
                let value = try normalize(rawValue)
                guard seen.insert(value).inserted else { throw Invalid.asset }
                if value == selectedValue { selected = entry["model"] }
            }
        }
        return selected
    }

    private func tint(_ raw: Any) throws -> AssetItem.Tint {
        let value = try AssetJSON.object(raw), type = try AssetJSON.identifier(value["type"])
        switch type.description {
        case "minecraft:constant": return .constant(try AssetJSON.color(value["value"]))
        case "minecraft:dye": return .dye(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:potion": return .potion(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:firework": return .firework(defaultColor: try AssetJSON.color(value["default"]))
        case "minecraft:grass":
            let temperature = try AssetJSON.number(value["temperature"]), downfall = try AssetJSON.number(value["downfall"])
            guard (0...1).contains(temperature), (0...1).contains(downfall),
                  let texture = GameAssets.resourceID("minecraft:colormap/grass") else { throw Invalid.asset }
            return .colorMap(texture: texture, pixel: ClimateColorMap.pixel(temperature: temperature, downfall: downfall))
        default: throw Invalid.asset
        }
    }
}

private enum Invalid: Error { case asset }
