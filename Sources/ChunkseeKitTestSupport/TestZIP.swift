import CZlib
import Foundation
import ChunkseeKit

/// Synthetic archives shared by the ZIP, data-pack and game-asset reader tests.
public enum TestZIP {
    /// Independent central/local header writer; no production ZIP parsing or framing is reused.
    public struct Entry: Sendable {
        public let path: String, text: String
        public var data: Data?
        public var compressed = false
        public var flags: UInt16 = 0
        public var wrongCRC = false
        public var savedSize: UInt32?
        public var mode: UInt32 = 0o100644
        public var descriptorSignature = true
        public var payloadOverride: [UInt8]?
        public var extra: [UInt8] = []

        public init(path: String, text: String, data: Data? = nil, compressed: Bool = false,
                    flags: UInt16 = 0, wrongCRC: Bool = false, savedSize: UInt32? = nil,
                    mode: UInt32 = 0o100644, descriptorSignature: Bool = true,
                    payloadOverride: [UInt8]? = nil, extra: [UInt8] = []) {
            self.path = path; self.text = text; self.data = data; self.compressed = compressed
            self.flags = flags; self.wrongCRC = wrongCRC; self.savedSize = savedSize; self.mode = mode
            self.descriptorSignature = descriptorSignature; self.payloadOverride = payloadOverride; self.extra = extra
        }
    }

    public static func zip(_ entries: [Entry], comment: [UInt8] = []) throws -> [UInt8] {
        var local = [UInt8](), central = [UInt8]()
        func number<T: FixedWidthInteger>(_ value: T, into bytes: inout [UInt8]) {
            withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
        }
        for entry in entries {
            let content = Array(entry.data ?? Data(entry.text.utf8)), name = Array(entry.path.utf8)
            let payload = try entry.payloadOverride ?? (entry.compressed ? Array(Compression.deflate(content).dropFirst(2).dropLast(4)) : content)
            let crc = content.withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) } ^ (entry.wrongCRC ? 1 : 0)
            let size = entry.savedSize ?? UInt32(content.count)
            let descriptor = entry.flags & 8 != 0
            let offset = UInt32(local.count)
            number(UInt32(0x04034b50), into: &local); number(UInt16(20), into: &local)
            number(entry.flags, into: &local); number(UInt16(entry.compressed ? 8 : 0), into: &local)
            number(UInt32(0), into: &local); number(descriptor ? 0 : crc, into: &local)
            number(descriptor ? 0 : UInt32(payload.count), into: &local); number(descriptor ? 0 : size, into: &local)
            number(UInt16(name.count), into: &local); number(UInt16(entry.extra.count), into: &local)
            local += name; local += entry.extra; local += payload
            if descriptor {
                if entry.descriptorSignature { number(UInt32(0x08074b50), into: &local) }
                number(crc, into: &local)
                number(UInt32(payload.count), into: &local); number(size, into: &local)
            }

            number(UInt32(0x02014b50), into: &central); number(UInt16(0x0314), into: &central)
            number(UInt16(20), into: &central); number(entry.flags, into: &central)
            number(UInt16(entry.compressed ? 8 : 0), into: &central); number(UInt32(0), into: &central)
            number(crc, into: &central); number(UInt32(payload.count), into: &central); number(size, into: &central)
            number(UInt16(name.count), into: &central); number(UInt16(entry.extra.count), into: &central)
            number(UInt16(0), into: &central); number(UInt16(0), into: &central); number(UInt16(0), into: &central)
            number(entry.mode << 16, into: &central); number(offset, into: &central); central += name; central += entry.extra
        }
        let offset = UInt32(local.count), size = UInt32(central.count)
        local += central
        number(UInt32(0x06054b50), into: &local); number(UInt16(0), into: &local); number(UInt16(0), into: &local)
        number(UInt16(entries.count), into: &local); number(UInt16(entries.count), into: &local)
        number(size, into: &local); number(offset, into: &local); number(UInt16(comment.count), into: &local)
        local += comment
        return local
    }

}
