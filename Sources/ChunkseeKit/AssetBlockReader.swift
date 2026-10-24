import Foundation
import CoreFoundation

struct AssetBlockReader {
    let assets: GameAssets

    func read(_ state: BlockState) throws -> AssetBlock {
        guard let data = assets.resource(state.id, directory: "blockstates", extension: "json") else { throw Invalid.asset }
        var budget = AssetReadBudget(), nodes = 0, models = 0
        try budget.consume(bytes: data.count)
        let root = try AssetJSON.object(JSONSerialization.jsonObject(with: data))
        guard root["variants"] != nil || root["multipart"] != nil else { throw Invalid.asset }
        let properties = BlockProperties(state, gameDataVersion: assets.version.dataVersion)
        let seedOffset = BlockModelSeed.offset(for: properties, gameDataVersion: assets.version.dataVersion)
        if let raw = root["variants"] {
            let variants = try AssetJSON.object(raw)
            guard variants.count <= 4096 else { throw Invalid.asset }
            var selected: Any?
            for (selector, model) in variants {
                guard let matches = try variantMatches(selector, properties: properties) else { throw Invalid.asset }
                if matches {
                    // The game reports overlapping selectors. Our unordered dictionary cannot
                    // reproduce its partial replacement order, so leave the result unavailable.
                    guard selected == nil else { throw Invalid.asset }
                    selected = model
                }
            }
            if let selected {
                return .init(parts: [try part(selected, budget: &budget, models: &models)],
                             seedOffset: seedOffset, isMultipart: false)
            }
        }
        // Explicit variants take precedence; multipart fills the remaining states.
        guard let raw = root["multipart"] else { throw Invalid.asset }
        let selectors = try AssetJSON.array(raw)
        guard selectors.count <= 4096 else { throw Invalid.asset }
        var parts = [AssetBlock.Part]()
        for raw in selectors {
            let selector = try AssetJSON.object(raw)
            guard let apply = selector["apply"] else { throw Invalid.asset }
            let matches: Bool?
            if let condition = selector["when"] {
                matches = try conditionMatches(condition, properties: properties, depth: 0, nodes: &nodes)
            } else { matches = true }
            guard let matches else { throw Invalid.asset }
            if matches { parts.append(try part(apply, budget: &budget, models: &models)) }
        }
        return .init(parts: parts, seedOffset: seedOffset, isMultipart: true)
    }

    private func variantMatches(_ selector: String, properties: BlockProperties) throws -> Bool? {
        if selector.isEmpty { return true }
        let pairs = selector.split(separator: ",", omittingEmptySubsequences: false)
        guard pairs.count <= 4096 else { throw Invalid.asset }
        var values = [String: String]()
        for pair in pairs {
            let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty,
                  values.updateValue(String(fields[1]), forKey: String(fields[0])) == nil else { throw Invalid.asset }
        }
        return all(values.map { key, value in properties[key].map { $0 == value } })
    }

    private func conditionMatches(_ raw: Any, properties: BlockProperties, depth: Int, nodes: inout Int) throws -> Bool? {
        guard depth < 64, nodes < 4096 else { throw Invalid.asset }
        nodes += 1
        let condition = try AssetJSON.object(raw)
        guard !condition.isEmpty, condition.count <= 4096 - nodes else { throw Invalid.asset }
        if condition["OR"] != nil || condition["AND"] != nil {
            guard condition.count == 1 else { throw Invalid.asset }
            let isOr = condition["OR"] != nil
            let terms = try AssetJSON.array(condition[isOr ? "OR" : "AND"])
            guard terms.count <= 4096 - nodes else { throw Invalid.asset }
            let matches = try terms.map { try conditionMatches($0, properties: properties, depth: depth + 1, nodes: &nodes) }
            return isOr ? any(matches) : all(matches)
        }
        var matches = [Bool?]()
        for (key, raw) in condition {
            guard !key.isEmpty else { throw Invalid.asset }
            let value: String
            if let string = raw as? String { value = string }
            else if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                value = number.boolValue ? "true" : "false"
            } else { value = String(try AssetJSON.integer(raw)) }
            let terms = value.split(separator: "|", omittingEmptySubsequences: false)
            guard terms.count <= 4096 - nodes else { throw Invalid.asset }
            nodes += terms.count
            let alternatives: [Bool?] = try terms.map { term in
                let negated = term.hasPrefix("!")
                let expected = negated ? term.dropFirst() : term
                guard !expected.isEmpty else { throw Invalid.asset }
                // This per-term negation is verified in 26.3. Older clients used a different
                // grammar; unknown versions must not silently acquire its interpretation.
                if negated, assets.version.dataVersion != SaveVersion.java26_3 { throw Invalid.asset }
                return properties[key].map { ($0 == expected) != negated }
            }
            matches.append(any(alternatives))
        }
        return all(matches)
    }

    private func part(_ raw: Any, budget: inout AssetReadBudget, models: inout Int) throws -> AssetBlock.Part {
        let weighted = raw is [Any]
        let entries = weighted ? try AssetJSON.array(raw) : [raw]
        guard !entries.isEmpty, entries.count <= 256 - models else { throw Invalid.asset }
        models += entries.count
        var total = 0
        let alternatives: [AssetBlock.Alternative] = try entries.map { raw in
            let entry = try AssetJSON.object(raw), id = try AssetJSON.identifier(entry["model"])
            // A standalone variant has no weight field in the game's codec.
            let weight = weighted ? try entry["weight"].map(AssetJSON.integer) ?? 1 : 1
            guard weight > 0, weight <= Int(Int32.max) - total else { throw Invalid.asset }
            total += weight
            let rotation = try SIMD3(angle(entry["x"]), angle(entry["y"]), angle(entry["z"]))
            let uvLock = try entry["uvlock"].map(AssetJSON.boolean) ?? false
            let model = try AssetModelReader(assets: assets).read(id.description, budget: &budget)
            return .init(modelID: id, model: model, weight: weight, rotation: rotation, uvLock: uvLock)
        }
        return .init(alternatives: alternatives, totalWeight: Int32(total))
    }

    private func angle(_ raw: Any?) throws -> Int {
        guard let raw else { return 0 }
        let value = try AssetJSON.integer(raw)
        guard value.isMultiple(of: 90) else { throw Invalid.asset }
        return (value % 360 + 360) % 360
    }
}

private enum Invalid: Error { case asset }

/// Unknown properties remain unknown unless another term settles the whole predicate.
private func all(_ values: [Bool?]) -> Bool? {
    if values.contains(false) { return false }
    return values.contains(nil) ? nil : true
}

private func any(_ values: [Bool?]) -> Bool? {
    if values.contains(true) { return true }
    return values.contains(nil) ? nil : false
}
