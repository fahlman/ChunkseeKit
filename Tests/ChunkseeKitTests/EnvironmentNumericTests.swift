@testable import ChunkseeKit
import Foundation
import Testing

@Suite struct EnvironmentNumericTests {
    @Test(arguments: EnvironmentNumericSample.all)
    func nativeAttributesMatchActualGameFieldResults(_ sample: EnvironmentNumericSample) throws {
        let attributes: [SkyLighting.Attribute] = [.sunAngle, .skyLightFactor, .skyLightColor]
        for (formIndex, form) in ["direct", "override", "add"].enumerated() {
            for (attributeIndex, attribute) in attributes.enumerated() {
                let entry: NBT?
                if form == "direct" { entry = sample.tag }
                else {
                    var fields: [String: NBT] = ["modifier": .string(form)]
                    fields["argument"] = sample.tag
                    entry = .compound(fields)
                }
                var fields: [String: NBT] = [:]
                fields[attribute.rawValue] = entry
                let input = NBT.compound(["attributes": .compound(fields)])
                let expected = sample.results[formIndex * attributes.count + attributeIndex]
                // Entry structure itself can be invalid, before the selected value codec runs.
                let read = { () throws -> [Float] in
                    let map = try EnvironmentAttributeMap<SkyLighting.Attribute>(nbt: input)
                    if attribute == .skyLightColor {
                        let color = try map.applying(attribute, to: SIMD3<Float>(repeating: 1))
                        return [color.x, color.y, color.z]
                    }
                    return [try map.applying(attribute, to: Float(attribute == .skyLightFactor ? 1 : 0),
                                             overrideRange: attribute == .skyLightFactor ? 0...1 : nil)]
                }
                switch expected {
                case .rejected:
                    #expect(throws: (any Error).self) { try read() }
                case .absent:
                    #expect(try read() == (attribute == .sunAngle ? [0] : attribute == .skyLightFactor ? [1] : [1, 1, 1]))
                case .scalar(let bits):
                    let actual = try #require(try read().first)
                    expect(actual, bits: bits)
                case .color(let red, let green, let blue):
                    let values = try read()
                    #expect(values.count == 3)
                    for (actual, bits) in zip(values, [red, green, blue]) { expect(actual, bits: bits) }
                }
            }
        }
    }

    private func expect(_ actual: Float, bits: UInt32) {
        // NaN payloads are not a usable color/angle; the final lighting value rejects them.
        // All finite values, infinities and signed zero retain their exact captured bits.
        if Float(bitPattern: bits).isNaN { #expect(actual.isNaN) }
        else { #expect(actual.bitPattern == bits) }
    }

    @Test func timelineKeyframesKeepTheirExistingFiniteRequirement() throws {
        let scalar = try AssetJSON.object(from: Data(#"{"modifier":"minimum","keyframes":[{"ticks":0,"value":1e100}]}"#.utf8))
        let color = try AssetJSON.object(from: Data(#"{"modifier":"subtract","keyframes":[{"ticks":0,"value":[1e100,0,0]}]}"#.utf8))
        var budget = 10
        #expect(throws: (any Error).self) {
            try TimelineTrack<Float>(json: scalar, period: nil, budget: &budget, overrideRange: nil)
        }
        #expect(throws: (any Error).self) {
            try TimelineTrack<SIMD3<Float>>(json: color, period: nil, budget: &budget, overrideRange: nil)
        }
    }

    @Test func extremaMatchTheGameForNaNAndSignedZero() throws {
        // Captured EnvironmentAttributeMap.CODEC outputs in environment-overflow-proof-1.
        for modifier in ["minimum", "maximum"] {
            let input = NBT.compound(["attributes": .compound([
                "visual/sky_light_factor": .compound(["modifier": .string(modifier), "argument": .float(.nan)])
            ])])
            let map = try EnvironmentAttributeMap<SkyLighting.Attribute>(nbt: input)
            #expect(try map.applying(.skyLightFactor, to: Float(1), overrideRange: 0...1).isNaN)
        }
        let cases: [(String, String, UInt32, UInt32)] = [
            ("minimum", "-0.0", 0x00000000, 0x80000000),
            ("maximum", "0.0", 0x80000000, 0x00000000)
        ]
        for (modifier, token, base, expected) in cases {
            let json = "{\"attributes\":{\"visual/sun_angle\":{\"modifier\":\"\(modifier)\",\"argument\":\(token)}}}"
            let map = try EnvironmentAttributeMap<SkyLighting.Attribute>(json: AssetJSON.object(from: Data(json.utf8)))
            #expect(try map.applying(.sunAngle, to: Float(bitPattern: base)).bitPattern == expected)
        }
    }
}
