import ChunkseeKit
import ChunkseeKitTestSupport
import Foundation
import Testing

@Suite struct ResolvedBlockLightTests {
    private func chunk(block: NBT? = nil, version: Int = SaveVersion.java26_3,
                       flag: NBT? = .byte(1), sectionY: Int8? = -4) throws -> Chunk {
        var section: [String: NBT] = [:]
        section["Y"] = sectionY.map(NBT.byte)
        section["BlockLight"] = block
        var fields = try #require(Fixtures.chunk(x: -1, z: 2,
            sections: sectionY == nil ? [] : [.compound(section)]).compound)
        fields["DataVersion"] = .int(Int32(version))
        fields["isLightOn"] = flag
        return try Chunk(nbt: .compound(fields))
    }

    @Test(arguments: [SaveVersion.java26_3, SaveVersion.java26_4Snapshot5])
    func verifiedOmittedLayerIsZeroButRawDataStaysAbsent(version: Int) throws {
        for sectionY: Int8? in [-4, nil] {
            let chunk = try chunk(version: version, sectionY: sectionY)
            for y in [-80, -64, -49, -48, 0, 319] {
                #expect(chunk.resolvedBlockLight(x: 0, y: y, z: 15) == 0)
                #expect(chunk.blockLight(x: 0, y: y, z: 15) == nil)
                #expect(chunk.skyLight(x: 0, y: y, z: 15) == nil)
            }
        }
    }

    @Test func staleAndUnverifiedOmissionsStayUnknown() throws {
        for flag: NBT? in [nil, .byte(0), .string("true"), .compound([:])] {
            #expect(try chunk(flag: flag).resolvedBlockLight(x: 0, y: -64, z: 0) == nil)
            #expect(try chunk(block: .byteArray(Array(repeating: 0, count: 2048)), flag: flag)
                .resolvedBlockLight(x: 0, y: -64, z: 0) == nil)
        }
        for version in [SaveVersion.flatChunkRoot, SaveVersion.java26_2, 5022, 5024, SaveVersion.perBlockBiomes, 9999] {
            #expect(try chunk(version: version).resolvedBlockLight(x: 0, y: -64, z: 0) == nil)
            #expect(try chunk(version: version, sectionY: nil).resolvedBlockLight(x: 0, y: -64, z: 0) == nil)
            #expect(try chunk(block: .byteArray(Array(repeating: 0x33, count: 2048)), version: version)
                .resolvedBlockLight(x: 0, y: -64, z: 0) == 3)
        }
    }

    @Test func malformedPresentTagsNeverAcquireTheOmissionDefault() throws {
        let invalid: [NBT] = [.string("0"), .byte(0), .compound([:]), .list(.byte, []),
            .byteArray([]), .byteArray([0]), .byteArray(Array(repeating: 0, count: 2047)),
            .byteArray(Array(repeating: 0, count: 2049))]
        for block in invalid {
            let chunk = try chunk(block: block)
            #expect(chunk.resolvedBlockLight(x: 0, y: -64, z: 0) == nil)
            #expect(chunk.blockLight(x: 0, y: -64, z: 0) == nil)
        }
    }

    @Test func explicitLayersPreserveEveryNibbleAcrossNegativeSectionCoordinates() throws {
        var bytes = [Int8](repeating: 0, count: 2048)
        for index in 0..<4096 {
            let x = index & 15, z = (index >> 4) & 15, y = index >> 8
            let value = UInt8((x + y + z) & 15)
            bytes[index / 2] = Int8(bitPattern: UInt8(bitPattern: bytes[index / 2]) | (value << ((index & 1) * 4)))
        }
        let chunk = try chunk(block: .byteArray(bytes))
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 {
            #expect(chunk.resolvedBlockLight(x: x, y: y - 64, z: z) == ((x + y + z) & 15))
        } } }
        for (x, y, z) in [(-1, -64, 0), (16, -64, 0), (0, -64, -1), (0, -64, 16),
                           (0, Int.min, 0), (0, Int.max, 0)] {
            #expect(chunk.resolvedBlockLight(x: x, y: y, z: z) == nil)
        }
    }

    @Test func onlyCompleteOrLightRetainingReadsResolveOmissions() throws {
        let source = Fixtures.chunk(x: 0, z: 0, dataVersion: SaveVersion.java26_3, sections: [.compound(["Y": .byte(0)])],
                                    extra: ["isLightOn": .byte(1)]).serialized()
        for skipping in [Set<String>(), Chunk.keysNotNeededForTerrainAndLight] {
            let chunk = try Chunk(nbt: NBT.read(source, skipping: skipping).value)
            #expect(chunk.resolvedBlockLight(x: 0, y: 0, z: 0) == 0)
            #expect(chunk.blockLight(x: 0, y: 0, z: 0) == nil)
        }
        let terrain = try Chunk(nbt: NBT.read(source, skipping: Chunk.keysNotNeededForTerrain).value)
        #expect(!terrain.isLightOn)
        #expect(terrain.resolvedBlockLight(x: 0, y: 0, z: 0) == nil)
    }
}
