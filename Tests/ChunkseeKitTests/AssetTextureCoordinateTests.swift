import Foundation
import ChunkseeKit
import Testing

@Suite struct AssetTextureCoordinateTests {
    private func alternative(rotation: SIMD3<Int> = .zero, locked: Bool = false,
                             faceRotation: Int = 90, uv: [Float] = [1, 2, 13, 11]) throws -> AssetBlock.Alternative {
        let faces = Dictionary(uniqueKeysWithValues: AssetModel.Direction.allCases.map {
            ($0.rawValue, ["texture": "#skin", "uv": uv, "rotation": faceRotation] as [String: Any])
        })
        let model: [String: Any] = ["textures": ["skin": "block/test"],
            "elements": [["from": [2, 3, 4], "to": [11, 13, 15], "faces": faces]]]
        let state: [String: Any] = ["variants": ["": ["model": "block/test", "x": rotation.x,
            "y": rotation.y, "z": rotation.z, "uvlock": locked]]]
        func json(_ value: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }
        let reader = try #require(GameAssets(data: Data(TestZIP.zip([
            .init(path: "version.json", text: #"{"id":"26.3","world_version":5023}"#),
            .init(path: "assets/minecraft/models/block/test.json", text: try json(model)),
            .init(path: "assets/minecraft/blockstates/test.json", text: try json(state))
        ]))))
        return try #require(reader.blockModel(for: .init("test"))?.parts.first?.alternatives.first)
    }

    private func face(_ model: AssetBlock.Alternative, _ direction: AssetModel.Direction) throws -> AssetModel.Face {
        guard case .elements(let elements) = model.model.geometry else { throw Invalid.geometry }
        return try #require(elements.first?.faces[direction])
    }

    @Test func faceCoordinatesKeepVertexOrderAndApplyEachUVQuarterTurn() throws {
        let corners = [SIMD2<Float>(1, 2), SIMD2(1, 11), SIMD2(13, 11), SIMD2(13, 2)]
        for turn in 0..<4 {
            let model = try alternative(locked: true, faceRotation: turn * 90)
            let original = try face(model, .south)
            let expected = (0..<4).map { corners[($0 + turn) % 4] / 16 }
            #expect(original.textureCoordinates == expected)
            #expect(model.textureCoordinates(for: original, facing: .south) == expected)
            #expect(original.uv == SIMD4(1, 2, 13, 11) && original.rotation == turn * 90)
        }
    }

    @Test func lockedPartialFacesMatchOfficialModelStateForEachAxisAndComposition() throws {
        // Official 26.3 SimpleModelState.inverseFaceTransformation + CuboidFace UVs.
        let cases: [(SIMD3<Int>, AssetModel.Direction, [SIMD2<Float>])] = [
            (SIMD3(90, 0, 0), .up, [SIMD2(15, 5), SIMD2(3, 5), SIMD2(3, 14), SIMD2(15, 14)]),
            (SIMD3(0, 90, 0), .up, [SIMD2(5, 1), SIMD2(5, 13), SIMD2(14, 13), SIMD2(14, 1)]),
            (SIMD3(0, 0, 90), .north, [SIMD2(11, 15), SIMD2(11, 3), SIMD2(2, 3), SIMD2(2, 15)]),
            (SIMD3(90, 270, 180), .north, [SIMD2(5, 1), SIMD2(5, 13), SIMD2(14, 13), SIMD2(14, 1)])
        ]
        for (rotation, direction, values) in cases {
            let model = try alternative(rotation: rotation, locked: true)
            let original = try face(model, direction)
            #expect(model.textureCoordinates(for: original, facing: direction) == values.map { $0 / 16 })
            #expect(model.rotation == rotation && model.uvLock)
        }
    }

    @Test func unlockedFacesIgnoreAllBlockRotations() throws {
        for x in stride(from: 0, to: 360, by: 90) {
            for y in stride(from: 0, to: 360, by: 90) {
                for z in stride(from: 0, to: 360, by: 90) {
                    let model = try alternative(rotation: SIMD3(x, y, z))
                    for direction in AssetModel.Direction.allCases {
                        let original = try face(model, direction)
                        #expect(model.textureCoordinates(for: original, facing: direction) == original.textureCoordinates)
                    }
                }
            }
        }
    }

    @Test func invertedAndOutsideUVRectanglesAreNotClampedOrReordered() throws {
        let reversed = try alternative(rotation: SIMD3(0, 90, 0), locked: true, uv: [13, 11, 1, 2])
        let reversedFace = try face(reversed, .up)
        #expect(reversed.textureCoordinates(for: reversedFace, facing: .up) ==
            [SIMD2<Float>(14, 13), SIMD2(14, 1), SIMD2(5, 1), SIMD2(5, 13)].map { $0 / 16 })
        let outside = try alternative(rotation: SIMD3(0, 90, 0), locked: true, uv: [-4, 0, 20, 22])
        let outsideFace = try face(outside, .up)
        #expect(outside.textureCoordinates(for: outsideFace, facing: .up) ==
            [SIMD2<Float>(-6, -4), SIMD2(-6, 20), SIMD2(16, 20), SIMD2(16, -4)].map { $0 / 16 })
        let wrapped = try alternative(rotation: SIMD3(-270, 630, -180), locked: true)
        let normalized = try alternative(rotation: SIMD3(90, 270, 180), locked: true)
        #expect(wrapped == normalized)
    }

    private enum Invalid: Error { case geometry }
}
