import CZlib

public enum CompressionError: Error, Equatable {
    case zlib(Int32)
    case truncated
    case invalidLZ4
    case invalidLZ4BlockHeader
}

/// Codecs used by world files: gzip (`.dat` files), zlib (chunks), and LZ4 (optional for chunks since 1.20.5).
public enum Compression {
    /// True for a gzip (`1F 8B`) or zlib (`78 xx`) header.
    static func looksCompressed(_ b: [UInt8]) -> Bool {
        guard b.count >= 2 else { return false }
        if b[0] == 0x1F && b[1] == 0x8B { return true }
        return b[0] & 0x0F == 8 && (UInt16(b[0]) << 8 | UInt16(b[1])) % 31 == 0
    }

    /// Inflates gzip or zlib data (the header is auto-detected).
    public static func inflate(_ input: [UInt8]) throws -> [UInt8] {
        var stream = z_stream()
        // 15 window bits + 32 = auto-detect gzip or zlib header.
        var rc = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw CompressionError.zlib(rc) }
        defer { inflateEnd(&stream) }

        var output = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: min(max(64 * 1024, input.count * 4), 4 << 20))
        try input.withUnsafeBufferPointer { inBuf in
            stream.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress)
            stream.avail_in = uInt(inBuf.count)
            repeat {
                rc = chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(outBuf.count)
                    return CZlib.inflate(&stream, Z_NO_FLUSH)
                }
                guard rc == Z_OK || rc == Z_STREAM_END else {
                    throw rc == Z_BUF_ERROR ? CompressionError.truncated : CompressionError.zlib(rc)
                }
                output.append(contentsOf: chunk[0..<(chunk.count - Int(stream.avail_out))])
            } while rc != Z_STREAM_END
        }
        return output
    }

    /// Deflates `input` with a zlib header, or a gzip header when `gzip` is true.
    public static func deflate(_ input: [UInt8], gzip: Bool = false) throws -> [UInt8] {
        var stream = z_stream()
        var rc = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, gzip ? 15 + 16 : 15, 8,
                               Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw CompressionError.zlib(rc) }
        defer { deflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 32)
        rc = input.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                stream.next_in = UnsafeMutablePointer(mutating: inBuf.baseAddress)
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.baseAddress
                stream.avail_out = uInt(outBuf.count)
                return CZlib.deflate(&stream, Z_FINISH)
            }
        }
        guard rc == Z_STREAM_END else { throw CompressionError.zlib(rc) }
        output.removeLast(Int(stream.avail_out))
        return output
    }

    // MARK: LZ4

    private static let lz4BlockMagic = Array("LZ4Block".utf8)

    /// Decodes the framing Minecraft uses for LZ4 chunks (lz4-java's `LZ4BlockOutputStream`):
    /// repeated blocks of `"LZ4Block"`, a method/level byte, little-endian compressed length,
    /// decompressed length and checksum, then the payload. A zero-length block ends the stream.
    /// The xxHash checksum is not verified.
    public static func decodeLZ4BlockStream(_ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8]()
        var pos = 0
        func le32(_ at: Int) -> Int {
            Int(UInt32(input[at]) | UInt32(input[at + 1]) << 8 | UInt32(input[at + 2]) << 16 | UInt32(input[at + 3]) << 24)
        }
        while pos < input.count {
            guard input.count - pos >= 21, Array(input[pos..<pos + 8]) == lz4BlockMagic else {
                throw CompressionError.invalidLZ4BlockHeader
            }
            let method = input[pos + 8] & 0xF0
            let compressedLength = le32(pos + 9)
            let originalLength = le32(pos + 13)
            pos += 21
            guard compressedLength <= input.count - pos else { throw CompressionError.truncated }
            if originalLength == 0 { break }  // end-of-stream marker
            let payload = input[pos..<pos + compressedLength]
            switch method {
            case 0x10:  // stored
                output.append(contentsOf: payload)
            case 0x20:
                output.append(contentsOf: try decompressLZ4Block(payload, originalSize: originalLength))
            default:
                throw CompressionError.invalidLZ4BlockHeader
            }
            pos += compressedLength
        }
        return output
    }

    /// Decompresses one raw LZ4 block (no frame header).
    public static func decompressLZ4Block(_ input: ArraySlice<UInt8>, originalSize: Int) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(originalSize)
        var ip = input.startIndex
        let end = input.endIndex

        func readLength(_ base: Int) throws -> Int {
            var len = base
            guard base == 15 else { return len }
            while true {
                guard ip < end else { throw CompressionError.invalidLZ4 }
                let b = input[ip]; ip += 1
                len += Int(b)
                if b != 255 { return len }
            }
        }

        while ip < end {
            let token = input[ip]; ip += 1
            let literals = try readLength(Int(token >> 4))
            guard literals <= end - ip else { throw CompressionError.invalidLZ4 }
            out.append(contentsOf: input[ip..<ip + literals])
            ip += literals
            if ip >= end { break }  // the last sequence has no match

            guard end - ip >= 2 else { throw CompressionError.invalidLZ4 }
            let offset = Int(input[ip]) | Int(input[ip + 1]) << 8
            ip += 2
            let matchLength = try readLength(Int(token & 0x0F)) + 4
            guard offset > 0, offset <= out.count else { throw CompressionError.invalidLZ4 }
            // Byte-by-byte copy: the match may overlap the bytes it produces.
            var from = out.count - offset
            for _ in 0..<matchLength { out.append(out[from]); from += 1 }
        }
        guard out.count == originalSize else { throw CompressionError.invalidLZ4 }
        return out
    }
}
