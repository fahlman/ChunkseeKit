import CZlib
import Foundation

/// Reads ordinary stored/deflated ZIP resources without extracting files. Unknown archive
/// features stay unavailable: absence permits fallback only after validating the whole directory.
/// Layout: PKWARE APPNOTE 6.3.10, sections 4.3 and 4.4.
struct ZipResources: Sendable {
    private let source: ZipBytes
    private let entries: [Data: Entry]
    static let maximumResourceSize = 16 * 1024 * 1024
    static let maximumCompressedResourceSize = 2 * maximumResourceSize

    private struct Entry: Sendable {
        let payload: Range<Int>
        let size: Int
        let method: UInt16
        let crc: UInt32
        let isRegular: Bool
    }

    init?(data: Data) {
        let source = ZipBytes(data: data)
        guard let entries = try? Directory(bytes: ZipDirectoryBytes(source)).read() else { return nil }
        self.source = source
        self.entries = entries
    }

    init?(contentsOf url: URL) throws {
        let source = try ZipBytes(contentsOf: url)
        guard let entries = try Directory(bytes: ZipDirectoryBytes(source)).read(),
              source.isUnchanged else { return nil }
        self.source = source
        self.entries = entries
    }

    // A changed archive has unknown contents, so it must not permit lower-priority fallback.
    func contains(_ path: String) -> Bool { presence(of: path) ?? true }

    /// Directory evidence only; a present entry may still have an unreadable payload.
    func presence(of path: String) -> Bool? {
        guard source.isUnchanged else { return nil }
        let present = entries[Data(path.utf8)] != nil
        return source.isUnchanged ? present : nil
    }

    /// Names come from the already validated directory; listing does not read entry payloads.
    /// A changed file has unknown contents, just as it does for contains/read.
    func paths(under prefix: String) -> [String]? {
        guard source.isUnchanged else { return nil }
        let paths = entries.keys.compactMap { name -> String? in
            guard let path = String(data: name, encoding: .utf8), path.hasPrefix(prefix) else { return nil }
            return path
        }
        return source.isUnchanged ? paths : nil
    }

