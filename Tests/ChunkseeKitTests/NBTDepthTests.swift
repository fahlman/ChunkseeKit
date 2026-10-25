import Testing
import ChunkseeKit

@Suite struct NBTDepthTests {
    // These bytes are assembled directly so a writer defect cannot hide a reader regression.
    private let root: [UInt8] = [10, 0, 0]
    private let child: [UInt8] = [10, 0, 1, 120]

    @Test func compoundDepthBoundaryIsSafeForRetainedAndSkippedValues() throws {
        for depth in [0, 1, 200, 511] {
            let bytes = root + compoundPayload(depth: depth)
            var value = try NBT.read(bytes).value
            for _ in 0..<depth { value = try #require(value["x"]) }
            #expect(value.compound?.isEmpty == true)
            #expect(try NBT.read(bytes, skipping: ["x"]).value == .compound([:]))
        }
        let excessive = root + compoundPayload(depth: 512)
        for skipped in [[], ["x"]] as [Set<String>] {
            #expect(throws: NBTError.nestingTooDeep) { try NBT.read(excessive, skipping: skipped) }
        }
    }

    @Test func listDepthBoundaryRetainsTheInnermostEmptyListType() throws {
        for depth in [200, 511, 512] {
            let bytes: [UInt8] = [9, 0, 0]
                + Array(repeating: [UInt8]([9, 0, 0, 0, 1]), count: depth).flatMap { $0 }
                + [1, 0, 0, 0, 0]
            if depth == 512 {
                #expect(throws: NBTError.nestingTooDeep) { try NBT.read(bytes) }
            } else {
                var value = try NBT.read(bytes).value
                for _ in 0..<depth { value = try #require(value.list?.first) }
                #expect(value == .list(.byte, []))
            }
        }
    }

    @Test func skippingADeepCompoundInAListResumesAtTheNextSibling() throws {
        let drop: [UInt8] = [9, 0, 4] + Array("drop".utf8) + [10, 0, 0, 0, 1]
        let keep: [UInt8] = [3, 0, 4] + Array("keep".utf8) + [0, 0, 0, 42]
        // Root, named list, element compound, then 509 child compounds reach depth 511.
        let bytes = root + drop + compoundPayload(depth: 509) + keep + [0]
        let retained = try NBT.read(bytes).value
        #expect(retained["keep"]?.int == 42)
        var nested = try #require(retained["drop"]?.list?.first)
        for _ in 0..<509 { nested = try #require(nested["x"]) }
        #expect(nested.compound?.isEmpty == true)
        #expect(try NBT.read(bytes, skipping: ["drop"]).value == .compound(["keep": .int(42)]))
        let excessive = root + drop + compoundPayload(depth: 510) + keep + [0]
        for skipped in [[], ["drop"]] as [Set<String>] {
            #expect(throws: NBTError.nestingTooDeep) { try NBT.read(excessive, skipping: skipped) }
            #expect(throws: NBTError.unexpectedEndOfData) { try NBT.read(Array(bytes.dropLast()), skipping: skipped) }
        }
    }

    @Test func skippedPayloadValidationKeepsItsExistingBoundaries() throws {
        let name: [UInt8] = [0, 4] + Array("drop".utf8)
        let unusedListType = root + [9] + name + [255, 0, 0, 0, 0, 0]
        #expect(throws: NBTError.invalidTagType(255)) { try NBT.read(unusedListType) }
        #expect(try NBT.read(unusedListType, skipping: ["drop"]).value == .compound([:]))

        let negativeList = root + [9] + name + [1, 255, 255, 255, 255, 0]
        let invalidMember = root + [9] + name + [0, 0, 0, 0, 1, 0]
        let invalidString = root + [8] + name + [0, 1, 255, 0]
        let invalidNestedName = root + [10] + name + [1, 0, 1, 255, 1, 0, 0]
        for skipped in [[], ["drop"]] as [Set<String>] {
            #expect(throws: NBTError.negativeLength(-1)) { try NBT.read(negativeList, skipping: skipped) }
            #expect(throws: NBTError.invalidTagType(0)) { try NBT.read(invalidMember, skipping: skipped) }
        }
        for bytes in [invalidString, invalidNestedName] {
            #expect(throws: NBTError.invalidModifiedUTF8) { try NBT.read(bytes) }
            #expect(try NBT.read(bytes, skipping: ["drop"]).value == .compound([:]))
        }
    }

    @Test func wideListsAndDuplicateCompoundNamesPreserveOrderAndReplacement() throws {
        let values = (0..<10_000).map { NBT.int(Int32($0)) }
        let bytes = NBT.list(values).serialized()
        #expect(try NBT.read(bytes).value.list == values)
        let duplicate: [UInt8] = root + [1, 0, 1, 120, 1, 1, 0, 1, 120, 2, 0]
        #expect(try NBT.read(duplicate).value == .compound(["x": .byte(2)]))
    }

    private func compoundPayload(depth: Int) -> [UInt8] {
        Array(repeating: child, count: depth).flatMap { $0 } + Array(repeating: 0, count: depth + 1)
    }
}
