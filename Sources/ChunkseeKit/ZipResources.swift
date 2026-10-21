import CArchive
import Foundation

/// Read-only ZIP resources. A complete directory is required before absence can allow
/// a lower-priority pack to supply a definition. No entries are extracted to disk.
struct ZipResources {
    private let data: Data
    private let paths: Set<String>
    // Pack metadata and dimension definitions are JSON, not general-purpose assets.
    // Limit both the declared size and actual output of each requested resource.
    static let maximumResourceSize = 16 * 1024 * 1024

    init?(data: Data) {
        guard let paths: Set<String> = Self.withArchive(data, { archive in
            var paths = Set<String>()
            var entry: OpaquePointer?
            while true {
                let result = archive_read_next_header(archive, &entry)
                if result == ARCHIVE_EOF { return paths }
                guard result == ARCHIVE_OK, let entry,
                      archive_entry_is_encrypted(entry) == 0,
                      let name = archive_entry_pathname_utf8(entry),
                      let path = String(validatingCString: name),
                      paths.insert(path).inserted,
                      archive_read_data_skip(archive) == ARCHIVE_OK else { return nil }
            }
        }) else { return nil }
        self.data = data
        self.paths = paths
    }

    func contains(_ path: String) -> Bool { paths.contains(path) }

    /// Nil for an absent or unreadable resource. Call contains first when that distinction
    /// controls fallback: an invalid present override must still shadow lower-priority packs.
    func read(_ path: String) -> Data? {
        guard contains(path) else { return nil }
        return Self.withArchive(data) { archive in
            var entry: OpaquePointer?
            while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
                guard let entry, let name = archive_entry_pathname_utf8(entry) else { return nil }
                guard String(validatingCString: name) == path else {
                    guard archive_read_data_skip(archive) == ARCHIVE_OK else { return nil }
                    continue
                }
                let size = archive_entry_size(entry)
                guard archive_entry_filetype(entry) == AE_IFREG, archive_entry_is_encrypted(entry) == 0,
                      (0...Int64(Self.maximumResourceSize)).contains(size) else { return nil }
                var output = Data()
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                while true {
                    let count = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
                    if count == 0 { return Int64(output.count) == size ? output : nil }
                    // libarchive reports malformed compressed data and checksum mismatches
                    // as errors. Do not accept a partial JSON prefix from either condition.
                    guard count > 0, count <= Self.maximumResourceSize - output.count else { return nil }
                    output.append(contentsOf: buffer.prefix(count))
                }
            }
            return nil
        }
    }

    private static func withArchive<Value>(_ data: Data, _ body: (OpaquePointer) -> Value?) -> Value? {
        data.withUnsafeBytes { bytes in
            guard let archive = archive_read_new() else { return nil }
            defer { archive_read_free(archive) }
            guard archive_read_support_format_zip_seekable(archive) == ARCHIVE_OK,
                  archive_read_open_memory(archive, bytes.baseAddress, bytes.count) == ARCHIVE_OK else { return nil }
            return body(archive)
        }
    }
}
