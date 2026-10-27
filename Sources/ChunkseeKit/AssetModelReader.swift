import Foundation

struct AssetModelReader {
    let assets: GameAssets

    func read(_ identifier: String) throws -> AssetModel {
        var budget = AssetReadBudget()
        return try read(identifier, budget: &budget)
    }

    func read(_ identifier: String, budget: inout AssetReadBudget) throws -> AssetModel {
        var next: String? = identifier
        var seen = Set<Identifier>(), textures = [String: TextureSlot]()
        var elements: [RawElement]?, gui: AssetModel.Transform?, light: AssetModel.GuiLight?, ambient: Bool?
        var generated = false
        while let name = next {
            guard let id = GameAssets.resourceID(name), seen.insert(id).inserted else { throw AssetReadError.invalidData }
            guard seen.count <= 64 else { throw AssetReadError.limitExceeded }
            if id.description == "minecraft:builtin/generated" {
                generated = true
                light = light ?? .front
                break
            }
            let data = try assets.requiredResource(id.description, directory: "models", extension: "json", missing: AssetReadError.missingModel)
            try budget.consume(bytes: data.count)
            let model = try AssetJSON.decode(RawModel.self, from: data)
            textures.merge(model.textures) { child, _ in child }
            elements = elements ?? model.elements
            gui = gui ?? model.gui
            light = light ?? model.light
            ambient = ambient ?? model.ambient
            next = model.parent.flatMap { $0.isEmpty ? nil : $0 }
        }
        let geometry: AssetModel.Geometry
        if let elements {
            try budget.consume(elements: elements.count)
            geometry = .elements(try elements.map { try $0.resolved(in: textures) })
        } else if generated {
            var layers = [AssetModel.Layer]()
            for index in 0..<5 {
                let slot = "layer\(index)"
                guard textures[slot] != nil else { break }
                layers.append(.init(material: try material(slot, in: textures), tintIndex: index))
            }
            geometry = .layers(layers)
        } else {
            geometry = .elements([])
        }
        return .init(geometry: geometry, guiTransform: gui ?? .identity, guiLight: light ?? .side,
                     ambientOcclusion: ambient ?? true)
    }
}


/// Missing optional fields inherit/default. Explicit null or the wrong type is not absence.
private extension KeyedDecodingContainer {
    func optional<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        contains(key) ? try decode(type, forKey: key) : nil
    }
}

private struct RawModel: Decodable {
    let parent: String?
    let textures: [String: TextureSlot]
    let elements: [RawElement]?
    let gui: AssetModel.Transform?
    let light: AssetModel.GuiLight?
    let ambient: Bool?

    private enum Keys: String, CodingKey { case parent, textures, elements, display, gui_light, ambientocclusion }
    private struct Display: Decodable {
        let gui: RawTransform?
        private enum Keys: String, CodingKey { case gui }
        init(from decoder: any Decoder) throws {
            gui = try decoder.container(keyedBy: Keys.self).optional(RawTransform.self, forKey: .gui)
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        parent = try c.optional(String.self, forKey: .parent)
        textures = try c.optional([String: TextureSlot].self, forKey: .textures) ?? [:]
        elements = try c.optional([RawElement].self, forKey: .elements)
        guard (elements?.count ?? 0) <= 4096 else { throw AssetReadError.limitExceeded }
        gui = try c.optional(Display.self, forKey: .display)?.gui?.value
        light = try c.optional(AssetModel.GuiLight.self, forKey: .gui_light)
        ambient = try c.optional(Bool.self, forKey: .ambientocclusion)
    }
}

private enum TextureSlot: Decodable {
    case reference(String)
    case value(AssetModel.Material)

