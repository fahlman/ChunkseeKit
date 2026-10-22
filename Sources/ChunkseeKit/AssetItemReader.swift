import Foundation
import CoreFoundation

struct AssetItemReader {
    let assets: GameAssets

    func read(_ identifier: String) throws -> AssetItem {
        guard let data = assets.resource(identifier, directory: "items", extension: "json") else { throw Invalid.asset }
        var budget = AssetReadBudget()
        try budget.consume(bytes: data.count)
        let root = try object(JSONSerialization.jsonObject(with: data))
        var parts = [AssetItem.Part](), nodes = 0
        try visit(root["model"], parts: &parts, nodes: &nodes, budget: &budget)
        return .init(parts: parts)
    }

    private func visit(_ raw: Any?, parts: inout [AssetItem.Part], nodes: inout Int,
                       budget: inout AssetReadBudget) throws {
        guard nodes < 64 else { throw Invalid.asset }
        nodes += 1
        let node = try object(raw), type = try identifier(node["type"])
        switch type.description {
        case "minecraft:model":
            guard parts.count < 32 else { throw Invalid.asset }
            let modelID = try identifier(node["model"])
            let rawTints = try node["tints"].map(array) ?? []
            guard rawTints.count <= 32 else { throw Invalid.asset }
            let tints = try rawTints.map(tint)
            let model = try AssetModelReader(assets: assets).read(modelID.description, budget: &budget)
            parts.append(.init(model: model, tints: tints))
        case "minecraft:composite":
            let children = try array(node["models"])
            guard children.count <= 64 else { throw Invalid.asset }
            for child in children { try visit(child, parts: &parts, nodes: &nodes, budget: &budget) }
        case "minecraft:condition":
            _ = try identifier(node["property"])
            try visit(node["on_false"], parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:select":
            let property = try identifier(node["property"])
            let child = property.description == "minecraft:display_context" ? try inventoryCase(node) : node["fallback"]
            try visit(child, parts: &parts, nodes: &nodes, budget: &budget)
        case "minecraft:range_dispatch":
            _ = try identifier(node["property"])
            if let fallback = node["fallback"] {
                try visit(fallback, parts: &parts, nodes: &nodes, budget: &budget)
            } else {
                let entries = try array(node["entries"])
                guard !entries.isEmpty, entries.count <= 4096 else { throw Invalid.asset }
                var first: (threshold: Float, model: Any)?
                for rawEntry in entries {
                    let entry = try object(rawEntry), threshold = try number(entry["threshold"])
                    guard let model = entry["model"] else { throw Invalid.asset }
                    if first == nil || threshold < first!.threshold { first = (threshold, model) }
                }
                try visit(first?.model, parts: &parts, nodes: &nodes, budget: &budget)
            }
        case "minecraft:empty": break
        default: throw Invalid.asset
        }
    }

    /// Inventory is a known context, unlike live properties such as use state or compass angle.
    /// Validate the case table but resolve only its selected model, as for other static branches.
    private func inventoryCase(_ node: [String: Any]) throws -> Any? {
        let cases = try array(node["cases"])
        guard !cases.isEmpty, cases.count <= 4096 else { throw Invalid.asset }
        var selected = node["fallback"], seen = Set<String>()
        for raw in cases {
            let entry = try object(raw)
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
        let value = try object(raw), type = try identifier(value["type"])
        switch type.description {
        case "minecraft:constant": return .constant(try color(value["value"]))
        case "minecraft:dye": return .dye(defaultColor: try color(value["default"]))
        case "minecraft:potion": return .potion(defaultColor: try color(value["default"]))
        case "minecraft:firework": return .firework(defaultColor: try color(value["default"]))
        case "minecraft:grass":
            let temperature = try number(value["temperature"]), downfall = try number(value["downfall"])
            guard (0...1).contains(temperature), (0...1).contains(downfall),
                  let texture = GameAssets.resourceID("minecraft:colormap/grass") else { throw Invalid.asset }
            // GrassColorSource widens its Float fields before ColorMapColorUtil's Double math.
            let x = Int((1 - Double(temperature)) * 255)
            let y = Int((1 - Double(downfall) * Double(temperature)) * 255)
            return .colorMap(texture: texture, pixel: SIMD2(x, y))
        default: throw Invalid.asset
        }
    }
}

private enum Invalid: Error { case asset }

private func object(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else { throw Invalid.asset }
    return value
}

private func array(_ value: Any?) throws -> [Any] {
    guard let value = value as? [Any] else { throw Invalid.asset }
    return value
}

private func identifier(_ value: Any?) throws -> Identifier {
    guard let value = value as? String, let id = GameAssets.resourceID(value) else { throw Invalid.asset }
    return id
}

private func jsonNumber(_ value: Any?) throws -> NSNumber {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { throw Invalid.asset }
    return value
}

private func number(_ value: Any?) throws -> Float {
    let number = try jsonNumber(value).floatValue
    guard number.isFinite else { throw Invalid.asset }
    return number
}

private func color(_ value: Any?) throws -> UInt32 {
    if let values = value as? [Any] {
        guard let color = RGBColor.channels(try values.map(number)) else { throw Invalid.asset }
        return color
    }
    let value = try jsonNumber(value).doubleValue
    guard let integer = Int32(exactly: value) else { throw Invalid.asset }
    return RGBColor.integer(integer)
}
