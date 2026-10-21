import CZlib
import Foundation

/// Reads ordinary stored/deflated ZIP resources without extracting files. Unknown archive
/// features stay unavailable: absence permits fallback only after validating the whole directory.
/// Layout: PKWARE APPNOTE 6.3.10, sections 4.3 and 4.4.
struct ZipResources {
    private let data: Data
    private let entries: [Data: Entry]
    static let maximumResourceSize = 16 * 1024 * 1024

    private struct Entry {
        let payload: Range<Int>
        let size: Int
        let method: UInt16
        let crc: UInt32
        let isRegular: Bool
    }

    init?(data: Data) {
        guard let entries = data.withUnsafeBytes({ Directory(bytes: $0).read() }) else { return nil }
        self.data = data
        self.entries = entries
    }

    func contains(_ path: String) -> Bool { entries[Data(path.utf8)] != nil }

    /// Contains distinguishes an absent resource from a present one whose payload is invalid.
    /// The latter must still shadow every lower-priority pack.
    func read(_ path: String) -> Data? {
        guard let entry = entries[Data(path.utf8)], entry.isRegular,
              entry.size <= Self.maximumResourceSize else { return nil }
        return data.withUnsafeBytes { bytes in
            let payload = UnsafeRawBufferPointer(rebasing: bytes[entry.payload])
            let output: Data
            if entry.method == 0 {
                guard payload.count == entry.size else { return nil }
                output = Data(payload)
            } else {
                guard let inflated = Compression.inflateRaw(payload, size: entry.size) else { return nil }
                output = Data(inflated)
            }
            let crc = output.withUnsafeBytes { buffer in
                crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, uInt(buffer.count))
            }
            return crc == entry.crc ? output : nil
        }
    }

    private struct Directory {
        let bytes: UnsafeRawBufferPointer

        func read() -> [Data: Entry]? {
            guard bytes.count >= 22 else { return nil }
            var end: Int?
            // Only a complete trailing comment identifies an end record. Multiple candidates
            // are ambiguous; do not let a signature hidden in a comment conceal an override.
            for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65535), by: -1) {
                if u32(offset) == 0x06054b50, Int(u16(offset + 20)) == bytes.count - offset - 22 {
                    guard end == nil else { return nil }
                    end = offset
                }
            }
            guard let end, u16(end + 4) == 0, u16(end + 6) == 0,
                  u16(end + 8) == u16(end + 10), u16(end + 10) != UInt16.max,
                  u32(end + 12) != UInt32.max, u32(end + 16) != UInt32.max else { return nil }
            // ZIP64 and multipart archives require different records. Their absence is unknown.
            if end >= 20, u32(end - 20) == 0x07064b50 { return nil }
            let count = Int(u16(end + 10)), size = Int(u32(end + 12)), start = Int(u32(end + 16))
            guard size <= end, start == end - size, count <= size / 46 else { return nil }
            var cursor = start
            var result = [Data: Entry]()
            var occupied = [Range<Int>]()
            for _ in 0..<count {
                guard has(cursor, 46, before: end), u32(cursor) == 0x02014b50,
                      u16(cursor + 6) <= 20, u16(cursor + 34) == 0 else { return nil }
                let flags = u16(cursor + 8), method = u16(cursor + 10)
                // Only deflate tuning, a data descriptor and UTF-8 names are supported.
                guard flags & ~UInt16(0x080e) == 0, method == 0 || method == 8,
                      u32(cursor + 20) != UInt32.max, u32(cursor + 24) != UInt32.max,
                      u32(cursor + 42) != UInt32.max else { return nil }
                let nameSize = Int(u16(cursor + 28)), extraSize = Int(u16(cursor + 30)), commentSize = Int(u16(cursor + 32))
                let length = 46 + nameSize + extraSize + commentSize
                guard nameSize > 0, has(cursor, length, before: end) else { return nil }
                let nameRange = cursor + 46..<cursor + 46 + nameSize
                let name = Data(bytes[nameRange])
                guard let path = String(data: name, encoding: .utf8), !path.contains("\0"), result[name] == nil,
                      validExtra(nameRange.upperBound..<nameRange.upperBound + extraSize) else { return nil }
                let crc = u32(cursor + 16), compressedSize = Int(u32(cursor + 20)), originalSize = Int(u32(cursor + 24))
                let local = Int(u32(cursor + 42))
                guard let content = payload(at: local, name: name, flags: flags, method: method, crc: crc,
                                            compressedSize: compressedSize, size: originalSize, before: start) else { return nil }
                let host = u16(cursor + 4) >> 8, attributes = u32(cursor + 38)
                let kind = (attributes >> 16) & 0o170000
                let regular = !path.hasSuffix("/") && attributes & 0x10 == 0
                    && (!(host == 3 || host == 19) || kind == 0 || kind == 0o100000)
                result[name] = Entry(payload: content.range, size: originalSize, method: method, crc: crc, isRegular: regular)
                occupied.append(local..<content.end)
                cursor += length
            }
            guard cursor == end else { return nil }
            occupied.sort { $0.lowerBound < $1.lowerBound }
            for (previous, next) in zip(occupied, occupied.dropFirst()) where previous.upperBound > next.lowerBound { return nil }
            return result
        }

        private func payload(at offset: Int, name: Data, flags: UInt16, method: UInt16, crc: UInt32,
                             compressedSize: Int, size: Int, before limit: Int) -> (range: Range<Int>, end: Int)? {
            guard has(offset, 30, before: limit), u32(offset) == 0x04034b50, u16(offset + 4) <= 20,
                  u16(offset + 6) == flags, u16(offset + 8) == method else { return nil }
            let nameSize = Int(u16(offset + 26)), extraSize = Int(u16(offset + 28))
            let headerSize = 30 + nameSize + extraSize
            guard has(offset, headerSize, before: limit), nameSize == name.count,
                  bytes[offset + 30..<offset + 30 + nameSize].elementsEqual(name),
                  validExtra(offset + 30 + nameSize..<offset + headerSize) else { return nil }
            let start = offset + headerSize
            guard has(start, compressedSize, before: limit) else { return nil }
            let range = start..<start + compressedSize
            if flags & 8 == 0 {
                guard u32(offset + 14) == crc, Int(u32(offset + 18)) == compressedSize,
                      Int(u32(offset + 22)) == size else { return nil }
                return (range, range.upperBound)
            }
            guard u32(offset + 14) == 0 || u32(offset + 14) == crc,
                  u32(offset + 18) == 0 || Int(u32(offset + 18)) == compressedSize,
                  u32(offset + 22) == 0 || Int(u32(offset + 22)) == size else { return nil }
            let end = range.upperBound
            // Both descriptor forms are valid. Trying both also handles a CRC equal to the
            // optional signature without mistaking that checksum for another header.
            let candidates = has(end, 4, before: limit) && u32(end) == 0x08074b50 ? [end + 4, end] : [end]
            for position in candidates where has(position, 12, before: limit) {
                if u32(position) == crc, Int(u32(position + 4)) == compressedSize, Int(u32(position + 8)) == size {
                    return (range, position + 12)
                }
            }
            return nil
        }

        private func validExtra(_ range: Range<Int>) -> Bool {
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                guard has(cursor, 4, before: range.upperBound), u16(cursor) != 1 else { return false }
                let size = 4 + Int(u16(cursor + 2))
                guard has(cursor, size, before: range.upperBound) else { return false }
                cursor += size
            }
            return true
        }

        private func has(_ offset: Int, _ count: Int, before limit: Int) -> Bool {
            offset >= 0 && count >= 0 && offset <= limit && count <= limit - offset && limit <= bytes.count
        }

        // Every caller first validates the complete fixed or variable record containing these fields.
        private func u16(_ offset: Int) -> UInt16 { UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
        private func u32(_ offset: Int) -> UInt32 { UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
}