    private enum Keys: String, CodingKey { case sprite, force_translucent }
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let sprite: String, translucent: Bool
        if let string = try? c.decode(String.self) {
            if string.hasPrefix("#") {
                guard string.count > 1 else { throw AssetReadError.invalidData }
                self = .reference(String(string.dropFirst()))
                return
            }
            sprite = string
            translucent = false
        } else {
            let object = try decoder.container(keyedBy: Keys.self)
            sprite = try object.decode(String.self, forKey: .sprite)
            translucent = try object.optional(Bool.self, forKey: .force_translucent) ?? false
        }
        guard let id = GameAssets.resourceID(sprite) else { throw AssetReadError.invalidData }
        self = .value(.init(texture: id, forceTranslucent: translucent))
    }
}

private func material(_ reference: String, in textures: [String: TextureSlot]) throws -> AssetModel.Material {
    // Face references are slot names, optionally prefixed with '#', not literal texture IDs.
    var name = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
    var seen = Set<String>()
    while true {
        guard seen.insert(name).inserted else { throw AssetReadError.invalidData }
        guard seen.count <= 64 else { throw AssetReadError.limitExceeded }
        guard let slot = textures[name] else { throw AssetReadError.invalidData }
        switch slot {
        case .value(let value): return value
        case .reference(let next): name = next
        }
    }
}

private struct Vector3: Decodable {
    let value: SIMD3<Float>
    init(from decoder: any Decoder) throws {
        let a = try decoder.singleValueContainer().decode([Float].self)
        guard a.count == 3, a.allSatisfy(\.isFinite) else { throw AssetReadError.invalidData }
        value = SIMD3(a[0], a[1], a[2])
    }
}

private struct Vector4: Decodable {
    let value: SIMD4<Float>
    init(from decoder: any Decoder) throws {
        let a = try decoder.singleValueContainer().decode([Float].self)
        guard a.count == 4, a.allSatisfy(\.isFinite) else { throw AssetReadError.invalidData }
        value = SIMD4(a[0], a[1], a[2], a[3])
    }
}

private struct RawTransform: Decodable {
    let value: AssetModel.Transform
    private enum Keys: String, CodingKey { case rotation, translation, scale }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let rotation = try c.optional(Vector3.self, forKey: .rotation)?.value ?? .zero
        let translation = try c.optional(Vector3.self, forKey: .translation)?.value ?? .zero
        let scale = try c.optional(Vector3.self, forKey: .scale)?.value ?? .one
        value = .init(rotation: rotation, translation: clamp(translation / 16, to: -5...5), scale: clamp(scale, to: -4...4))
    }
}

private func clamp(_ vector: SIMD3<Float>, to range: ClosedRange<Float>) -> SIMD3<Float> {
    SIMD3(min(max(vector.x, range.lowerBound), range.upperBound),
          min(max(vector.y, range.lowerBound), range.upperBound),
          min(max(vector.z, range.lowerBound), range.upperBound))
}

private struct RawRotation: Decodable {
    let value: AssetModel.Rotation
    private enum Keys: String, CodingKey { case origin, axis, angle, x, y, z, rescale }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let origin = try c.decode(Vector3.self, forKey: .origin).value
        let angles: AssetModel.Rotation.Angles
        if c.contains(.axis) || c.contains(.angle) {
            let rawAxis = try c.decode(String.self, forKey: .axis)
            guard let axis = AssetModel.Rotation.Axis(rawValue: rawAxis.lowercased()) else { throw AssetReadError.invalidData }
            let angle = try c.decode(Float.self, forKey: .angle)
            guard angle.isFinite else { throw AssetReadError.invalidData }
            angles = .axis(axis, angle)
        } else {
            guard c.contains(.x) || c.contains(.y) || c.contains(.z) else { throw AssetReadError.invalidData }
            let x = try c.optional(Float.self, forKey: .x) ?? 0
            let y = try c.optional(Float.self, forKey: .y) ?? 0
            let z = try c.optional(Float.self, forKey: .z) ?? 0
            guard x.isFinite, y.isFinite, z.isFinite else { throw AssetReadError.invalidData }
            angles = .eulerXYZ(SIMD3(x, y, z))
        }
        value = .init(origin: origin, angles: angles, rescale: try c.optional(Bool.self, forKey: .rescale) ?? false)
    }
}

