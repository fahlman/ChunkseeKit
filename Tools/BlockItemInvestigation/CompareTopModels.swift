import ChunkseeKit
import CryptoKit
import Foundation

/// Compiled with exact copies of the app's production rasterizer and texture decoder.
@main
struct CompareTopModels {
    struct Input: Decodable {
        let id: String
        let properties: [String: String]
        let category: String
        let candidateID: String?
        let stateIndependent: Bool
    }

    static func hash(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    static func rgb(_ color: MapColor?) -> String? {
        color.map { String(format: "%02x%02x%02x", $0.red, $0.green, $0.blue) }
    }

    static func textures(_ block: AssetBlock, assets: GameAssets) throws -> [[UInt8]]? {
        var choices: [[AssetBlock.Alternative]] = [[]]
        for part in block.parts {
            guard choices.count * part.alternatives.count <= 64 else { return nil }
            choices = choices.flatMap { chosen in part.alternatives.map { chosen + [$0] } }
        }
        var result: [[UInt8]] = []
        for choice in choices {
            guard let image = try GameModelRenderer.topTexture(choice, tint: { _ in 0xffffff },
                texture: { assets.texture($0.description).flatMap(ItemTexture.init(png:)) }) else { return nil }
            result.append(image.pixels)
        }
        return result
    }

    static func main() throws {
        guard CommandLine.arguments.count == 5 else {
            fatalError("Expected original jar, candidate fixture, cases JSON and output JSON")
        }
        guard let assets = try GameAssets(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
              let candidates = try GameAssets(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])) else {
            fatalError("Could not open input assets")
        }
        let cases = try JSONDecoder().decode([Input].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[4])
        let samples = outputURL.deletingLastPathComponent().appendingPathComponent("samples")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: false)
        // Illustrative evidence only; these IDs never choose behavior or comparison cases.
        let illustrations: Set<String> = ["minecraft:oak_slab", "minecraft:oak_stairs", "minecraft:oak_button",
            "minecraft:oak_fence", "minecraft:anvil", "minecraft:oak_log", "minecraft:oak_door", "minecraft:oak_trapdoor"]
        var results: [[String: Any]] = []
        for input in cases {
            var result: [String: Any] = ["id": input.id, "category": input.category,
                                       "stateIndependent": input.stateIndependent]
            guard let candidateID = input.candidateID else {
                result["status"] = input.category
                results.append(result)
                continue
            }
            guard let reference = assets.blockModel(for: BlockState(input.id, properties: input.properties)) else {
                result["status"] = "reference_unavailable"
                results.append(result)
                continue
            }
            guard let candidate = candidates.blockModel(for: BlockState(candidateID)) else {
                result["status"] = "candidate_unavailable"
                results.append(result)
                continue
            }
            let referenceColor = try GameModelRenderer.topColor(reference, tint: { _ in 0xffffff },
                texture: { assets.texture($0.description).flatMap(ItemTexture.init(png:)) })
            let candidateColor = try GameModelRenderer.topColor(candidate, tint: { _ in 0xffffff },
                texture: { candidates.texture($0.description).flatMap(ItemTexture.init(png:)) })
            guard let referencePixels = try textures(reference, assets: assets),
                  let candidatePixels = try textures(candidate, assets: candidates), candidatePixels.count == 1 else {
                result["status"] = "projection_unavailable"
                result["referenceColor"] = rgb(referenceColor)
                result["candidateColor"] = rgb(candidateColor)
                results.append(result)
                continue
            }
            result["status"] = "compared"
            result["referenceColor"] = rgb(referenceColor)
            result["candidateColor"] = rgb(candidateColor)
            result["colorEqual"] = referenceColor != nil && candidateColor != nil && referenceColor == candidateColor
            result["bothColorsAbsent"] = referenceColor == nil && candidateColor == nil
            result["allPixelsEqual"] = referencePixels.allSatisfy { $0 == candidatePixels[0] }
            result["anyPixelsEqual"] = referencePixels.contains(candidatePixels[0])
            result["referencePixelHashes"] = Array(Set(referencePixels.map(hash))).sorted()
            result["candidatePixelHash"] = hash(candidatePixels[0])
            if illustrations.contains(input.id), let pixels = referencePixels.first {
                let name = input.id.replacingOccurrences(of: ":", with: "_")
                try Data(pixels).write(to: samples.appendingPathComponent(name + "-block.rgba"))
                try Data(candidatePixels[0]).write(to: samples.appendingPathComponent(name + "-item.rgba"))
            }
            results.append(result)
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: outputURL)
        print("Compared \(cases.count) property-bearing blocks; per-block outcomes: \(outputURL.path)")
    }
}
