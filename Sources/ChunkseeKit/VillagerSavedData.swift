/// The original VillagerData field and the entity whose reader supplies whole-record defaults.
/// A nil value means the field was absent; a non-compound value remains available for inspection.
/// This retains only the VillagerData subtree, never the enclosing entity or chunk.
public struct VillagerSavedData: Sendable, Equatable, Codable {
    public let entityID: String?
    public let value: NBT?

    var hasKnownReader: Bool { reader != nil }

    private var reader: GeneratedTradingFacts.DataReader? {
        entityID.flatMap { GeneratedTradingFacts.dataReaders[$0] }
    }

    var interpreted: VillagerDataValues {
        if let fields = value?.compound {
            // TagValueInput.read retains VillagerData.CODEC's partial result. A bad level
            // therefore cannot erase the independently readable profession and type.
            let level = fields["level"]?.javaInt.map(Int.init) ?? GeneratedTradingFacts.defaultLevel
            return .init(
                profession: Self.identifier(fields["profession"], fallback: GeneratedTradingFacts.defaultProfession),
                type: Self.identifier(fields["type"], fallback: GeneratedTradingFacts.defaultType),
                level: max(GeneratedTradingFacts.minimumLevel, level))
        }
        switch reader {
        case .villager:
            return .init(profession: GeneratedTradingFacts.defaultProfession,
                         type: GeneratedTradingFacts.defaultType, level: GeneratedTradingFacts.defaultLevel)
        case .zombieVillager:
            // initializeZombieVillagerData chooses a random registered profession. The
            // original save cannot establish which choice a future game load will make.
            return .init(profession: nil, type: GeneratedTradingFacts.defaultType,
                         level: GeneratedTradingFacts.defaultLevel)
        case nil:
            return .init(profession: nil, type: nil, level: nil)
        }
    }

    private static func identifier(_ value: NBT?, fallback: String) -> String {
        guard let saved = value?.string, Identifier(saved) != nil else { return fallback }
        // The extraction game's registry cannot prove that a readable custom ID is absent
        // from the user's game. Even an empty path is valid identifier syntax. Preserve
        // that evidence, including its original spelling, without assuming registration.
        return saved
    }
}

/// An explicit projection, including older archives that did not retain the saved field.
struct VillagerDataValues: Sendable, Equatable {
    var profession: String?
    var type: String?
    var level: Int?
}
