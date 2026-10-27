import Foundation

/// An immutable translation snapshot from the supplied game files. Locale selection, text
/// layout, argument substitution and the final ID-based fallback belong to the client.
public struct GameLanguage: Sendable, Equatable {
    fileprivate let values: [String: String]

    /// The selected language's value, then English; nil when neither supplies this key.
    public subscript(key: String) -> String? { values[key] }
}

extension GameAssets {
    /// Reads English and the requested locale from this jar. Supplying the Minecraft folder
    /// also resolves this release's launcher metadata, asset index and installed language objects.
    /// Locale codes accept either underscores or hyphens, ignoring case. Missing/unreadable
    /// translations fall back per key to English. No downloads, writes or shared mutable cache.
    /// Reads are synchronous and bounded to 16 MiB total; call off the UI actor.
    public func language(_ locale: String, minecraftDirectory: URL? = nil) -> GameLanguage {
        var reader = GameLanguageReader(assets: self)
        return reader.read(locale: locale, minecraftDirectory: minecraftDirectory)
    }
}

private struct GameLanguageReader {
    let assets: GameAssets
    private var remaining = ZipResources.maximumResourceSize
    private static let unsupportedFormat = try! NSRegularExpression(pattern: #"%(\d+\$)?[\d.]*[df]"#)

    init(assets: GameAssets) { self.assets = assets }

    mutating func read(locale: String, minecraftDirectory: URL?) -> GameLanguage {
        let locale = locale.replacingOccurrences(of: "-", with: "_").lowercased()
        let validLocale = !locale.isEmpty && locale.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }
        let locales = validLocale && locale != "en_us" ? ["en_us", locale] : ["en_us"]
        var values: [String: String] = [:]
        let paths = assets.resources.paths(under: "assets/") ?? []
        for locale in locales {
            for path in paths.sorted() where Self.isLanguage(path, locale: locale, inJar: true) {
                if let data = archive(path) { Self.append(data, to: &values) }
            }
            if locale != "en_us", let minecraftDirectory {
                appendIndexed(locale, in: minecraftDirectory, to: &values)
            }
        }
        // The game applies these data-supplied removals/renames after merging all languages.
        if let data = archive("assets/minecraft/lang/deprecated.json"),
           let rules = try? JSONDecoder().decode(Deprecated.self, from: data) {
            for key in rules.removed { values[key] = nil }
            for (old, new) in rules.renamed.sorted(by: { $0.key < $1.key }) {
                values[new] = values.removeValue(forKey: old)
            }
        }
        return GameLanguage(values: values)
    }

    private struct Deprecated: Decodable {
        let removed: [String]
        let renamed: [String: String]
    }

    private static func isLanguage(_ path: String, locale: String, inJar: Bool) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let start = inJar ? 1 : 0
        guard parts.count == start + 3, !inJar || parts[0] == "assets",
              parts[start + 1] == "lang", parts[start + 2] == "\(locale).json" else { return false }
        return GameAssets.resourceID("\(parts[start]):language") != nil
    }

    private mutating func appendIndexed(_ locale: String, in root: URL, to values: inout [String: String]) {
        let id = assets.version.id
        guard Self.component(id), let data = file("versions/\(id)/\(id).json", under: root),
              let metadata = Self.object(data)?["assetIndex"] as? [String: Any],
              let index = metadata["id"] as? String, Self.component(index),
              let indexData = file("assets/indexes/\(index).json", under: root),
              let objects = Self.object(indexData)?["objects"] as? [String: Any] else { return }
        // IndexedAssetSource uses the current local index and hash-named files. Download
        // checksums/sizes describe a launcher download, not whether these strings are readable.
        for path in objects.keys.sorted() where Self.isLanguage(path, locale: locale, inJar: false) {
            guard let object = objects[path] as? [String: Any], let hash = object["hash"] as? String,
                  Self.isHash(hash), let data = file("assets/objects/\(hash.prefix(2))/\(hash)", under: root) else { continue }
            Self.append(data, to: &values)
        }
    }

    private static func append(_ data: Data, to values: inout [String: String]) {
        guard let object = object(data) else { return }
        for (key, value) in object {
            let text: String
            if let string = value as? String { text = string }
            else if let boolean = try? AssetJSON.boolean(value) { text = boolean ? "true" : "false" }
            else if let number = try? AssetJSON.jsonNumber(value) { text = number.stringValue }
            else { continue }
            // Language.loadFromJson converts numeric format placeholders to string ones.
            values[key] = unsupportedFormat.stringByReplacingMatches(in: text,
                range: NSRange(text.startIndex..., in: text), withTemplate: "%$1s")
        }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func component(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private mutating func archive(_ path: String) -> Data? {
        guard remaining > 0, let data = assets.resources.read(path) else { return nil }
        guard data.count <= remaining else { remaining = 0; return nil }
        remaining -= data.count
        return data
    }

    private mutating func file(_ path: String, under root: URL) -> Data? {
        guard remaining > 0, root.isFileURL, let url = WorldResourcePack.file(path, under: root),
              let bytes = try? ZipBytes(contentsOf: url), bytes.count <= remaining,
              bytes.isUnchanged, let data = try? bytes.read(0..<bytes.count), bytes.isUnchanged else { return nil }
        remaining -= data.count
        return data
    }
}
