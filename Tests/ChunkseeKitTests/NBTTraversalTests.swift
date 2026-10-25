import Foundation
import Testing
@testable import ChunkseeKit

@Suite struct NBTTraversalTests {
    private enum Outcome: Sendable, Equatable {
        case value(NBT)
        case error(NBTError)
    }

    @Test func forcedTraversalsAgreeAcrossTheHandoffAndDepthBoundary() async throws {
        for depth in [0, 1, 63, 64, 65, 200, 511, 512] {
            let compound = [UInt8]([10, 0, 0])
                + Array(repeating: [UInt8]([10, 0, 1, 120]), count: depth).flatMap { $0 }
                + Array(repeating: UInt8(0), count: depth + 1)
            let list = [UInt8]([9, 0, 0])
                + Array(repeating: [UInt8]([9, 0, 0, 0, 1]), count: depth).flatMap { $0 }
                + [1, 0, 0, 0, 0]
            for bytes in [compound, list] {
                for skipping in [[], ["x"]] as [Set<String>] {
                    let outcomes = try await decodeWithEveryTraversal(bytes, skipping: skipping)
                    #expect(outcomes.dropFirst().allSatisfy { $0 == outcomes.first })
                    if depth == 512 { #expect(outcomes.first == .error(.nestingTooDeep)) }
                    else if case .error = outcomes.first { Issue.record("Valid depth was rejected") }
                }
            }
        }
    }

    @Test func forcedTraversalsShareScalarAndSkippedValidation() async throws {
        let mixed = NBT.compound([
            "é": .string("NUL\0 and 🌍"), "b": .byte(-1), "s": .short(-300), "i": .int(-40000),
            "l": .long(Int64.min), "f": .float(1.25), "d": .double(-2.5),
            "bytes": .byteArray([-1, 0, 127]), "ints": .intArray([Int32.min, Int32.max]),
            "longs": .longArray([Int64.min, Int64.max]), "empty": .list(.short, []),
            "drop": .list([.compound(["inside": .string("skipped")]), .compound([:])]),
        ]).serialized()
        let root: [UInt8] = [10, 0, 0], name: [UInt8] = [0, 4] + Array("drop".utf8)
        let malformed = [
            root + [9] + name + [255, 0, 0, 0, 0, 0],
            root + [9] + name + [1, 255, 255, 255, 255, 0],
            root + [10] + name + [1, 0, 1, 255, 1, 0, 0],
            root + [7] + name + [0, 0, 0, 3, 1],
        ]
        for bytes in [mixed] + malformed {
            for skipping in [[], ["drop"]] as [Set<String>] {
                let outcomes = try await decodeWithEveryTraversal(bytes, skipping: skipping)
                #expect(outcomes.dropFirst().allSatisfy { $0 == outcomes.first })
            }
        }
    }

    private func decodeWithEveryTraversal(_ bytes: [UInt8], skipping: Set<String>) async throws -> [Outcome] {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                do {
                    let outcomes = try [0, 64, 512].map { limit -> Outcome in
                        do {
                            return try bytes.withUnsafeBytes { buffer in
                                var reader = NBTReader(bytes: buffer, skipping: skipping, recursionLimit: limit)
                                return .value(try reader.readRoot().value)
                            }
                        } catch let error as NBTError { return .error(error) }
                    }
                    continuation.resume(returning: outcomes)
                } catch { continuation.resume(throwing: error) }
            }
            // The forced-recursive reference intentionally exceeds the production handoff.
            // It needs a larger test stack; production depth tests still use normal workers.
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
    }
}
