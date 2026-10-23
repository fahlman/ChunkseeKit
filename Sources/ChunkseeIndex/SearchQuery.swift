import Foundation

/// Query interpretation and case-insensitive matching shared by world-search clients.
/// Clients supply searchable text and choose which records a filter covers.
public struct SearchQuery: Sendable {
    public enum Filter: String, CaseIterable, Sendable {
        case structure, place, creature, pet, villager, trade, biome, block
    }

    public let filter: Filter?
    private let terms: [String]

    /// Whether there is search text after an optional filter. A bare filter can list its category;
    /// clients decide whether an unfiltered empty query should produce results.
    public var isEmpty: Bool { terms.allSatisfy(\.isEmpty) }

    /// Matches every whitespace-separated word, in any order. A recognized prefix before the
    /// first colon selects a filter; unknown prefixes stay part of the searchable text.
    /// Prefix parsing trims horizontal whitespace; a leading newline does not introduce a filter.
    public init(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let text: String
        if let colon = trimmed.firstIndex(of: ":"),
           let filter = Filter(rawValue: trimmed[..<colon].lowercased()) {
            self.filter = filter
            text = String(trimmed[trimmed.index(after: colon)...])
        } else {
            filter = nil
            text = query
        }
        terms = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Preserves the CLI's literal phrase grammar: spaces and colons are significant, and no
    /// filter is parsed. Both query forms use the same case-insensitive substring matching.
    public init(phrase: String) {
        filter = nil
        terms = [phrase.lowercased()]
    }

    public func matches(_ text: String) -> Bool {
        let haystack = text.lowercased()
        return terms.allSatisfy(haystack.contains)
    }
}
