"""Translate actual baked polygons into the library's cuboid/UV representation."""
import math
import re


def generated_special_models(facts, notice):
    def number(value):
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError("Non-finite model coordinate")
        return repr(float(value)) if value else "0"

    def vector(values):
        return f"SIMD{len(values)}(" + ", ".join(number(v) for v in values) + ")"

    def quote(value):
        import json
        return json.dumps(value)

    def near(a, b, tolerance=0.00004):
        return all(abs(x - y) <= tolerance for x, y in zip(a, b))

    def rotate(point, angles):
        x, y, z = point
        cx, cy, cz = [math.cos(v) for v in angles]
        sx, sy, sz = [math.sin(v) for v in angles]
        y, z = cx * y - sx * z, sx * y + cx * z
        x, z = cy * x + sy * z, -sy * x + cy * z
        return [cz * x - sz * y, sz * x + cz * y, z]

    directions = {"down": [0, -1, 0], "up": [0, 1, 0], "north": [0, 0, -1],
                  "south": [0, 0, 1], "west": [-1, 0, 0], "east": [1, 0, 0]}

    def element(part):
        matrix, scales = part["matrix"], part["scale"]
        if len(matrix) != 16 or len(scales) != 3 or min(scales) <= 0 or not near(scales, [scales[0]] * 3):
            raise ValueError("Unrepresentable special-model scale")
        scale = sum(scales) / 3
        translation = [v * 16 for v in matrix[12:15]]
        rotation = [[matrix[column * 4 + row] / scale for column in range(3)] for row in range(3)]
        aligned = all(abs(v - round(v)) < 0.000001 for row in rotation for v in row)
        snapped = [[round(v) for v in row] for row in rotation]
        if aligned and (any(sum(abs(v) for v in row) != 1 for row in snapped)
                        or any(sum(abs(snapped[r][c]) for r in range(3)) != 1 for c in range(3))):
            raise ValueError("Invalid axis-aligned rotation")
        angles = [0 if abs(v) < 0.000001 else v for v in part["angles"]]

        def transform(point, is_normal=False):
            if aligned:
                return [sum(snapped[r][c] * point[c] for c in range(3)) * (1 if is_normal else scale)
                        + (0 if is_normal else translation[r]) for r in range(3)]
            return point if is_normal else [point[r] * scale + translation[r] for r in range(3)]

        points = [transform(v["local"]) for p in part["polygons"] for v in p["vertices"]]
        if not points:
            raise ValueError("Empty special-model cube")
        low = [min(p[i] for p in points) for i in range(3)]
        high = [max(p[i] for p in points) for i in range(3)]
        faces = []
        seen = set()
        for polygon in part["polygons"]:
            normal = transform(polygon["normal"], True)
            facing = next((key for key, value in directions.items() if near(normal, value)), None)
            if facing is None or facing in seen:
                raise ValueError("Unknown or duplicate model face")
            seen.add(facing)
            vertices = polygon["vertices"]
            ordered = []
            for corner in facts["faceCorners"][facing]:
                point = [low[i] + (high[i] - low[i]) * corner[i] for i in range(3)]
                matches = [v["uv"] for v in vertices if near(point, transform(v["local"]))]
                if not matches or any(not near(matches[0], value, 0.000001) for value in matches):
                    raise ValueError("Ambiguous model UV corner")
                ordered.append(matches[0])
            choices = []
            for turns in range(4):
                base = [ordered[(i - turns) % 4] for i in range(4)]
                uv = [*base[0], *base[2]]
                corners = [[uv[0], uv[1]], [uv[0], uv[3]], [uv[2], uv[3]], [uv[2], uv[1]]]
                if all(near(ordered[i], corners[(i + turns) % 4], 0.000001) for i in range(4)):
                    score = (uv[0] > uv[2], uv[1] > uv[3], turns)
                    choices.append((score, turns * 90, [v * 16 for v in uv]))
            if not choices:
                raise ValueError("UVs cannot be represented by a rotated rectangle")
            _, turn, uv = min(choices)
            faces.append(f".{facing}: .init(uv: {vector(uv)}, rotation: {turn})")
            # Every emitted coordinate/rotation must reproduce the actual posed vertex.
            for vertex in vertices:
                point = transform(vertex["local"])
                if not aligned:
                    point = [v + translation[i] for i, v in enumerate(rotate(
                        [point[i] - translation[i] for i in range(3)], angles))]
                if not near(point, vertex["posed"]):
                    raise ValueError("Emitted special-model pose differs from Minecraft")
        angle_source = "nil"
        if not aligned:
            nonzero = [i for i, value in enumerate(angles) if value != 0]
            degrees = [value * 180 / math.pi for value in angles]
            if len(nonzero) == 1:
                i = nonzero[0]
                representation = f".axis(.{'xyz'[i]}, {number(degrees[i])})"
            else:
                representation = f".eulerXYZ({vector(degrees)})"
            angle_source = f".init(origin: {vector(translation)}, angles: {representation}, rescale: false)"
        width, height = part["skinSize"]
        if min(width, height) <= 0:
            raise ValueError("Invalid special-model texture size")
        material = part["material"]
        if material not in {"primary", "plain", "front", "back", "left", "right"}:
            raise ValueError("Unknown special-model material role")
        return (f".init(from: {vector(low)}, to: {vector(high)}, rotation: {angle_source},\n"
                f"              faces: [" + ", ".join(faces) + f"],\n"
                f"              textureAspectRatio: {number(width / height)}, material: .{material})")

    source = notice + "// Actual baked polygons and static inventory poses; no bundled artwork.\n"
    source += "enum GeneratedSpecialItemModels {\n    static let textures: [String: String] = [\n"
    for key, value in sorted(facts["textures"].items()):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value):
            raise ValueError("Invalid generated texture identifier")
        source += f"        {quote(key)}: {quote(value)},\n"
    source += "    ]\n    static let models: [String: [SpecialItemGeometry.Part]] = [\n"
    for key, model in sorted(facts["models"].items()):
        source += f"        {quote(key)}: [\n"
        for part in model["parts"]:
            source += "            // " + part["source"] + " " + part["part"] + "\n"
            source += "            " + element(part) + ",\n"
        source += "        ],\n"
    return source + "    ]\n}\n"
