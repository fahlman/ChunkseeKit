import ChunkseeIndex
import Testing

@Suite struct SearchQueryTests {
    @Test(arguments: SearchQuery.Filter.allCases)
    func recognizedPrefixesKeepWordsAndIgnoreCase(_ filter: SearchQuery.Filter) {
        let query = SearchQuery(" \t\(filter.rawValue.uppercased()): Red\tBlue \n")
        #expect(query.filter == filter)
        #expect(!query.isEmpty)
        #expect(query.matches("blue and RED"))
        #expect(!query.matches("red"))
    }

    @Test func unknownPrefixesAndPrefixWhitespaceKeepTheirMeaning() {
        for text in ["note: diamonds", "minecraft:diamond", "pet : summer", "\npet:summer", "pet"] {
            #expect(SearchQuery(text).filter == nil)
        }
        #expect(SearchQuery("note: diamonds").matches("Diamonds with a NOTE: attached"))
        #expect(!SearchQuery("note: diamonds").matches("diamonds"))
        let identifier = SearchQuery("PeT: minecraft:wolf")
        #expect(identifier.filter == .pet)
        #expect(identifier.matches("Summer minecraft:wolf"))
        #expect(!identifier.matches("Summer wolf"))
    }

    @Test func wordsUseSubstringsAcrossTextWithoutFoldingAccents() {
        let query = SearchQuery(" RED\tblue\n")
        #expect(query.matches("blueberry\nredwood"))
        #expect(!query.matches("blueberry"))
        #expect(SearchQuery("CAFÉ").matches("Le café"))
        #expect(!SearchQuery("cafe").matches("Le café"))
    }

    @Test func emptyWordsRemainDistinctFromABareFilter() {
        let empty = SearchQuery(" \n\t")
        let pets = SearchQuery("pet: \t")
        #expect(empty.isEmpty && empty.filter == nil)
        #expect(pets.isEmpty && pets.filter == .pet)
        #expect(empty.matches("anything") && pets.matches("anything"))
    }

    @Test func phrasesKeepWhitespaceOrderAndLiteralColons() {
        let query = SearchQuery(phrase: " Red  Blue ")
        #expect(query.matches("a RED  BLUE object"))
        #expect(!query.matches("red blue"))
        #expect(!query.matches(" blue  red "))
        let colon = SearchQuery(phrase: "pet:")
        #expect(colon.filter == nil)
        #expect(colon.matches("A PET: River"))
        #expect(!colon.matches("River"))
        #expect(SearchQuery(phrase: "").isEmpty)
        #expect(!SearchQuery(phrase: " ").isEmpty)
    }
}
