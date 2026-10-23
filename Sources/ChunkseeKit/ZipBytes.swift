import Darwin
import Foundation

/// One byte source for the ZIP parser. A file stays on its opened inode; pread never shares
/// a seek position, and every read owns its buffer. No file bytes are memory-mapped.
struct ZipBytes: Sendable {
    private enum Storage: Sendable { case data(Data), file(File) }
    private let storage: Storage
    let count: Int

    init(data: Data) {
        storage = .data(data)
        count = data.count
    }

    init(contentsOf url: URL) throws {
        let file = try File(url)
        storage = .file(file)
        count = file.identity.count
    }

    var isUnchanged: Bool {
        switch storage {
        case .data: true
        case .file(let file): file.isUnchanged
        }
    }

    func read(_ range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= count else { throw POSIXError(.EIO) }
        switch storage {
        case .data(let data):
            return data.withUnsafeBytes { Data(UnsafeRawBufferPointer(rebasing: $0[range])) }
        case .file(let file):
            return try file.read(range)
        }
    }

    /// Immutable Swift state owns the descriptor until the last ZipBytes copy is released.
    /// External writes are detected through size and nanosecond modification/change times;
    /// payload CRCs independently verify the bytes against the validated directory.
    private final class File: Sendable {
        let descriptor: Int32
        let identity: Identity

        init(_ url: URL) throws {
            guard url.isFileURL else { throw URLError(.unsupportedURL) }
            guard !url.path.contains("\0") else { throw URLError(.badURL) }
            let descriptor = url.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NONBLOCK) } ?? -1
            }
            guard descriptor >= 0 else { throw Self.error() }
            do {
                identity = try Identity(descriptor)
                self.descriptor = descriptor
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        }

        deinit { Darwin.close(descriptor) }

        var isUnchanged: Bool {
            withExtendedLifetime(self) { (try? Identity(descriptor)) == identity }
        }

        func read(_ range: Range<Int>) throws -> Data {
            defer { withExtendedLifetime(self) {} }
            var result = Data(count: range.count)
            try result.withUnsafeMutableBytes { bytes in
                var completed = 0
                while completed < bytes.count {
                    let amount = pread(descriptor, bytes.baseAddress!.advanced(by: completed),
                                       bytes.count - completed, off_t(range.lowerBound + completed))
                    if amount < 0, errno == EINTR { continue }
                    guard amount > 0 else { throw amount == 0 ? POSIXError(.EIO) : Self.error() }
                    completed += amount
                }
            }
            return result
        }

        private static func error() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        struct Identity: Sendable, Equatable {
            let device: dev_t
            let inode: ino_t
            let count: Int
            let mode: mode_t
            let modifiedSeconds: time_t
            let modifiedNanoseconds: Int
            let changedSeconds: time_t
            let changedNanoseconds: Int

            init(_ descriptor: Int32) throws {
                var value = stat()
                guard fstat(descriptor, &value) == 0 else { throw File.error() }
                guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                      let count = Int(exactly: value.st_size), count >= 0 else { throw POSIXError(.EINVAL) }
                device = value.st_dev; inode = value.st_ino; self.count = count; mode = value.st_mode
                modifiedSeconds = value.st_mtimespec.tv_sec
                modifiedNanoseconds = value.st_mtimespec.tv_nsec
                changedSeconds = value.st_ctimespec.tv_sec
                changedNanoseconds = value.st_ctimespec.tv_nsec
            }
        }
    }
}

/// Parsing alternates between the central directory and local headers. Two small windows
/// avoid a system call per integer without retaining the archive or a second parsed directory.
/// This mutable cache is confined to synchronous initialization and never enters ZipResources.
final class ZipDirectoryBytes {
    private struct Window {
        let start: Int
        let data: Data
        func contains(_ range: Range<Int>) -> Bool {
            start <= range.lowerBound && range.upperBound - start <= data.count
        }
    }
    private let source: ZipBytes
    private var windows: [Window] = []
    var count: Int { source.count }

    init(_ source: ZipBytes) { self.source = source }

    func data(in range: Range<Int>) throws -> Data {
        let window = try window(for: range)
        let local = range.lowerBound - window.start..<range.upperBound - window.start
        // Copy names rather than retaining their entire directory window in each entry.
        return window.data.withUnsafeBytes { Data(UnsafeRawBufferPointer(rebasing: $0[local])) }
    }

    func integer<T: FixedWidthInteger>(at offset: Int, as type: T.Type) throws -> T {
        let window = try window(for: offset..<offset + MemoryLayout<T>.size)
        return window.data.withUnsafeBytes {
            T(littleEndian: $0.loadUnaligned(fromByteOffset: offset - window.start, as: type))
        }
    }

    private func window(for range: Range<Int>) throws -> Window {
        guard range.lowerBound >= 0, range.upperBound <= count else { throw POSIXError(.EIO) }
        if let window = windows.first(where: { $0.contains(range) }) { return window }
        let pageSize = 64 * 1024
        let start = range.lowerBound / pageSize * pageSize
        let length = min(count - start, max(pageSize, range.upperBound - start))
        let window = Window(start: start, data: try source.read(start..<start + length))
        if windows.count == 2 { windows.removeFirst() }
        windows.append(window)
        return window
    }
}
