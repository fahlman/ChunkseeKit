import Foundation

/// An immutable snapshot of potential trading from the selected game's enabled resources.
/// Code supplies profession-to-trade-set links; contents come only from runtime data.
/// Unknown code, missing resources or dynamic amounts cannot invent a positive answer.
public struct TradingDefinitions: Sendable, Equatable {
    let tradeSets: [String: Bool]

    fileprivate static func read(in packs: [WorldResourcePack]) throws -> Self {
        let sets = try WorldResourcePack.Registry(directory: "trade_set", in: packs)
        let trades = try WorldResourcePack.Registry(directory: "villager_trade", in: packs)
        let amounts = try WorldResourcePack.Registry(directory: "context_int_provider", in: packs)
        var tags = try ResourceTagReader(registry: "villager_trade", packs: packs)
        var budget = ResourceReadBudget(), answers: [String: Bool] = [:]
        let identifiers = Set(GeneratedTradingFacts.professions.values.flatMap(\.values))
        guard identifiers.count <= 4096 else { return Self(tradeSets: [:]) }
        for id in identifiers.sorted() {
            try Task.checkCancellation()
            var visiting: Set<String> = []
            guard budget.consume(1), case .data(let data) = try sets.resource(id),
                  let json = json(data, budget: &budget) as? [String: Any],
                  let amount = try Amount.read(json["amount"], in: amounts, budget: &budget, visiting: &visiting),
                  json["trades"] != nil else { continue }
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
                else if case .constant(let count) = amount { answers[id] = count > 0 }
            }
        }
        return Self(tradeSets: answers)
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
            guard let json = json(data, budget: &budget) as? [String: Any],
                  let wants = json["wants"] as? [String: Any],
                  (try? AssetJSON.identifier(wants["id"])) != nil,
                  (try? AssetJSON.identifier((json["gives"] as? [String: Any])?["id"] ?? json["gives"])) != nil else { return .unavailable }
            return .value(())
        }
    }

    private static func json(_ data: Data, budget: inout ResourceReadBudget) -> Any? {
        guard budget.charge(data) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    /// ContextIntProviders accepts a bare integer, a typed provider or a registry reference.
    /// Only the constant form can be evaluated without the merchant's runtime loot context.
    private enum Amount {
        case constant(Int), dynamic

        static func read(_ raw: Any?, in registry: WorldResourcePack.Registry,
                         budget: inout ResourceReadBudget, visiting: inout Set<String>) throws -> Self? {
            try Task.checkCancellation()
            guard budget.consume(1) else { return nil }
            if let value = try? AssetJSON.integer(raw) { return .constant(value) }
            if let reference = raw as? String {
                guard let id = GameAssets.resourceID(reference)?.description,
                      visiting.count < 64, visiting.insert(id).inserted else { return nil }
                defer { visiting.remove(id) }
                guard case .data(let data) = try registry.resource(id),
                      let value = TradingDefinitions.json(data, budget: &budget) else { return nil }
                return try read(value, in: registry, budget: &budget, visiting: &visiting)
            }
            guard let fields = raw as? [String: Any],
                  let type = try? AssetJSON.identifier(fields["type"]) else { return nil }
            if type.description == "minecraft:constant" {
                guard let value = try? AssetJSON.integer(fields["value"]) else { return nil }
                return .constant(value)
            } else { return .dynamic }
        }
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
    /// sets/members, 64 tag/reference levels, 16 MiB/file, 64 MiB total and 65,536 lookup/member steps.
    /// Retain this snapshot for Villager.supportsTrading(using:); saved offers stay independent.
    public func tradingDefinitions(assets: GameAssets?) throws -> TradingDefinitions {
        guard let packs = try resourcePacks(assets: assets) else { return TradingDefinitions(tradeSets: [:]) }
        return try TradingDefinitions.read(in: packs)
    }
}
