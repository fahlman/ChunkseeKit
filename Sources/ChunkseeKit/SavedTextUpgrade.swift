import Foundation

/// Unflattening is a save-format operation. Once this boundary has run, every NBT string
/// is literal, including strings nested inside a parsed component or translation argument.
enum SavedTextUpgrade {
    struct Context: Sendable {
        let version: Int

        init(dataVersion: Int?) { version = dataVersion ?? -1 }

        func component(_ value: NBT) -> NBT {
            version < GeneratedSavedText.boundary ? SavedTextUpgrade.component(value) : value
        }

        func entityName(_ value: NBT, id: String?) -> NBT {
            let id = id.flatMap(Identifier.init)?.description ?? id ?? ""
            if version < GeneratedSavedText.entityNameBoundary, !GeneratedSavedText.jsonEntityNames.contains(id) {
                return Self.literalComponent(value)
            }
            return component(value)
        }

        func blockEntityName(_ value: NBT, id: String?) -> NBT {
            let id = id.flatMap(Identifier.init)?.description ?? id ?? ""
            if version < GeneratedSavedText.blockEntityNameBoundary, GeneratedSavedText.plainBlockEntityNames.contains(id) {
                return Self.literalComponent(value)
            }
            return component(value)
        }

        func itemName(_ value: NBT) -> NBT {
            version < GeneratedSavedText.itemNameBoundary ? Self.literalComponent(value) : component(value)
        }

        func lore(_ value: NBT) -> NBT {
            version < GeneratedSavedText.loreBoundary ? Self.literalComponent(value) : component(value)
        }

        func sign(_ value: NBT) -> NBT {
            version < GeneratedSavedText.signBoundary ? SavedTextUpgrade.earlierComponent(value) : component(value)
        }

        func bookPage(_ value: NBT) -> NBT {
            version < GeneratedSavedText.bookBoundary ? SavedTextUpgrade.earlierComponent(value) : component(value)
        }

        func mapBannerName(_ banner: NBT) -> NBT? {
            // The field rename precedes unflattening. A later save's uppercase Name is
            // remainder data, so the readable fallback must not acquire JSON semantics.
            if version < GeneratedSavedText.mapBannerFieldsBoundary, let name = banner["Name"] {
                return component(name)
            }
            if let name = banner["name"] { return component(name) }
            return banner["Name"]
        }

        private static func literalComponent(_ value: NBT) -> NBT {
            guard value.string != nil else { return value }
            return .compound(["text": value])
        }
    }

    static func component(_ value: NBT) -> NBT {
        guard let literal = value.string else { return value }
        var budget = ResourceReadBudget()
        guard budget.charge(bytes: literal.utf8.count),
              let json = try? AssetJSON.legacyTextValue(from: Data(literal.utf8)),
              let converted = try? convert(json, budget: &budget) else { return value }
        return converted
    }

    /// SignTextStrictJsonFix and WrittenBookPagesStrictJsonFix share rewriteFromLenient.
    /// Its prefix/suffix rule belongs only to those earlier formats, never current strings.
    private static func earlierComponent(_ value: NBT) -> NBT {
        guard let literal = value.string else { return value }
        if literal.isEmpty || literal == "null" { return .compound(["text": .string("")]) }
        var budget = ResourceReadBudget()
        guard budget.charge(bytes: literal.utf8.count) else { return value }
        let framed = (literal.first == "\"" && literal.last == "\"")
            || (literal.first == "{" && literal.last == "}")
            || (literal.first == "[" && literal.last == "]")
        if framed, let json = try? AssetJSON.legacyTextValue(from: Data(literal.utf8)) {
            if let text = json as? String { return .compound(["text": .string(text)]) }
            if let converted = try? convert(json, budget: &budget) { return converted }
            if let rewritten = try? AssetJSON.legacyTextData(json), budget.charge(rewritten) {
                return .string(String(decoding: rewritten, as: UTF8.self))
            }
        }
        return .compound(["text": value])
    }

    private enum Work {
        case value(Any, component: Bool)
        case compound([String])
        case list(Int, components: Bool)
    }

    private static func convert(_ json: Any, budget: inout ResourceReadBudget) throws -> NBT {
        var pending: [Work] = [.value(json, component: true)]
        var results: [NBT] = []
        while let next = pending.popLast() {
            switch next {
            case .compound(let keys):
                let start = results.count - keys.count
                let fields = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, results[start + $0.offset]) })
                results.removeLast(keys.count)
                results.append(.compound(fields))
            case .list(let count, let components):
                let start = results.count - count
                let values = results[start...].filter { !components || $0.string != nil || $0.compound != nil || $0.list != nil }
                results.removeLast(count)
                // DFU's new TEXT_COMPONENT schema keeps the readable component members of
                // a list. Translation arguments are remainder data and keep numeric kinds.
                results.append(.listPreservingTypes(values))
            case .value(let value, let component):
                guard budget.consume(1) else { throw AssetReadError.invalidData }
                if let text = value as? String { results.append(.string(text)) }
                else if let number = value as? AssetJSON.Number {
                    guard let argument = number.argument else { throw AssetReadError.invalidData }
                    switch argument {
                    case .integer(let integer):
                        if let byte = Int8(exactly: integer) { results.append(.byte(byte)) }
                        else if let short = Int16(exactly: integer) { results.append(.short(short)) }
                        else if let int = Int32(exactly: integer) { results.append(.int(int)) }
                        else { results.append(.long(integer)) }
                    case .float(let number): results.append(.float(number == 0 ? 0 : number))
                    case .number(let number): results.append(.double(number == 0 ? 0 : number))
                    default: throw AssetReadError.invalidData
                    }
                } else if let flag = try? AssetJSON.boolean(value) { results.append(.byte(flag ? 1 : 0)) }
                else if let fields = value as? [String: Any] {
                    let keys = fields.keys.sorted()
                    pending.append(.compound(keys))
                    for key in keys.reversed() {
                        pending.append(.value(fields[key]!, component: component && (key == "extra" || key == "separator")))
                    }
                } else if let values = value as? [Any] {
                    pending.append(.list(values.count, components: component))
                    for entry in values.reversed() { pending.append(.value(entry, component: component)) }
                } else {
                    // JsonOps produces EndTag for null, which cannot be inserted in an NBT
                    // list or compound. Minecraft catches that failure around the entire
                    // conversion and preserves the original string, including its quotes.
                    throw AssetReadError.invalidData
                }
            }
        }
        return results[0]
    }
}
