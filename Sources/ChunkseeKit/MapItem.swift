import Foundation

/// A map made in the game (a filled map item), from `data/minecraft/maps/<id>.dat` (26.1+) or
/// `data/map_<id>.dat` (older).
public struct MapItem: Sendable, Hashable, Encodable {
    /// A banner marked on the map.
    public struct Banner: Sendable, Hashable, Encodable {
        public var x: Int
        public var y: Int
        public var z: Int
        /// The saved dye color. Current maps may omit the white default.
        public var color: String?
        public var name: String?
    }

    /// The number shown on the map item, `map_<id>`.
    public var id: Int
    /// Namespaced dimension ID, or `nil` when it is not recognized; see `unrecognizedDimension`.
    public var dimension: String?
    public var unrecognizedDimension: String?
    public var centerX: Int
    public var centerZ: Int
    /// Zoom level 0–4: each pixel covers 2^scale blocks.
    public var scale: Int
    /// 128×128 color ids, row by row from the north-west corner; see `rgb(forColor:)`.
    public var colors: [UInt8]
    /// Locked in a cartography table, so it no longer updates.
    public var isLocked: Bool
    public var banners: [Banner]

    public static let size = 128

    /// Blocks covered by one pixel.
    public var blocksPerPixel: Int { 1 << scale }
    /// Blocks covered by the whole map, along each side.
    public var sideInBlocks: Int { Self.size << scale }
    /// The world X and Z of the map's north-west corner.
    public var minX: Int { centerX - (Self.size / 2) * blocksPerPixel }
    public var minZ: Int { centerZ - (Self.size / 2) * blocksPerPixel }
    /// True when nothing has been drawn, as for a map never held while exploring.
    public var isBlank: Bool { colors.allSatisfy { $0 < 4 } }

    public init?(id: Int, nbt: NBT) {
        let data = nbt["data"] ?? nbt
        guard case .byteArray(let bytes)? = data["colors"], bytes.count == Self.size * Self.size else { return nil }
        let text = SavedTextUpgrade.Context(dataVersion: nbt["DataVersion"]?.compoundInt.map(Int.init)
            ?? GeneratedSavedText.savedDataDefaultVersion)
        self.id = id
        let dimensionTag = data["dimension"]
        dimension = dimensionTag?.dimensionID
        unrecognizedDimension = dimension == nil ? dimensionTag?.dimensionDescription : nil
        centerX = data["xCenter"]?.int ?? 0
        centerZ = data["zCenter"]?.int ?? 0
        scale = min(max(data["scale"]?.int ?? 0, 0), 4)
        colors = bytes.map { UInt8(bitPattern: $0) }
        isLocked = data["locked"]?.bool ?? false
        banners = (data["banners"]?.list ?? []).compactMap { banner in
            let pos = banner["pos"] ?? banner["Pos"]
            let x: Int, y: Int, z: Int
            if case .intArray? = pos {
                guard let position = pos?.blockPosition else { return nil }
                (x, y, z) = (position.x, position.y, position.z)
            } else {
                guard let oldX = pos?["X"]?.int ?? pos?["x"]?.int,
                      let oldY = pos?["Y"]?.int ?? pos?["y"]?.int,
                      let oldZ = pos?["Z"]?.int ?? pos?["z"]?.int else { return nil }
                (x, y, z) = (oldX, oldY, oldZ)
            }
            return Banner(x: x, y: y, z: z, color: (banner["color"] ?? banner["Color"])?.string,
                          name: text.mapBannerName(banner).flatMap(TextComponent.plainText))
        }
    }

    /// The red, green and blue of a map color id, or `nil` for transparent (ids 0–3) and unknown
    /// ids. Each id is a base color (id / 4) at one of four shades (id % 4).
    public static func rgb(forColor id: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let base = Int(id) / 4
        guard let color = GeneratedMapColors.baseColors[base] else { return nil }
        let multiplier = GeneratedMapColors.brightness[Int(id) % 4]
        func channel(_ shift: Int) -> UInt8 { UInt8((Int((color >> shift) & 0xFF) * multiplier) / 255) }
        return (channel(16), channel(8), channel(0))
    }
}

/// Readable saved maps and the uncertainty needed to distinguish failed reads from removal.
public struct MapItemRead: Sendable {
    /// The best readable value for each ID, sorted by ID, including readable legacy fallbacks.
    public let maps: [MapItem]
    /// IDs whose preferred value could not be established. A readable fallback may appear in
    /// `maps`; a refreshing client can retain its previous value for these IDs instead.
    public let unresolvedIDs: Set<Int>
    /// False when a directory could not be listed. Absent IDs then do not establish removal.
    /// Missing directories are successful empty listings, not failures.
    public let isListingComplete: Bool
}

extension World {
    /// Every readable map, by id. Files that aren't maps (`last_id.dat`, `idcounts.dat`) or
    /// can't be read are skipped.
    public func mapItems() -> [MapItem] {
        readMapItems().maps
    }

    /// Reads the same maps as `mapItems()`, preserving failed discovery and preferred-file
    /// reads so callers can refresh a retained snapshot without treating failure as deletion.
    public func readMapItems() -> MapItemRead {
        var maps: [Int: MapItem] = [:], unresolved: Set<Int> = []
        var listingComplete = true
        for (directory, prefix) in [("data/minecraft/maps", ""), ("data", "map_")] {
            let folder = url.appendingPathComponent(directory)
            let names: [String]
            do { names = try FileManager.default.contentsOfDirectory(atPath: folder.path) }
            catch {
                let code = (error as? CocoaError)?.code
                if code != .fileReadNoSuchFile && code != .fileNoSuchFile { listingComplete = false }
                continue
            }
            var failed: Set<Int> = [], readHere: Set<Int> = []
            for name in names {
                guard name.hasPrefix(prefix), name.hasSuffix(".dat") else { continue }
                let stem = name.dropFirst(prefix.count).dropLast(4)
                guard let id = Int(stem), stem == String(id), maps[id] == nil else { continue }
                if let nbt = try? NBT.read(contentsOf: folder.appendingPathComponent(name)),
                   let map = MapItem(id: id, nbt: nbt) {
                    maps[id] = map
                    readHere.insert(id)
                } else {
                    failed.insert(id)
                }
            }
            unresolved.formUnion(failed)
            if !listingComplete { unresolved.formUnion(readHere) }
        }
        return MapItemRead(maps: maps.values.sorted { $0.id < $1.id },
                           unresolvedIDs: unresolved, isListingComplete: listingComplete)
    }
}
