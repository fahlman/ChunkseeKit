import Foundation

/// A map made in the game (a filled map item), from `data/minecraft/maps/<id>.dat` (26.1+) or
/// `data/map_<id>.dat` (older).
public struct MapItem: Sendable, Equatable {
    /// A banner marked on the map.
    public struct Banner: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var z: Int
        public var color: String?
        public var name: String?
    }

    /// The number shown on the map item, `map_<id>`.
    public var id: Int
    /// Namespaced dimension id, or `nil` when it isn't recognized (Bukkit servers stored their
    /// own world numbers here); see `unrecognizedDimension`.
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
        self.id = id
        let dimensionTag = data["dimension"]
        dimension = dimensionTag.flatMap { PlayerInfo.dimensionID($0) }
        unrecognizedDimension = dimension == nil ? dimensionTag.map { $0.string ?? $0.int.map(String.init) ?? "?" } : nil
        centerX = data["xCenter"]?.int ?? 0
        centerZ = data["zCenter"]?.int ?? 0
        scale = min(max(data["scale"]?.int ?? 0, 0), 4)
        colors = bytes.map { UInt8(bitPattern: $0) }
        isLocked = data["locked"]?.bool ?? false
        banners = (data["banners"]?.list ?? []).compactMap { banner in
            let pos = banner["pos"] ?? banner["Pos"]
            guard let x = pos?["X"]?.int ?? pos?["x"]?.int, let y = pos?["Y"]?.int ?? pos?["y"]?.int,
                  let z = pos?["Z"]?.int ?? pos?["z"]?.int else { return nil }
            return Banner(x: x, y: y, z: z, color: (banner["color"] ?? banner["Color"])?.string,
                          name: (banner["name"] ?? banner["Name"]).flatMap(TextComponent.plainText))
        }
    }

    /// The red, green and blue of a map color id, or `nil` for transparent (ids 0–3) and unknown
    /// ids. Each id is a base color (id / 4) at one of four shades (id % 4).
    public static func rgb(forColor id: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        let base = Int(id) / 4
        guard base > 0, base < baseColors.count else { return nil }
        let multiplier = [180, 220, 255, 135][Int(id) % 4]
        let color = baseColors[base]
        func channel(_ shift: Int) -> UInt8 { UInt8((Int((color >> shift) & 0xFF) * multiplier) / 255) }
        return (channel(16), channel(8), channel(0))
    }

    /// Minecraft's map base colors, by id; 0 is transparent.
    static let baseColors: [UInt32] = [
        0x000000, 0x7FB238, 0xF7E9A3, 0xC7C7C7, 0xFF0000, 0xA0A0FF, 0xA7A7A7, 0x007C00, 0xFFFFFF, 0xA4A8B8,
        0x976D4D, 0x707070, 0x4040FF, 0x8F7748, 0xFFFCF5, 0xD87F33, 0xB24CD8, 0x6699D8, 0xE5E533, 0x7FCC19,
        0xF27FA5, 0x4C4C4C, 0x999999, 0x4C7F99, 0x7F3FB2, 0x334CB2, 0x664C33, 0x667F33, 0x993333, 0x191919,
        0xFAEE4D, 0x5CDBD5, 0x4A80FF, 0x00D93A, 0x815631, 0x700200, 0xD1B1A1, 0x9F5224, 0x95576C, 0x706C8A,
        0xBA8524, 0x677535, 0xA04D4E, 0x392923, 0x876B62, 0x575C5C, 0x7A4958, 0x4C3E5C, 0x4C3223, 0x4C522A,
        0x8E3C2E, 0x251610, 0xBD3031, 0x943F61, 0x5C191D, 0x167E86, 0x3A8E8C, 0x562C3E, 0x14B485, 0x646464,
        0xD8AF93, 0x7FA796,
    ]
}

extension World {
    /// Every readable map, by id. Files that aren't maps (`last_id.dat`, `idcounts.dat`) or
    /// can't be read are skipped.
    public func mapItems() -> [MapItem] {
        var maps: [MapItem] = []
        for (directory, prefix) in [("data/minecraft/maps", ""), ("data", "map_")] {
            let folder = url.appendingPathComponent(directory)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                guard name.hasPrefix(prefix), name.hasSuffix(".dat"),
                      let id = Int(name.dropFirst(prefix.count).dropLast(4)), !maps.contains(where: { $0.id == id }),
                      let nbt = try? NBT.read(contentsOf: folder.appendingPathComponent(name)),
                      let map = MapItem(id: id, nbt: nbt) else { continue }
                maps.append(map)
            }
        }
        return maps.sorted { $0.id < $1.id }
    }
}
