import Foundation
import Testing
@testable import MCWorldKit

@Suite struct CompressionTests {
    @Test func gzipAndZlibRoundTrip() throws {
        let data = Array(repeating: Array("minecraft:stone".utf8), count: 500).flatMap { $0 }
        #expect(try Compression.inflate(Compression.deflate(data)) == data)
        #expect(try Compression.inflate(Compression.deflate(data, gzip: true)) == data)
    }

    @Test func lz4BlockWithOverlappingMatch() throws {
        // Literal "abc", then a 9-byte match at offset 3 (overlaps its own output).
        let block: [UInt8] = [0x35] + Array("abc".utf8) + [0x03, 0x00]
        #expect(try Compression.decompressLZ4Block(block[...], originalSize: 12) == Array("abcabcabcabc".utf8))
    }

    @Test func lz4LongLiteralRun() throws {
        let text = [UInt8](repeating: 0x41, count: 300)
        // 300 literals = 15 + 255 + 30.
        let block: [UInt8] = [0xF0, 255, 30] + text
        #expect(try Compression.decompressLZ4Block(block[...], originalSize: 300) == text)
    }

    @Test func lz4BlockStreamFraming() throws {
        let compressed: [UInt8] = [0x35] + Array("xyz".utf8) + [0x03, 0x00]
        let stream = Fixtures.lz4Block(method: 0x20, payload: compressed, originalLength: 12)
            + Fixtures.lz4Block(method: 0x10, payload: Array("!!".utf8), originalLength: 2)
            + Fixtures.lz4Block(method: 0x10, payload: [], originalLength: 0)
        #expect(try Compression.decodeLZ4BlockStream(stream) == Array("xyzxyzxyzxyz!!".utf8))
    }

    @Test func lz4RejectsBadOffset() {
        let block: [UInt8] = [0x15, 0x61, 0x09, 0x00]
        #expect(throws: CompressionError.invalidLZ4) { try Compression.decompressLZ4Block(block[...], originalSize: 10) }
    }
}