    /// Contains distinguishes an absent resource from a present one whose payload is invalid.
    /// The latter must still shadow every lower-priority pack.
    func read(_ path: String) -> Data? {
        guard let entry = entries[Data(path.utf8)], entry.isRegular,
              entry.size <= Self.maximumResourceSize,
              entry.payload.count <= Self.maximumCompressedResourceSize, source.isUnchanged,
              let data = try? source.read(entry.payload) else { return nil }
        return data.withUnsafeBytes { payload in
            let output: Data
            if entry.method == 0 {
                guard payload.count == entry.size else { return nil }
                output = data
            } else {
                guard let inflated = Compression.inflateRaw(payload, size: entry.size) else { return nil }
                output = Data(inflated)
            }
            let crc = output.withUnsafeBytes { buffer in
                crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, uInt(buffer.count))
            }
            return crc == entry.crc && source.isUnchanged ? output : nil
        }
    }

    private struct Directory {
        let bytes: ZipDirectoryBytes

        func read() throws -> [Data: Entry]? {
            guard bytes.count >= 22 else { return nil }
            var end: Int?
            // Only a complete trailing comment identifies an end record. Multiple candidates
            // are ambiguous; do not let a signature hidden in a comment conceal an override.
            for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65535), by: -1) {
                if try u32(offset) == 0x06054b50, Int(try u16(offset + 20)) == bytes.count - offset - 22 {
                    guard end == nil else { return nil }
                    end = offset
                }
            }
            guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0,
                  try u16(end + 8) == u16(end + 10), try u16(end + 10) != UInt16.max,
                  try u32(end + 12) != UInt32.max, try u32(end + 16) != UInt32.max else { return nil }
            // ZIP64 and multipart archives require different records. Their absence is unknown.
            if end >= 20, try u32(end - 20) == 0x07064b50 { return nil }
            let count = Int(try u16(end + 10)), size = Int(try u32(end + 12)), start = Int(try u32(end + 16))
            guard size <= end, start == end - size, count <= size / 46 else { return nil }
            var cursor = start
            var result = [Data: Entry]()
            var occupied = [Range<Int>]()
            for _ in 0..<count {
                guard has(cursor, 46, before: end), try u32(cursor) == 0x02014b50,
                      try u16(cursor + 6) <= 20, try u16(cursor + 34) == 0 else { return nil }
                let flags = try u16(cursor + 8), method = try u16(cursor + 10)
                // Only deflate tuning, a data descriptor and UTF-8 names are supported.
                guard flags & ~UInt16(0x080e) == 0, method == 0 || method == 8,
                      try u32(cursor + 20) != UInt32.max, try u32(cursor + 24) != UInt32.max,
                      try u32(cursor + 42) != UInt32.max else { return nil }
                let nameSize = Int(try u16(cursor + 28)), extraSize = Int(try u16(cursor + 30)), commentSize = Int(try u16(cursor + 32))
                let length = 46 + nameSize + extraSize + commentSize
                guard nameSize > 0, has(cursor, length, before: end) else { return nil }
                let nameRange = cursor + 46..<cursor + 46 + nameSize
                let name = try bytes.data(in: nameRange)
                guard let path = String(data: name, encoding: .utf8), !path.contains("\0"), result[name] == nil,
                      try validExtra(nameRange.upperBound..<nameRange.upperBound + extraSize) else { return nil }
                let crc = try u32(cursor + 16), compressedSize = Int(try u32(cursor + 20)), originalSize = Int(try u32(cursor + 24))
                let local = Int(try u32(cursor + 42))
                guard let content = try payload(at: local, name: name, flags: flags, method: method, crc: crc,
                                            compressedSize: compressedSize, size: originalSize, before: start) else { return nil }
                let host = try u16(cursor + 4) >> 8, attributes = try u32(cursor + 38)
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
                             compressedSize: Int, size: Int, before limit: Int) throws -> (range: Range<Int>, end: Int)? {
            guard has(offset, 30, before: limit), try u32(offset) == 0x04034b50, try u16(offset + 4) <= 20,
                  try u16(offset + 6) == flags, try u16(offset + 8) == method else { return nil }
            let nameSize = Int(try u16(offset + 26)), extraSize = Int(try u16(offset + 28))
            let headerSize = 30 + nameSize + extraSize
            guard has(offset, headerSize, before: limit), nameSize == name.count,
                  try bytes.data(in: offset + 30..<offset + 30 + nameSize) == name,
                  try validExtra(offset + 30 + nameSize..<offset + headerSize) else { return nil }
            let start = offset + headerSize
            guard has(start, compressedSize, before: limit) else { return nil }
            let range = start..<start + compressedSize
            if flags & 8 == 0 {
                guard try u32(offset + 14) == crc, Int(try u32(offset + 18)) == compressedSize,
                      Int(try u32(offset + 22)) == size else { return nil }
                return (range, range.upperBound)
            }
            guard try u32(offset + 14) == 0 || u32(offset + 14) == crc,
                  try u32(offset + 18) == 0 || Int(u32(offset + 18)) == compressedSize,
                  try u32(offset + 22) == 0 || Int(u32(offset + 22)) == size else { return nil }
            let end = range.upperBound
            // Both descriptor forms are valid. Trying both also handles a CRC equal to the
            // optional signature without mistaking that checksum for another header.
            let candidates = try has(end, 4, before: limit) && u32(end) == 0x08074b50 ? [end + 4, end] : [end]
            for position in candidates where has(position, 12, before: limit) {
                if try u32(position) == crc, Int(try u32(position + 4)) == compressedSize, Int(try u32(position + 8)) == size {
                    return (range, position + 12)
                }
            }
            return nil
        }

        private func validExtra(_ range: Range<Int>) throws -> Bool {
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                guard has(cursor, 4, before: range.upperBound), try u16(cursor) != 1 else { return false }
                let size = 4 + Int(try u16(cursor + 2))
                guard has(cursor, size, before: range.upperBound) else { return false }
                cursor += size
            }
            return true
        }

        private func has(_ offset: Int, _ count: Int, before limit: Int) -> Bool {
            offset >= 0 && count >= 0 && offset <= limit && count <= limit - offset && limit <= bytes.count
        }

        // Every caller first validates the complete fixed or variable record containing these fields.
        private func u16(_ offset: Int) throws -> UInt16 { try bytes.integer(at: offset, as: UInt16.self) }
        private func u32(_ offset: Int) throws -> UInt32 { try bytes.integer(at: offset, as: UInt32.self) }
    }
}
