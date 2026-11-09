import Darwin
import Foundation

extension GameAssets {
    /// The file metadata used by the archive reader to detect changes. This is not a content
    /// digest or proof that a file is a valid archive. Keep the whole value when caching readers.
    public struct SourceIdentity: Sendable, Hashable {
        public let byteCount: Int
        private let device: dev_t
        private let inode: ino_t
        private let mode: mode_t
        private let modifiedSeconds: time_t
        private let modifiedNanoseconds: Int
        private let changedSeconds: time_t
        private let changedNanoseconds: Int

        /// Reads current metadata without opening or retaining an archive. Symbolic links are
        /// followed, as when opening GameAssets. Missing and non-regular files throw.
        public init(contentsOf url: URL) throws {
            guard url.isFileURL else { throw URLError(.unsupportedURL) }
            guard !url.path.contains("\0") else { throw URLError(.badURL) }
            var value = stat()
            guard url.withUnsafeFileSystemRepresentation({ path in
                path.map { fstatat(AT_FDCWD, $0, &value, 0) } ?? -1
            }) == 0 else { throw Self.error() }
            try self.init(value)
        }

        /// Stable metadata representation for persistent cache keys; do not parse it or use
        /// Swift's randomized hashValue instead. Include the source URL and interpretation
        /// contract separately when the cached result depends on them.
        public var cacheKey: String {
            "\(device)|\(inode)|\(byteCount)|\(mode)|\(modifiedSeconds)|\(modifiedNanoseconds)"
                + "|\(changedSeconds)|\(changedNanoseconds)"
        }

        init(descriptor: Int32) throws {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else { throw Self.error() }
            try self.init(value)
        }

        private init(_ value: stat) throws {
            guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  let count = Int(exactly: value.st_size), count >= 0 else { throw POSIXError(.EINVAL) }
            byteCount = count
            device = value.st_dev; inode = value.st_ino; mode = value.st_mode
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }

        private static func error() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
