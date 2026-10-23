import Foundation

/// The four biome-controlled terrain tint sources in the verified 26.3 client.
public enum BiomeColor: Sendable, Hashable, CaseIterable {
    case grass, foliage, dryFoliage, water
}

extension BiomeDefinition {
    /// Whether changing X/Z can change this source's color. When false, callers can reuse
    /// the resolved color for this definition while their colormap pixels remain unchanged.
    public func colorDependsOnPosition(_ source: BiomeColor) -> Bool {
        source == .grass && grassColorModifier == .swamp
    }

    /// Resolves an unblended 24-bit RGB tint at a block's X/Z, using this definition's overrides
    /// and climate. The caller supplies decoded 256×256 colormap pixels, with a top-left origin.
    /// A missing needed pixel returns nil; no game artwork or image decoder is included.
    /// Definitions are available only for the verified game version. Position affects swamp
    /// grass; neighboring-biome blending and choosing the column's biome belong to the caller.
    public func color(_ source: BiomeColor, x: Int32, z: Int32,
                      sample: (Identifier, SIMD2<Int>) -> UInt32?) -> UInt32? {
        // Swamp's modifier replaces the base color completely, including an explicit override.
        if colorDependsOnPosition(source) {
            return BiomeGrassNoise.color(x: x, z: z)
        }
        let override: UInt32?
        let texture: String
        switch source {
        case .grass: (override, texture) = (grassColor, "grass")
        case .foliage: (override, texture) = (foliageColor, "foliage")
        case .dryFoliage: (override, texture) = (dryFoliageColor, "dry_foliage")
        case .water: return waterColor
        }
        guard let id = Identifier(namespace: "minecraft", path: "colormap/" + texture),
              let color = override ?? sample(id,
                                             ClimateColorMap.pixel(temperature: temperature, downfall: downfall)) else { return nil }
        let rgb = color & 0xffffff
        if source == .grass, grassColorModifier == .darkForest {
            return ((rgb & 0xfefefe) + 0x28340a) >> 1
        }
        return rgb
    }
}

/// ColorMapColorUtil's Double math follows clamping the saved Float climate.
/// Item GrassColorSource and biome terrain use this same pixel calculation.
enum ClimateColorMap {
    static func pixel(temperature: Float, downfall: Float) -> SIMD2<Int> {
        let t = Double(min(1, max(0, temperature))), d = Double(min(1, max(0, downfall)))
        return SIMD2(Int((1 - t) * 255), Int((1 - d * t) * 255))
    }
}

/// Only the 2D, seed-2345, zero-offset simplex noise used by 26.3's swamp modifier.
/// It is independent of the world's seed and immutable after its permutation is initialized.
private enum BiomeGrassNoise {
    private static let permutation: [Int] = {
        var random = LegacyRandom(seed: 2345)
        // GradientNoise consumes three offset draws even when their multiplier is zero.
        for _ in 0..<3 { _ = random.nextDouble() }
        var values = Array(0..<256)
        for i in values.indices { values.swapAt(i, i + Int(random.nextInt(bound: Int32(256 - i)))) }
        return values
    }()
    private static let gradients: [(Double, Double)] = [
        (1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0),
        (1, 0), (-1, 0), (0, 1), (0, -1), (0, 1), (0, -1)
    ]
    private static let skew = (sqrt(3.0) - 1) * 0.5
    private static let unskew = (3 - sqrt(3.0)) / 6

    static func color(x: Int32, z: Int32) -> UInt32 {
        let x = Double(x) * 0.0225, z = Double(z) * 0.0225
        let skewed = (x + z) * skew
        // Int32 block inputs keep these floors and their sum comfortably within Int32.
        let i = Int(floor(x + skewed)), j = Int(floor(z + skewed))
        let offset = Double(i + j) * unskew
        let a = x - (Double(i) - offset), b = z - (Double(j) - offset)
        let stepX = a > b ? 1 : 0, stepZ = a > b ? 0 : 1
        func permute(_ n: Int) -> Int { permutation[n & 255] }
        func corner(_ cellX: Int, _ cellZ: Int, _ dx: Double, _ dz: Double) -> Double {
            let attenuation = 0.5 - dx * dx - dz * dz
            guard attenuation >= 0 else { return 0 }
            let gradient = gradients[permute(cellX + permute(cellZ)) % 12]
            let square = attenuation * attenuation
            return square * square * (gradient.0 * dx + gradient.1 * dz)
        }
        let first = corner(i, j, a, b)
        let second = corner(i + stepX, j + stepZ, a - Double(stepX) + unskew, b - Double(stepZ) + unskew)
        let third = corner(i + 1, j + 1, a - 1 + 2 * unskew, b - 1 + 2 * unskew)
        // SimplexNoise returns Float, which the modifier widens before comparing to -0.1.
        let noise = Float(70 * (first + second + third))
        return Double(noise) < -0.1 ? 0x4c763c : 0x6a7039
    }
}
