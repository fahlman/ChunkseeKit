import Foundation
import Testing
@testable import MCWorldKit

@Suite struct NBTTests {
    @Test func readsSpecExample() throws {
        // "hello world" example from the NBT specification.
        let bytes: [UInt8] = [0x0A, 0x00, 0x0B] + Array("hello world".utf8)
            + [0x08, 0x00, 0x04] + Array("name".utf8) + [0x00, 0x09] + Array("Bananrama".utf8) + [0x00]
        let (name, value) = try NBT.read(bytes)
        #expect(name == "hello world")
        #expect(value["name"]?.string == "Bananrama")
    }

    @Test func roundTripsEveryTagType() throws {
        let value = NBT.compound([
            "b": .byte(-5), "s": .short(-300), "i": .int(70000), "l": .long(.min), "f": .float(1.5), "d": .double(-2.25),
            "ba": .byteArray([1, -1]), "str": .string("héllo"), "ia": .intArray([1, -2]), "la": .longArray([.max, 0]),
            "emptyList": .list(.compound, []), "list": .list([.int(1), .int(2)]),
            "nested": .compound(["x": .list([.compound(["y": .string("z")])])]),
        ])
        let (name, decoded) = try NBT.read(value.serialized(rootName: "root"))
        #expect(name == "root")
        #expect(decoded == value)
    }

    @Test func modifiedUTF8() throws {
        let tricky = "a\u{0}b ⛏ 🌍"
        let encoded = ModifiedUTF8.encode(tricky)
        #expect(!encoded.contains(0))  // NUL is C0 80
        #expect(encoded.contains(0xED))  // surrogate halves encoded separately
        #expect(try ModifiedUTF8.decode(encoded[...]) == tricky)
    }

    @Test func rejectsTruncatedData() {
        let bytes = NBT.compound(["x": .longArray([1, 2, 3])]).serialized()
        #expect(throws: NBTError.unexpectedEndOfData) { try NBT.read(Array(bytes.dropLast(5))) }
    }

    @Test func skippingLeavesOutNamedEntriesAtAnyDepth() throws {
        let value = NBT.compound([
            "keep": .int(1),
            "drop": .list([.compound(["deep": .longArray([1, 2, 3]), "s": .string("x")])]),
            "nested": .compound(["drop": .byteArray([1, 2]), "kept": .string("yes")]),
            "after": .longArray([.max]),
        ])
        let (_, decoded) = try NBT.read(value.serialized(), skipping: ["drop"])
        #expect(decoded == .compound(["keep": .int(1), "nested": .compound(["kept": .string("yes")]), "after": .longArray([.max])]))
        #expect(try NBT.read(value.serialized(), skipping: []).value == value)
    }

    @Test func skippingStillDetectsTruncation() {
        let bytes = NBT.compound(["drop": .longArray([1, 2, 3, 4]), "keep": .int(1)]).serialized()
        #expect(throws: NBTError.unexpectedEndOfData) { try NBT.read(Array(bytes.prefix(20)), skipping: ["drop"]) }
    }

    @Test func uuidFromIntArray() {
        let uuid = NBT.intArray([0x01234567, -0x7654_3211, 0x0, 0x1]).uuid
        #expect(uuid?.uuidString == "01234567-89AB-CDEF-0000-000000000001")
    }
}
