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
            let model = try RawModel(AssetJSON.object(from: data))
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
private struct RawModel {
    let parent: String?
    let textures: [String: TextureSlot]
    let elements: [RawElement]?
    let gui: AssetModel.Transform?
    let light: AssetModel.GuiLight?
    let ambient: Bool?

    init(_ object: [String: Any]) throws {
        parent = try object["parent"].map(AssetJSON.string)
        textures = try object["textures"].map { try AssetJSON.object($0).mapValues(TextureSlot.init) } ?? [:]
        if let raw = object["elements"] {
            let values = try AssetJSON.array(raw)
            guard values.count <= 4096 else { throw AssetReadError.limitExceeded }
            elements = try values.map(RawElement.init)
        } else { elements = nil }
        gui = try object["display"].flatMap { try AssetJSON.object($0)["gui"].map { try RawTransform($0).value } }
        if let raw = object["gui_light"] {
            guard let value = AssetModel.GuiLight(rawValue: try AssetJSON.string(raw)) else { throw AssetReadError.invalidData }
            light = value
        } else { light = nil }
        ambient = try object["ambientocclusion"].map(AssetJSON.boolean)
    }
}

private enum TextureSlot {
    case reference(String)
    case value(AssetModel.Material)

    init(_ raw: Any) throws {
        let sprite: String, translucent: Bool
        if let string = raw as? String {
            if string.hasPrefix("#") {
                guard string.count > 1 else { throw AssetReadError.invalidData }
                self = .reference(String(string.dropFirst()))
                return
            }
            sprite = string
            translucent = false
        } else {
            let object = try AssetJSON.object(raw)
            sprite = try AssetJSON.string(object["sprite"])
            translucent = try object["force_translucent"].map(AssetJSON.boolean) ?? false
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

private func vector3(_ raw: Any?) throws -> SIMD3<Float> {
    let values = try AssetJSON.numbers(raw, count: 3)
    return SIMD3(values[0], values[1], values[2])
}

private func vector4(_ raw: Any?) throws -> SIMD4<Float> {
    let values = try AssetJSON.numbers(raw, count: 4)
    return SIMD4(values[0], values[1], values[2], values[3])
}

private struct RawTransform {
    let value: AssetModel.Transform

    init(_ raw: Any) throws {
        let object = try AssetJSON.object(raw)
        let rotation = try object["rotation"].map(vector3) ?? .zero
        let translation = try object["translation"].map(vector3) ?? .zero
        let scale = try object["scale"].map(vector3) ?? .one
        value = .init(rotation: rotation, translation: clamp(translation / 16, to: -5...5), scale: clamp(scale, to: -4...4))
    }
}

private func clamp(_ vector: SIMD3<Float>, to range: ClosedRange<Float>) -> SIMD3<Float> {
    SIMD3(min(max(vector.x, range.lowerBound), range.upperBound),
          min(max(vector.y, range.lowerBound), range.upperBound),
          min(max(vector.z, range.lowerBound), range.upperBound))
}

private struct RawRotation {
    let value: AssetModel.Rotation

    init(_ raw: Any) throws {
        let object = try AssetJSON.object(raw)
        let origin = try vector3(object["origin"])
        let angles: AssetModel.Rotation.Angles
        if object["axis"] != nil || object["angle"] != nil {
            let rawAxis = try AssetJSON.string(object["axis"])
            guard let axis = AssetModel.Rotation.Axis(rawValue: rawAxis.lowercased()) else { throw AssetReadError.invalidData }
            angles = .axis(axis, try AssetJSON.number(object["angle"]))
        } else {
            guard object["x"] != nil || object["y"] != nil || object["z"] != nil else { throw AssetReadError.invalidData }
            let x = try object["x"].map(AssetJSON.number) ?? 0
            let y = try object["y"].map(AssetJSON.number) ?? 0
            let z = try object["z"].map(AssetJSON.number) ?? 0
            angles = .eulerXYZ(SIMD3(x, y, z))
        }
        value = .init(origin: origin, angles: angles, rescale: try object["rescale"].map(AssetJSON.boolean) ?? false)
    }
}

private struct RawElement {
    let from: SIMD3<Float>, to: SIMD3<Float>
    let faces: [AssetModel.Direction: RawFace]
    let rotation: AssetModel.Rotation?
    let shadeDirection: AssetModel.Direction?
    let lightEmission: Int

    init(_ raw: Any) throws {
        let object = try AssetJSON.object(raw)
        from = try vector3(object["from"])
        to = try vector3(object["to"])
        guard from == clamp(from, to: -16...32), to == clamp(to, to: -16...32) else { throw AssetReadError.invalidData }
        var faces = [AssetModel.Direction: RawFace]()
        for (name, rawFace) in try AssetJSON.object(object["faces"]) {
            guard let direction = AssetModel.Direction(rawValue: name) else { throw AssetReadError.invalidData }
            if !(rawFace is NSNull) { faces[direction] = try RawFace(rawFace) }
        }
        guard !faces.isEmpty else { throw AssetReadError.invalidData }
        self.faces = faces
        rotation = try object["rotation"].map { try RawRotation($0).value }
        if let raw = object["shade_direction_override"] {
            guard let value = AssetModel.Direction(rawValue: try AssetJSON.string(raw)) else { throw AssetReadError.invalidData }
            shadeDirection = value
        } else { shadeDirection = nil }
        lightEmission = try object["light_emission"].map(AssetJSON.integer) ?? 0
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

private struct RawFace {
    let texture: String
    let uv: SIMD4<Float>?
    let rotation: Int
    let tintIndex: Int?
    let cullFace: AssetModel.Direction?

    init(_ raw: Any) throws {
        let object = try AssetJSON.object(raw)
        texture = try AssetJSON.string(object["texture"])
        guard !texture.isEmpty else { throw AssetReadError.invalidData }
        uv = try object["uv"].map(vector4)
        let angle = try object["rotation"].map(AssetJSON.integer) ?? 0
        guard angle.isMultiple(of: 90) else { throw AssetReadError.invalidData }
        rotation = (angle % 360 + 360) % 360
        let tint = try object["tintindex"].map(AssetJSON.integer) ?? -1
        tintIndex = tint >= 0 ? tint : nil
        cullFace = try object["cullface"].map(AssetJSON.string).flatMap(AssetModel.Direction.init(rawValue:))
    }
}
