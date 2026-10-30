import Foundation

/// An immutable translation snapshot from the supplied game files. Locale selection, text
/// layout, argument substitution and the final ID-based fallback belong to the client.
public struct GameLanguage: Sendable, Equatable {
    fileprivate let values: [String: String]
    fileprivate let renamedKeys: [String: String]

    /// The requested language's own `language.code`, without inheriting English's declaration.
    /// This may differ from its resource filename. Nil means that the requested files supplied
    /// no readable declaration; the translation subscript still keeps its English fallback.
    /// Locale normalization and matching belong to the client.
    public let declaredLanguageCode: String?

    /// The selected language's value, then English; nil when neither supplies this key.
    public subscript(key: String) -> String? { values[key] }

    /// The direct replacement declared by the game's deprecated-translation metadata.
    /// This does not follow a chain or guarantee that the replacement has a translation.
    /// Direct subscripting still reflects the game's removals and renames; clients naming
    /// older saved identifiers can explicitly look up this replacement when one is supplied.
    public func replacementKey(for key: String) -> String? { renamedKeys[key] }
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

    /// Sorted codes from readable language files in this jar and its installed asset index.
    /// The client chooses a language; this query does not match locales or download files.
    /// A listed file may still contain malformed translations; `language` retains its per-key
    /// English fallback. Metadata and archive reads share a 16 MiB budget. Indexed objects
    /// must be openable regular files within the same per-resource size limit, but their
    /// contents are read only when the client requests a language. Call off the UI actor.
    public func languageCodes(minecraftDirectory: URL? = nil) -> [String] {
        var reader = GameLanguageReader(assets: self)
        return reader.codes(minecraftDirectory: minecraftDirectory)
    }
}

private struct GameLanguageReader {
    let assets: GameAssets
    private var remaining = ZipResources.maximumResourceSize
    private static let unsupportedFormat = try! NSRegularExpression(pattern: #"%(\d+\$)?[\d.]*[df]"#)

    init(assets: GameAssets) { self.assets = assets }

    mutating func codes(minecraftDirectory: URL?) -> [String] {
        var codes: Set<String> = []
        if let root = minecraftDirectory {
            for (path, object) in indexedFiles(in: root) {
                guard let code = Self.languageCode(path, inJar: false),
                      let bytes = Self.localFile(object, under: root),
                      bytes.count <= ZipResources.maximumResourceSize, bytes.isUnchanged else { continue }
                codes.insert(code)
            }
        }
        for path in (assets.resources.paths(under: "assets/") ?? []).sorted() {
            guard let code = Self.languageCode(path, inJar: true), archive(path) != nil else { continue }
            codes.insert(code)
        }
        return codes.sorted()
    }

    mutating func read(locale: String, minecraftDirectory: URL?) -> GameLanguage {
        let locale = locale.replacingOccurrences(of: "-", with: "_").lowercased()
        let locales = Self.validLocale(locale) && locale != "en_us" ? ["en_us", locale] : ["en_us"]
        var values: [String: String] = [:]
        var declaredLanguageCode: String?
        let paths = (assets.resources.paths(under: "assets/") ?? []).sorted()
        for selected in locales {
            var declaration: String?
            for path in paths where Self.languageCode(path, inJar: true) == selected {
                if let data = archive(path) { Self.append(data, to: &values, declaration: &declaration) }
            }
            if selected != "en_us", let minecraftDirectory {
                appendIndexed(selected, in: minecraftDirectory, to: &values, declaration: &declaration)
            }
            if selected == locale { declaredLanguageCode = declaration }
        }
        var renamedKeys: [String: String] = [:]
        // The game applies these data-supplied removals/renames after merging all languages.
        if let data = archive("assets/minecraft/lang/deprecated.json"),
           let rules = try? AssetJSON.decode(Deprecated.self, from: data) {
            renamedKeys = rules.renamed
            for key in rules.removed { values[key] = nil }
            for (old, new) in rules.renamed.sorted(by: { $0.key < $1.key }) {
                values[new] = values.removeValue(forKey: old)
            }
        }
        return GameLanguage(values: values, renamedKeys: renamedKeys, declaredLanguageCode: declaredLanguageCode)
    }

    private struct Deprecated: Decodable {
        let removed: [String]
        let renamed: [String: String]
    }

    private static func validLocale(_ code: String) -> Bool {
        !code.isEmpty && code.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private static func languageCode(_ path: String, inJar: Bool) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let start = inJar ? 1 : 0
        guard parts.count == start + 3, !inJar || parts[0] == "assets",
              parts[start + 1] == "lang", parts[start + 2].hasSuffix(".json"),
              GameAssets.resourceID("\(parts[start]):language") != nil else { return nil }
        let code = String(parts[start + 2].dropLast(5))
        // This file supplies removal/rename rules, not a selectable language.
        guard validLocale(code), !(parts[start] == "minecraft" && code == "deprecated") else { return nil }
        return code
    }

    private mutating func appendIndexed(_ locale: String, in root: URL, to values: inout [String: String],
                                       declaration: inout String?) {
        for (path, object) in indexedFiles(in: root).sorted(by: { $0.key < $1.key })
            where Self.languageCode(path, inJar: false) == locale {
            if let data = file(object, under: root) { Self.append(data, to: &values, declaration: &declaration) }
        }
    }

    private mutating func indexedFiles(in root: URL) -> [String: String] {
        let id = assets.version.id
        guard Self.component(id), let data = file("versions/\(id)/\(id).json", under: root),
              let metadata = Self.object(data)?["assetIndex"] as? [String: Any],
              let index = metadata["id"] as? String, Self.component(index),
              let indexData = file("assets/indexes/\(index).json", under: root),
              let objects = Self.object(indexData)?["objects"] as? [String: Any] else { return [:] }
        // IndexedAssetSource uses the current local index and hash-named files. Download
        // checksums/sizes describe a launcher download, not whether these strings are readable.
        var files: [String: String] = [:]
        for path in objects.keys where Self.languageCode(path, inJar: false) != nil {
            guard let object = objects[path] as? [String: Any], let hash = object["hash"] as? String,
                  Self.isHash(hash) else { continue }
            files[path] = "assets/objects/\(hash.prefix(2))/\(hash)"
        }
        return files
    }

    private static func append(_ data: Data, to values: inout [String: String], declaration: inout String?) {
        guard let object = object(data) else { return }
        for (key, value) in object {
            let text: String
            if let string = value as? String { text = string }
            else if let boolean = try? AssetJSON.boolean(value) { text = boolean ? "true" : "false" }
            else if let number = try? AssetJSON.jsonNumber(value) { text = number.stringValue }
            else { continue }
            // Language.loadFromJson converts numeric format placeholders to string ones.
            let translated = unsupportedFormat.stringByReplacingMatches(in: text,
                range: NSRange(text.startIndex..., in: text), withTemplate: "%$1s")
            values[key] = translated
            if key == "language.code" { declaration = translated }
        }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? AssetJSON.foundationValue(from: data)) as? [String: Any]
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
        guard remaining > 0, let bytes = Self.localFile(path, under: root), bytes.count <= remaining,
              bytes.isUnchanged, let data = try? bytes.read(0..<bytes.count), bytes.isUnchanged else { return nil }
        remaining -= data.count
        return data
    }

    private static func localFile(_ path: String, under root: URL) -> ZipBytes? {
        guard root.isFileURL, let url = WorldResourcePack.file(path, under: root) else { return nil }
        return try? ZipBytes(contentsOf: url)
    }
}