private struct RawElement: Decodable {
    let from: SIMD3<Float>, to: SIMD3<Float>
    let faces: [AssetModel.Direction: RawFace]
    let rotation: AssetModel.Rotation?
    let shadeDirection: AssetModel.Direction?
    let lightEmission: Int
    private enum Keys: String, CodingKey { case from, to, faces, rotation, shade_direction_override, light_emission }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        from = try c.decode(Vector3.self, forKey: .from).value
        to = try c.decode(Vector3.self, forKey: .to).value
        guard from == clamp(from, to: -16...32), to == clamp(to, to: -16...32) else { throw AssetReadError.invalidData }
        var faces = [AssetModel.Direction: RawFace]()
        for (name, face) in try c.decode([String: RawFace?].self, forKey: .faces) {
            guard let direction = AssetModel.Direction(rawValue: name) else { throw AssetReadError.invalidData }
            if let face { faces[direction] = face }
        }
        guard !faces.isEmpty else { throw AssetReadError.invalidData }
        self.faces = faces
        rotation = try c.optional(RawRotation.self, forKey: .rotation)?.value
        shadeDirection = try c.optional(AssetModel.Direction.self, forKey: .shade_direction_override)
        lightEmission = Int(try c.optional(Int32.self, forKey: .light_emission) ?? 0)
        guard (0...15).contains(lightEmission) else { throw AssetReadError.invalidData }
    }

    func resolved(in textures: [String: TextureSlot]) throws -> AssetModel.Element {
        var resolved = [AssetModel.Direction: AssetModel.Face]()
        for (direction, face) in faces {
            resolved[direction] = .init(material: try material(face.texture, in: textures),
                uv: face.uv ?? defaultUV(direction), rotation: face.rotation, tintIndex: face.tintIndex,
                cullFace: face.cullFace)
        }
        return .init(from: from, to: to, faces: resolved, rotation: rotation,
                     shadeDirectionOverride: shadeDirection, lightEmission: lightEmission)
    }

    /// FaceBakery.defaultFaceUV in the official 26.3 client; keep format defaults out of renderers.
    private func defaultUV(_ direction: AssetModel.Direction) -> SIMD4<Float> {
        switch direction {
        case .down: SIMD4(from.x, 16 - to.z, to.x, 16 - from.z)
        case .up: SIMD4(from.x, from.z, to.x, to.z)
        case .north: SIMD4(16 - to.x, 16 - to.y, 16 - from.x, 16 - from.y)
        case .south: SIMD4(from.x, 16 - to.y, to.x, 16 - from.y)
        case .west: SIMD4(from.z, 16 - to.y, to.z, 16 - from.y)
        case .east: SIMD4(16 - to.z, 16 - to.y, 16 - from.z, 16 - from.y)
        }
    }
}

private struct RawFace: Decodable {
    let texture: String
    let uv: SIMD4<Float>?
    let rotation: Int
    let tintIndex: Int?
    let cullFace: AssetModel.Direction?
    private enum Keys: String, CodingKey { case texture, uv, rotation, tintindex, cullface }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        texture = try c.decode(String.self, forKey: .texture)
        guard !texture.isEmpty else { throw AssetReadError.invalidData }
        uv = try c.optional(Vector4.self, forKey: .uv)?.value
        let angle = Int(try c.optional(Int32.self, forKey: .rotation) ?? 0)
        guard angle.isMultiple(of: 90) else { throw AssetReadError.invalidData }
        rotation = (angle % 360 + 360) % 360
        let tint = try c.optional(Int32.self, forKey: .tintindex) ?? -1
        tintIndex = tint >= 0 ? Int(tint) : nil
        cullFace = try c.optional(String.self, forKey: .cullface).flatMap(AssetModel.Direction.init(rawValue:))
    }
}
