import Foundation

/// An immutable snapshot of potential trading from the selected game's enabled resources.
/// Code supplies profession-to-trade-set links; contents come only from runtime data.
/// Unknown code, missing resources or dynamic amounts cannot invent a positive answer.
public struct TradingDefinitions: Sendable, Equatable {
    let professions: [String: Bool]

    fileprivate static func read(in packs: [WorldResourcePack]) throws -> Self {
        let sets = try WorldResourcePack.Registry(directory: "trade_set", in: packs)
        let trades = try WorldResourcePack.Registry(directory: "villager_trade", in: packs)
        var tags = try ResourceTagReader(registry: "villager_trade", packs: packs)
        var budget = ResourceReadBudget(), answers: [String: Bool] = [:]
        let identifiers = Set(GeneratedTradingFacts.professions.values.flatMap(\.values))
        guard identifiers.count <= 4096 else { return Self(professions: [:]) }
        for id in identifiers.sorted() {
            try Task.checkCancellation()
            guard budget.consume(1), case .data(let data) = try sets.resource(id),
                  let json = object(data, budget: &budget),
                  json["amount"] != nil, json["trades"] != nil else { continue }
            let amount = try? AssetJSON.integer(json["amount"])
            let members: [String]?
            if let reference = json["trades"] as? String, reference.hasPrefix("#"),
               let tagID = GameAssets.resourceID(String(reference.dropFirst())) {
                if case .value(let tag) = try tags.read(tagID.description, budget: &budget, element: { id, budget in
                    try trade(id, in: trades, budget: &budget)
                }) { members = tag.members.map(\.id) }
                else { members = nil }
            } else {
                let direct = (json["trades"] as? [Any]) ?? (json["trades"] as? String).map { [$0] }
                if let direct, direct.count <= 4096, budget.consume(direct.count) {
                    var found: [String] = [], valid = true
                    for raw in direct {
                        guard let id = try? AssetJSON.identifier(raw),
                              case .value = try trade(id.description, in: trades, budget: &budget) else {
                            valid = false; break
                        }
                        found.append(id.description)
                    }
                    members = valid ? found : nil
                } else { members = nil }
            }
            // Empty candidates settle the answer independently of a dynamic amount. Otherwise
            // only a known constant amount establishes selection; no random/context roll is made.
            if let members {
                if members.isEmpty { answers[id] = false }
                else if let amount { answers[id] = amount > 0 }
            }
        }
        var professions: [String: Bool] = [:]
        for (id, levels) in GeneratedTradingFacts.professions {
            if levels.values.contains(where: { answers[$0] == true }) { professions[id] = true }
            else if levels.values.allSatisfy({ answers[$0] == false }) { professions[id] = false }
        }
        return Self(professions: professions)
    }

    /// The holder must resolve to a readable trade, including its required item references.
    /// Conditions and modifiers describe potential offers; they are not evaluated here.
    private static func trade(_ id: String, in registry: WorldResourcePack.Registry,
                              budget: inout ResourceReadBudget) throws -> ResourceRead<Void> {
        guard budget.consume(1) else { return .unavailable }
        switch try registry.resource(id) {
        case .absent: return .missing
        case .unavailable: return .unavailable
        case .data(let data):
            guard let json = object(data, budget: &budget),
                  let wants = json["wants"] as? [String: Any],
                  let gives = json["gives"] as? [String: Any],
                  (try? AssetJSON.identifier(wants["id"])) != nil,
                  (try? AssetJSON.identifier(gives["id"])) != nil else { return .unavailable }
            return .value(())
        }
    }

    private static func object(_ data: Data, budget: inout ResourceReadBudget) -> [String: Any]? {
        guard data.count <= ZipResources.maximumResourceSize, data.count <= budget.bytes else { return nil }
        budget.bytes -= data.count
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension GameAssets {
    /// Reads potential trade definitions from this jar without a game-version check.
    public func tradingDefinitions() throws -> TradingDefinitions {
        try TradingDefinitions.read(in: [.zip(resources)])
    }
}

extension World {
    /// Reads the selected game and enabled folder/ZIP packs in normal resource priority.
    /// Invalid overrides do not expose lower definitions. Limits: 64 packs, 4,096 selected
    /// sets/members, 64 tag levels, 16 MiB/file, 64 MiB total and 65,536 lookup/member steps.
    /// Retain this snapshot for Villager.supportsTrading(using:); saved offers stay independent.
    public func tradingDefinitions(assets: GameAssets?) throws -> TradingDefinitions {
        guard let packs = try resourcePacks(assets: assets) else { return TradingDefinitions(professions: [:]) }
        return try TradingDefinitions.read(in: packs)
    }
}
