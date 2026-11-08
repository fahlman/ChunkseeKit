@testable import ChunkseeKit
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
}
