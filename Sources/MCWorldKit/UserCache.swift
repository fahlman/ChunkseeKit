import Foundation

/// Minecraft's name cache, `usercache.json`: the players a game folder or server has seen.
///
/// Player files store only UUIDs, so this is the offline way to put names to them. Each game
/// folder (and each server) keeps its own cache, and entries expire a month after the player was
/// last seen there.
public enum UserCache {
    public struct Entry: Sendable, Equatable {
        public var uuid: UUID
        public var name: String
        /// When the game would stop trusting this entry; `nil` if the date couldn't be read.
        public var expires: Date?

        public init(uuid: UUID, name: String, expires: Date?) {
            self.uuid = uuid
            self.name = name
            self.expires = expires
        }
    }

    public enum ReadError: Error, Equatable {
        case notAUserCache
    }

    /// Parses one `usercache.json`. Entries with a malformed UUID or no name are skipped.
    public static func read(contentsOf url: URL) throws -> [Entry] {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> [Entry] {
        struct Raw: Decodable {
            var uuid: String?
            var name: String?
            var expiresOn: String?
        }
        guard let raw = try? JSONDecoder().decode([Raw].self, from: data) else { throw ReadError.notAUserCache }
        return raw.compactMap { entry in
            guard let text = entry.uuid, let uuid = UUID(uuidString: text), let name = entry.name, !name.isEmpty else {
                return nil
            }
            return Entry(uuid: uuid, name: name, expires: entry.expiresOn.flatMap(parseDate))
        }
    }

    /// Names from every `usercache.json` within `depth` folder levels of `folder` (for example
    /// all game folders under `~/Library/Application Support/minecraft`). Where caches disagree,
    /// the entry that expires last, which is the most recently seen, wins.
    public static func names(under folder: URL, depth: Int = 3) -> [UUID: Entry] {
        var best: [UUID: Entry] = [:]
        for file in files(under: folder, depth: depth) {
            for entry in (try? read(contentsOf: file)) ?? [] {
                if let current = best[entry.uuid], (current.expires ?? .distantPast) >= (entry.expires ?? .distantPast) {
                    continue
                }
                best[entry.uuid] = entry
            }
        }
        return best
    }

    static func files(under folder: URL, depth: Int) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var level = [folder]
        for _ in 0...max(0, depth) {
            var next: [URL] = []
            for dir in level {
                let cache = dir.appendingPathComponent("usercache.json")
                if fileManager.fileExists(atPath: cache.path) { found.append(cache) }
                let children = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
                // World saves hold no name caches and can be large, so they aren't searched.
                next += children.filter {
                    $0.lastPathComponent != "saves" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
            }
            level = next
        }
        return found
    }

    /// `2026-11-09 21:40:44 -0500`
    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: text)
    }
}
