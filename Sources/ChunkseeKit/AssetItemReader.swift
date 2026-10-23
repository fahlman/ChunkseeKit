import Foundation

struct AssetItemReader {
    let assets: GameAssets

    func read(_ identifier: String) throws -> AssetItem {
        guard let data = assets.resource(identifier, directory: "items", extension: "json") else { throw Invalid.asset }
        var budget = AssetReadBudget()
        try budget.consume(bytes: data.count)
        let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
        var parts = [AssetItem.Part](), nodes = 0
        try visit(root["model"], parts: &parts, nodes: &nodes, budget: &budget)
        return .init(parts: parts)
    }

    private func visit(_ raw: Any?, parts: inout [AssetItem.Part], nodes: inout Int,
                       budget: inout AssetReadBudget) throws {
        guard nodes < 64 else { throw Invalid.asset }
        nodes += 1
        let node = try AssetJSON.object(raw), type = try AssetJSON.identifier(node["type"])
        switch type.description {
        case "minecraft:model":
            guard parts.count < 32 else { throw Invalid.asset }
            let modelID = try AssetJSON.identifier(node["model"])
            let rawTints = try node["tints"].map(AssetJSON.array) ?? []
            guard rawTints.count <= 32 else { throw Invalid.asset }
            let tints = try rawTints.map(tint)
            let model = try AssetModelReader(assets: assets).read(modelID.description, budget: &budget)
            parts.append(.init(model: model, tints: tints))
        case "minecraft:special":
            guard parts.count < 32 else { throw Invalid.asset }
            parts.append(.init(model: try container(node, budget: &budget), tints: []))
        case "minecraft:composite":
            let children = try AssetJSON.array(node["models"])
            guard children.count <= 64 else { throw Invalid.asset }
            for child in children { try visit(child, parts: &parts, nodes: &nodes, budget: &budget) }
        case "minecraft:condition":
            _ = try AssetJSON.identifier(node["property"])
            try visit(node["on_false"], parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:select":
            let property = try AssetJSON.identifier(node["property"])
            let child = property.description == "minecraft:display_context" ? try inventoryCase(node) : node["fallback"]
            try visit(child, parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:range_dispatch":
            _ = try AssetJSON.identifier(node["property"])
            if let fallback = node["fallback"] {
                try visit(fallback, parts: &parts, nodes: &nodes, budget: &budget)
            } else {
                let entries = try AssetJSON.array(node["entries"])
                guard !entries.isEmpty, entries.count <= 4096 else { throw Invalid.asset }
                var first: (threshold: Float, model: Any)?
                for rawEntry in entries {
                    let entry = try AssetJSON.object(rawEntry), threshold = try AssetJSON.number(entry["threshold"])
                    guard let model = entry["model"] else { throw Invalid.asset }
                    if first == nil || threshold < first!.threshold { first = (threshold, model) }
                }
                try visit(first?.model, parts: &parts, nodes: &nodes, budget: &budget)
            }
        case "minecraft:empty": break
        default: throw Invalid.asset
        }
    }

    private func container(_ node: [String: Any], budget: inout AssetReadBudget) throws -> AssetModel {
        guard assets.version.id == "26.3", Int(assets.version.dataVersion) == SaveVersion.java26_3 else { throw Invalid.asset }
        let model = try AssetJSON.object(node["model"]), type = try AssetJSON.identifier(model["type"])
        guard let shape = ContainerItemModel(rawValue: type.description),
              let texture = shape.texture(try AssetJSON.identifier(model["texture"])),
              (try model["openness"].map(AssetJSON.number) ?? 0) == 0 else { throw Invalid.asset }
        if shape == .chest, let type = model["chest_type"], type as? String != "single" { throw Invalid.asset }
        var scale = SIMD3<Float>.one, translation = SIMD3<Float>.zero, turnX = false
        if let raw = node["transformation"] {
            let transform = try AssetJSON.object(raw)
            let left = try AssetJSON.numbers(transform["left_rotation"], count: 4)
            let right = try AssetJSON.numbers(transform["right_rotation"], count: 4)
            let s = try AssetJSON.numbers(transform["scale"], count: 3), t = try AssetJSON.numbers(transform["translation"], count: 3)
            // Only the axis-aligned transforms used by these verified item definitions can
            // become ordinary cuboids. Other transforms remain unsupported, never discarded.
            guard right[0...2].allSatisfy({ $0 == 0 }), abs(right[3]) == 1,
                  left[1] == 0, left[2] == 0,
                  (left[0] == 0 && abs(left[3]) == 1) || (abs(left[0]) == 1 && left[3] == 0),
                  s.allSatisfy({ $0 > 0 }) else { throw Invalid.asset }
            turnX = left[0] != 0
            scale = SIMD3(s[0], s[1], s[2])
            translation = SIMD3(t[0], t[1], t[2])
        }
        guard let elements = shape.elements(texture: texture, scale: scale, translation: translation, turnX: turnX) else { throw Invalid.asset }
        try budget.consume(elements: elements.count)
        let base = try AssetModelReader(assets: assets).read(try AssetJSON.identifier(node["base"]).description, budget: &budget)
        return .init(geometry: .elements(elements), guiTransform: base.guiTransform,
                     guiLight: base.guiLight, ambientOcclusion: base.ambientOcclusion)
    }

    /// Inventory is a known context, unlike live properties such as use state or compass angle.
    /// Validate the case table but resolve only its selected model, as for other static branches.
    private func inventoryCase(_ node: [String: Any]) throws -> Any? {
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
            for value in values {
                guard !value.isEmpty, seen.insert(value).inserted else { throw Invalid.asset }
                if value == "gui" { selected = entry["model"] }
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
