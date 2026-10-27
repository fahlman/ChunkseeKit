#!/usr/bin/env python3
"""Regenerate code-only game facts from an installed, hash-verified official release."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import textwrap
import zipfile
from special_item_models import generated_special_models


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def canonical_extraction(raw, output):
    # Game-fixer maps do not promise iteration order. Keep the original bytes as evidence,
    # but hash a stable representation of JSON objects without reordering arrays or values.
    value = json.loads(raw.read_text())
    output.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    return value


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def creature_color_sources(facts, entities, notice):
    source = notice + "// Sources: SheepRenderState.getWoolColor/ColorLerper.Type.SHEEP and AxolotlRenderer.TEXTURE_BY_TYPE.\n"
    source += "enum GeneratedCreatureColors {\n"
    proofs = notice + "import ChunkseeKit\n\nenum GeneratedCreatureColorProofs {\n"
    proofs += "    struct Case: Sendable {\n        let species: String\n        let variant: String\n        let expected: CreatureAppearance.ColorSource\n    }\n\n"
    proof_rows, mappings = [], []

    def identifier(value):
        if not isinstance(value, str) or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value):
            raise ValueError("Invalid creature color identifier: " + str(value))
        return quoted(value)

    def value(kind, raw):
        if kind == "tint" and type(raw) is int and 0 <= raw <= 0xffffff:
            return f".tint(0x{raw:06x})"
        if kind == "texture": return ".texture(" + identifier(raw) + ")"
        raise ValueError("Invalid creature color source")

    for index, entry in enumerate(facts):
        if not entry["values"] or entry["values"].keys() != entry["proofs"].keys():
            raise ValueError("Missing creature color proofs")
        members = [name for name, entity in sorted(entities.items()) if entry["entityClass"] in entity["ancestry"]]
        if not members: raise ValueError("Unregistered creature color class: " + entry["entityClass"])
        source += f"    // {entry['entityClass']}\n"
        source += f"    private static let values{index}: [String: CreatureAppearance.ColorSource] = [\n"
        for variant, raw in sorted(entry["values"].items()):
            source += f"        {identifier(variant)}: {value(entry['kind'], raw)},\n"
        source += "    ]\n\n"
        for species in members:
            mappings.append(f"        {identifier(species)}: values{index},\n")
            for variant, expected in sorted(entry["proofs"].items()):
                proof_rows.append(f"        Case(species: {identifier(species)}, variant: {identifier(variant)}, expected: {value(entry['kind'], expected)}),\n")
    source += "    static let sources: [String: [String: CreatureAppearance.ColorSource]] = [\n" + "".join(mappings) + "    ]\n}\n"
    proofs += "    // Results from the game's render-state and texture-selection methods.\n"
    proofs += "    static let cases: [Case] = [\n" + "".join(proof_rows) + "    ]\n}\n"
    return {"Sources/ChunkseeKit/GeneratedCreatureColors.swift": source,
            "Tests/ChunkseeKitTests/GeneratedCreatureColorProofs.swift": proofs}


def keyed_values(values, prefix="minecraft:"):
    entries = []
    for key, value in sorted(values.items(), key=lambda item: int(item[0])):
        if not re.fullmatch(r"[a-z0-9_.:/-]+", value):
            raise ValueError("Unsupported appearance identifier: " + value)
        entries.append(f"{int(key)}: {quoted(prefix + value)}")
    if not entries:
        raise ValueError("An extracted mapping was empty")
    return "[" + ", ".join(entries) + "]"


def non_block_definitions_source(identifiers, notice):
    if not isinstance(identifiers, list) or len(set(identifiers)) != len(identifiers):
        raise ValueError("Invalid rendering-only definition identifiers")
    if any(not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value) for value in identifiers):
        raise ValueError("Invalid rendering-only definition identifier")
    result = notice + "enum GeneratedNonBlockDefinitions {\n"
    result += "    // BlockStateDefinitions.STATIC_DEFINITIONS, excluding BuiltInRegistries.BLOCK entries.\n"
    result += "    static let ids: Set<String> = [" + ", ".join(map(quoted, sorted(identifiers))) + "]\n}\n"
    return result


def block_items_source(items, notice):
    if not isinstance(items, dict) or not items:
        raise ValueError("Missing block-item relationships")
    result = notice + "enum GeneratedBlockItems {\n"
    result += "    // Each entry is Block.asItem, checked against Item.byBlock after registry bootstrap.\n"
    result += "    static let items: [String: String] = [\n"
    for block, item in sorted(items.items()):
        if any(not isinstance(value, str) or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value)
               for value in [block, item]):
            raise ValueError("Invalid block-item identifier")
        result += f"        {quoted(block)}: {quoted(item)},\n"
    return result + "    ]\n}\n"


def legacy_chunk_source(facts, notice):
    result = notice + "// ChunkHeightAndBiomeFix and the preceding format fixers; not a biome catalog.\n"
    result += "enum GeneratedLegacyChunkFacts {\n"
    for name, source in {"heightmapNameBoundary": "HeightmapRenamingFix",
                         "sectionBoundary": "ChunkHeightAndBiomeFix"}.items():
        result += f"    static let {name} = {int(facts['boundaries'][source])}\n"
    result += "    // Repeated ChunkDeleteLightFix instances; any later reset invalidates saved light.\n"
    result += f"    static let lightResetBoundary = {max(map(int, facts['lightResets']))}\n"
    for name, source in {"oldSectionCount": "OLD_SECTION_COUNT", "newSectionCount": "NEW_SECTION_COUNT",
                         "newMinSectionY": "NEW_MIN_SECTION_Y", "heightmapBits": "HEIGHTMAP_BITS",
                         "biomeContainerSize": "BIOME_CONTAINER_SIZE"}.items():
        result += f"    static let {name} = {int(facts['geometry'][source])}\n"
    for name in ["emptyBlock", "defaultBiome"]:
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", facts[name]):
            raise ValueError("Invalid legacy chunk default")
        result += f"    static let {name} = {quoted(facts[name])}\n"
    result += "    // ChunkHeightAndBiomeFix.BIOMES_BY_ID; only numeric save-code meanings.\n"
    result += "    static let biomes: [Int: String] = [\n"
    for number, identifier in sorted(facts["biomes"].items(), key=lambda row: int(row[0])):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Invalid legacy biome identity")
        result += f"        {int(number)}: {quoted(identifier)},\n"
    result += "    ]\n    static let statusSteps: [SaveDataUpgrade.ChunkStatusRename] = [\n"
    for step in facts["statusSteps"]:
        result += "        // " + step["source"] + ".\n"
        changes = ", ".join(quoted(k) + ": " + quoted(v) for k, v in sorted(step["aliases"].items())) or ":"
        fallback = quoted(step["fallback"]) if "fallback" in step else "nil"
        result += f"        .init(version: {step['version']}, aliases: [{changes}], fallback: {fallback}),\n"
    result += "    ]\n    // HeightmapRenamingFix.fix; a name can split into several maps.\n"
    result += "    static let heightmapNames: [String: [String]] = [\n"
    for name, targets in sorted(facts["heightmapNames"].items()):
        result += f"        {quoted(name)}: [" + ", ".join(map(quoted, targets)) + "],\n"
    return result + "    ]\n}\n"


def legacy_chunk_proofs(facts, notice):
    result = notice + "// Whole synthetic chunks passed through Minecraft's complete CHUNK fix chain.\n"
    result += "enum GeneratedLegacyChunkProofs {\n"
    result += "    struct Record: Sendable { let name: String; let version: Int; let input: String; let output: String }\n"
    result += "    static let records: [Record] = [\n"
    for row in facts["records"]:
        source = quoted(json.dumps(row["input"], separators=(",", ":"), sort_keys=True))
        output = quoted(json.dumps(row["output"], separators=(",", ":"), sort_keys=True))
        result += f"        .init(name: {quoted(row['name'])}, version: {row['version']}, input: {source}, output: {output}),\n"
    return result + "    ]\n}\n"


def save_renames_source(facts, notice):
    steps = facts["steps"]
    if not steps:
        raise ValueError("No save rename steps")
    result = notice + "// DataFixers' actual rename instances, in application order. Not an ID catalog.\n"
    result += "enum GeneratedSaveRenames {\n"
    result += f"    static let lastVersion = {max(step['version'] for step in steps + facts['attributeSteps'])}\n"
    result += "    static let steps: [SaveDataUpgrade.Rename] = [\n"
    previous = -1
    for step in steps:
        if step["kind"] not in {"block", "item", "biome", "entity", "blockEntity", "enchantment", "recipe", "advancement", "stat"} or type(step["version"]) is not int or step["version"] < previous:
            raise ValueError("Invalid or unordered save rename step")
        previous = step["version"]
        result += "        // " + step["source"] + ": " + step["name"] + ".\n"
        result += f"        .init(kind: .{step['kind']}, version: {step['version']}, changes: [\n"
        for old, new in sorted(step["changes"].items()):
            input_pattern = r"(?:[a-z0-9_.-]*:)?[a-z0-9_./-]+" if step["kind"] == "advancement" else r"[a-z0-9_.-]+:[a-z0-9_./-]+"
            if not re.fullmatch(input_pattern, old) or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", new) or old == new:
                raise ValueError("Invalid save rename")
            result += f"            {quoted(old)}: {quoted(new)},\n"
        result += "        ]),\n"
    result += "    ]\n"
    result += "    static let attributeSteps: [SaveDataUpgrade.AttributeRename] = [\n"
    previous = -1
    for step in facts["attributeSteps"]:
        if type(step["version"]) is not int or step["version"] < previous:
            raise ValueError("Invalid attribute rename order")
        previous = step["version"]
        result += "        // " + step["source"] + ": " + step["name"] + ".\n"
        changes = ", ".join(quoted(k) + ": " + quoted(v) for k, v in sorted(step["changes"].items())) or ":"
        prefixes = ", ".join(f".init(from: {quoted(p['from'])}, to: {quoted(p['to'])})" for p in step["prefixes"])
        result += f"        .init(version: {step['version']}, changes: [{changes}], prefixes: [{prefixes}]),\n"
    result += "    ]\n"
    for kind, versions in sorted(facts["entityIntroductions"].items()):
        result += f"    // First input schema accepting each renamed {kind} ID; not a membership catalog.\n"
        result += f"    static let {kind}Introductions: [String: Int] = [\n"
        for name, version in sorted(versions.items()):
            if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", name) or type(version) is not int:
                raise ValueError("Invalid entity rename applicability")
            result += f"        {quoted(name)}: {version},\n"
        result += "    ]\n"
    numeric = facts["numericItems"]
    result += "    // " + numeric["source"] + ". Historical numeric item codec, not current membership.\n"
    result += f"    static let numericItemBoundary = {numeric['boundary']}\n"
    result += f"    static let numericItemFallback = {quoted(numeric['fallback'])}\n"
    result += "    static let numericItems: [Int32: String] = [\n"
    for number, name in sorted(numeric["mappings"].items(), key=lambda entry: int(entry[0])):
        if not -(2**31) <= int(number) < 2**31 or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", name):
            raise ValueError("Invalid numeric item meaning")
        result += f"        {int(number)}: {quoted(name)},\n"
    result += "    ]\n"
    item_names = facts["itemNames"]
    result += "    // " + item_names["source"] + ". Saved string identity and variant, not numeric item IDs.\n"
    result += f"    static let itemNameBoundary = {item_names['boundary']}\n"
    result += "    static let itemNames: [String: [Int: String]] = [\n"
    for name, variants in sorted(item_names["mappings"].items()):
        values = ", ".join(f"{int(k)}: {quoted(v)}" for k, v in sorted(variants.items(), key=lambda x: int(x[0])))
        result += f"        {quoted(name)}: [{values}],\n"
    result += "    ]\n"
    result += "    static let itemDamageChanges: [SaveDataUpgrade.DamageChange] = [\n"
    for row in facts["itemDamageChanges"]:
        result += "        // " + row["source"] + ".\n"
        changes = ", ".join(f"{int(old)}: {int(new)}" for old, new in sorted(row["changes"].items()))
        result += f"        .init(id: {quoted(row['id'])}, version: {row['version']}, changes: [{changes}]),\n"
    return result + "    ]\n}\n"


def save_rename_proofs_source(facts, notice):
    result = notice + "// Expected names returned by Minecraft's full DataFixers.update chain.\n"
    result += "enum GeneratedSaveRenameProofs {\n"
    result += "    struct Sample: Sendable { let kind: String; let version: Int; let input: String; let expected: String }\n"
    result += "    static let samples: [Sample] = [\n"
    for row in facts["proofs"]:
        if row["kind"] in {"entity", "blockEntity"}:
            continue
        result += f"        .init(kind: {quoted(row['kind'])}, version: {row['version']}, input: {quoted(row['input'])}, expected: {quoted(row['expected'])}),\n"
    result += "    ]\n"
    result += "    struct EntitySample: Sendable { let kind: String; let input: String; let expected: String; let versions: [Int] }\n"
    result += "    static let entitySamples: [EntitySample] = [\n"
    groups = {}
    for row in facts["proofs"]:
        if row["kind"] in {"entity", "blockEntity"}:
            groups.setdefault((row["kind"], row["input"], row["expected"]), set()).add(row["version"])
    for (kind, name, expected), versions in sorted(groups.items()):
        result += f"        .init(kind: {quoted(kind)}, input: {quoted(name)}, expected: {quoted(expected)}, versions: [\n"
        result += textwrap.indent(textwrap.fill(", ".join(map(str, sorted(versions))), width=100), "            ") + "\n"
        result += "        ]),\n"
    result += "    ]\n"
    result += "    struct Record: Sendable { let kind: String; let version: Int; let input: String; let output: String }\n"
    result += "    static let records: [Record] = [\n"
    for row in facts["records"]:
        source = quoted(json.dumps(row["input"], separators=(",", ":"), sort_keys=True))
        output = quoted(json.dumps(row["output"], separators=(",", ":"), sort_keys=True))
        result += f"        .init(kind: {quoted(row['kind'])}, version: {row['version']}, input: {source}, output: {output}),\n"
    result += "    ]\n"
    result += "    struct LegacyItem: Sendable { let version: Int; let input: String; let damage: Int; let expected: String }\n"
    result += "    static let legacyItems: [LegacyItem] = [\n"
    for row in facts["itemNames"]["proofs"]:
        result += f"        .init(version: {row['version']}, input: {quoted(row['input'])}, damage: {row['damage']}, expected: {quoted(row['expected'])}),\n"
    result += "    ]\n"
    result += "    // Actual ITEM_STACK IDs at the numeric codec boundary; later field conversions are separate.\n"
    result += "    struct NumericItem: Sendable { let version: Int; let input: Int32; let expected: String? }\n"
    result += "    static let numericItems: [NumericItem] = [\n"
    for row in facts["numericItems"]["proofs"]:
        expected = quoted(row["expected"]) if isinstance(row["expected"], str) else "nil"
        result += f"        .init(version: {row['version']}, input: {row['input']}, expected: {expected}),\n"
    return result + "    ]\n}\n"


def portal_source(facts, notice):
    result = notice + "// NetherPortalBlock, PortalForcer, DimensionType codec and WorldBorder methods.\n"
    result += "// Runtime dimension scales and saved borders are never bundled.\n"
    result += "enum GeneratedPortalFacts {\n"
    for name, value in facts.items():
        if isinstance(value, str):
            if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value):
                raise ValueError("Invalid portal dimension identifier")
            literal = quoted(value)
        elif type(value) in (int, float) and value > 0:
            literal = repr(value)
        else:
            raise ValueError("Invalid portal fact: " + name)
        result += f"    static let {name} = {literal}\n"
    return result + "}\n"



def legacy_content_sources(facts, notice):
    effects = {int(key): value for key, value in facts["effects"].items()}
    patterns = facts["patterns"]
    def identifier(value):
        if not isinstance(value, str) or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value):
            raise ValueError("Invalid legacy content identity")
        return quoted(value)
    if not effects or min(effects) < 0 or max(effects) > 65535 or not patterns:
        raise ValueError("Invalid legacy content maps")
    source = notice + "// MobEffectIdFix.ID_MAP and BannerPatternFormatFix.PATTERN_ID_MAP.\n"
    source += "enum GeneratedLegacyContentIDs {\n    static let effects: [String?] = [\n"
    for index in range(max(effects) + 1):
        source += "        " + (identifier(effects[index]) if index in effects else "nil") + ",\n"
    source += "    ]\n    static let bannerPatterns: [String: String] = [\n"
    for before, after in sorted(patterns.items()):
        source += f"        {quoted(before)}: {identifier(after)},\n"
    source += "    ]\n}\n"
    proofs = notice + "// Full native-NBT PLAYER/BLOCK_ENTITY upgrades through the game's current fixers.\n"
    proofs += "import ChunkseeKit\n\nenum GeneratedLegacyContentProofs {\n"
    proofs += "    static let effects: [(tag: NBT, id: String?)] = [\n"
    for sample in facts["effectProofs"]:
        expected = identifier(sample["id"]) if sample.get("id") is not None else "nil"
        proofs += f"        ({sample['tag']}, {expected}),\n"
    proofs += "    ]\n    static let patterns: [(before: String, id: String)] = [\n"
    for sample in facts["patternProofs"]:
        proofs += f"        ({quoted(sample['before'])}, {quoted(sample['id'])}),\n"
    return source, proofs + "    ]\n}\n"


def map_color_sources(facts, notice):
    colors, brightness, argb = (facts[key] for key in ("baseColors", "brightness", "argb"))
    if len(colors) != 64 or not any(color is not None for color in colors) or any(
            color is not None and (type(color) is not int or not 0 <= color <= 0xffffff)
            for color in colors):
        raise ValueError("Invalid map base colors")
    if len(brightness) != 4 or any(type(value) is not int or not 0 <= value <= 255 for value in brightness):
        raise ValueError("Invalid map brightness")
    if len(argb) != 256 or any(type(value) is not int or not 0 <= value <= 0xffffffff
                             or value >> 24 not in (0, 255) for value in argb):
        raise ValueError("Invalid packed map-color proofs")
    source = notice + "// MapColor.byId/col and Brightness.modifier; NONE remains transparent.\n"
    source += "enum GeneratedMapColors {\n    static let baseColors: [UInt32?] = [\n"
    for start in range(0, len(colors), 8):
        source += "        " + ", ".join("nil" if color is None else f"0x{color:06X}"
                                        for color in colors[start:start + 8]) + ",\n"
    source += "    ]\n    static let brightness = [" + ", ".join(map(str, brightness)) + "]\n}\n"
    proofs = notice + "// Actual MapColor.getColorFromPackedId outputs, indexed by every saved UInt8.\n"
    proofs += "enum GeneratedMapColorProofs {\n    static let argb: [UInt32] = [\n"
    for start in range(0, len(argb), 8):
        proofs += "        " + ", ".join(f"0x{color:08X}" for color in argb[start:start + 8]) + ",\n"
    return source, proofs + "    ]\n}\n"


def light_storage_sources(facts, notice):
    absent = facts["absentBlockLight"]
    if type(absent) is not int or not 0 <= absent <= 15 or not facts["samples"]:
        raise ValueError("Invalid absent block light")
    source = notice + "// BlockLightSectionStorage.getLightValue with no stored layer.\n"
    source += f"enum GeneratedLightStorage {{\n    static let absentBlockLight = {absent}\n}}\n"
    proofs = notice + "// Actual game reads from empty block-light storage at varied coordinates.\n"
    proofs += "enum GeneratedLightStorageProofs {\n"
    proofs += "    static let samples: [(x: Int, y: Int, z: Int, value: Int)] = [\n"
    for sample in facts["samples"]:
        if any(type(sample[key]) is not int for key in ("x", "y", "z", "value")) or sample["value"] != absent:
            raise ValueError("Invalid absent-light proof")
        proofs += f"        ({sample['x']}, {sample['y']}, {sample['z']}, {sample['value']}),\n"
    return source, proofs + "    ]\n}\n"


def health_default_sources(facts, entities, notice):
    def number(value):
        if type(value) not in (int, float) or not math.isfinite(value):
            raise ValueError("Invalid health default")
        return str(float(value))

    low, high = facts["minimumCubeSize"], facts["maximumCubeSize"]
    if type(low) is not int or type(high) is not int or not 1 <= low <= high <= 4096:
        raise ValueError("Invalid cube size range")
    bases, actual = facts["bases"], facts["attributeValues"]
    if bases.keys() != actual.keys() or not bases.keys() <= entities.keys() or facts["player"] not in bases:
        raise ValueError("Incomplete health defaults or proofs")
    rules = {rule["class"]: rule for rule in facts["loadingRules"]}
    if len(rules) != len(facts["loadingRules"]):
        raise ValueError("Duplicate health loading rules")
    curves = [rule for _, rule in sorted(rules.items()) if rule["kind"] == "cubeSize"]
    for rule in rules.values():
        if rule["kind"] == "cubeSize":
            if len(rule["bases"]) != high - low + 1 or len(rule["actual"]) != high - low + 1:
                raise ValueError("Incomplete cube health curve")
        elif rule["kind"] != "untamedReset":
            raise ValueError("Unsupported health loading rule")

    source = notice + "// DefaultAttributes -> AttributeSupplier; bounds from Attributes.MAX_HEALTH.\n"
    source += "enum GeneratedHealthDefaults {\n    static let bases: [String: Double] = [\n"
    for species, value in sorted(bases.items()):
        source += f"        {quoted(species)}: {number(value)},\n"
    source += "    ]\n"
    source += f"    static let player = {quoted(facts['player'])}\n"
    source += f"    static let minimum = {number(facts['minimum'])}\n"
    source += f"    static let maximum = {number(facts['maximum'])}\n"
    source += f"    static let minimumCubeSize = {low}\n    static let maximumCubeSize = {high}\n"
    source += "    // Actual setCubeMobHealth outputs, before saved attributes load.\n"
    source += "    static let cubeBases: [[Double]] = [\n"
    for rule in curves:
        source += f"        // {rule['class']}.setCubeMobHealth\n"
        source += "        [" + ", ".join(number(value) for value in rule["bases"]) + "],\n"
    source += "    ]\n"

    defaults, sized, resets = {}, {}, {}
    source += "    static let cubeKinds: [String: Int] = [\n"
    for species in sorted(bases):
        entity = entities[species]
        rule = next((rules[owner] for owner in entity["ancestry"] if owner in rules), None)
        expected = actual[species]
        if rule and rule["kind"] == "cubeSize":
            source += f"        {quoted(species)}: {curves.index(rule)},\n"
            expected = rule["actual"][0]
            if entity["mob"]:
                sized[species] = rule["actual"]
        elif rule:
            resets[species] = rule["base"]
            expected = rule["actual"]
        if entity["mob"]:
            defaults[species] = expected
    source += "    ]\n    // Wolf.applyTamingSideEffects runs after saved attributes for an unowned wolf.\n"
    source += "    static let untamedBaseOverrides: [String: Double] = [\n"
    for species, base in sorted(resets.items()):
        source += f"        {quoted(species)}: {number(base)},\n"
    source += "    ]\n}\n"

    proofs = notice + "// Independent AttributeMap values and actual game load-side-effect method outputs.\n"
    proofs += "enum GeneratedHealthDefaultProofs {\n"
    proofs += f"    static let playerMaximum = {number(actual[facts['player']])}\n"
    proofs += "    static let defaultMaximums: [String: Double] = [\n"
    for species, value in sorted(defaults.items()):
        proofs += f"        {quoted(species)}: {number(value)},\n"
    proofs += "    ]\n    static let cubeMaximums: [String: [Double]] = [\n"
    for species, values in sorted(sized.items()):
        proofs += f"        {quoted(species)}: [" + ", ".join(number(value) for value in values) + "],\n"
    return source, proofs + "    ]\n}\n"


def potion_color_sources(facts, notice):
    def identifier(value):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value):
            raise ValueError("Invalid potion/effect identifier: " + value)
        return quoted(value)

    def rgb(value):
        if type(value) is not int or not 0 <= value <= 0xffffff:
            raise ValueError("Invalid potion RGB color")
        return f"0x{value:06x}"

    def effect(value, proof=False):
        name = identifier(value["id"])
        amplifier = value["amplifier"]
        if value["id"] not in facts["effects"] or type(amplifier) is not int or not 0 <= amplifier <= 255:
            raise ValueError("Unsupported potion effect ingredient")
        fields = f"id: {name}, amplifier: {amplifier}"
        if proof:
            if type(value["visible"]) is not bool:
                raise ValueError("Invalid potion proof visibility")
            fields += f", visible: {str(value['visible']).lower()}"
        return ".init(" + fields + ")"

    source = notice + "// BuiltInRegistries.MOB_EFFECT -> MobEffect.getColor.\n"
    source += "enum GeneratedPotionColors {\n    static let effects: [String: UInt32] = [\n"
    for name, color in sorted(facts["effects"].items()):
        source += f"        {identifier(name)}: {rgb(color)},\n"
    source += "    ]\n    // Potion.getEffects: visible color ingredients and their actual amplifiers.\n"
    source += "    static let recipes: [String: [PotionColorEffect]] = [\n"
    for name, values in sorted(facts["recipes"].items()):
        if len(values) > 4096:
            raise ValueError("Potion exceeds the reader's effect budget")
        source += f"        {identifier(name)}: [" + ", ".join(effect(value) for value in values) + "],\n"
    source += "    ]\n}\n"
    proofs = notice + "// Independent PotionContents.getColorOr outputs, including base/custom mixtures and visibility.\n"
    proofs += "enum GeneratedPotionColorProofs {\n"
    proofs += "    struct Effect: Sendable { let id: String; let amplifier: Int; let visible: Bool }\n"
    proofs += "    struct Case: Sendable { let potion: String?; let effects: [Effect]; let color: UInt32 }\n"
    proofs += f"    static let defaultColor: UInt32 = {rgb(facts['proofDefaultColor'])}\n"
    proofs += "    static let cases: [Case] = [\n"
    for value in facts["proofs"]:
        potion = identifier(value["potion"]) if value.get("potion") is not None else "nil"
        effects = ", ".join(effect(item, proof=True) for item in value["effects"])
        proofs += f"        .init(potion: {potion}, effects: [{effects}], color: {rgb(value['color'])}),\n"
    return source, proofs + "    ]\n}\n"


def statistic_unit_sources(facts, notice):
    source = notice + "// Stats registrations -> Stat.formatter -> StatFormatter scale.\n"
    source += "enum GeneratedStatisticUnits {\n    static let values: [String: PlayerStatistics.Unit] = [\n"
    for identifier, unit in sorted(facts["units"].items()):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Invalid statistic identifier: " + identifier)
        if unit not in ("centimeters", "ticks", "tenthsOfDamagePoint"):
            raise ValueError("Unsupported statistic unit: " + unit)
        source += f"        {quoted(identifier)}: .{unit},\n"
    source += "    ]\n}\n"
    proofs = notice + "// Independent public Stat.format output; no unit labels copied from the table.\n"
    proofs += "enum GeneratedStatisticUnitProofs {\n"
    proofs += "    static let formatted: [String: [String]] = [\n"
    for identifier, values in sorted(facts["formatted"].items()):
        examples = ", ".join(quoted(values[str(value)]) for value in (20, 100, 155))
        proofs += f"        {quoted(identifier)}: [{examples}],\n"
    return source, proofs + "    ]\n}\n"


def mob_spawn_source(facts, notice):
    weight = None if facts["requiresWeight"] else facts["defaultWeight"]
    if weight is not None and (type(weight) is not int or weight < 0):
        raise ValueError("Invalid default spawn weight")
    result = notice + "enum GeneratedMobSpawnFacts {\n"
    result += "    // Weighted.codec(MapCodec): omitted selection weight.\n"
    result += f"    static let defaultWeight: Int? = {weight if weight is not None else 'nil'}\n"
    result += "    // EnvironmentAttributes.NATURAL_MOB_SPAWNS.defaultValue -> MobSpawnSettings.\n"
    groups = []
    for category, entries in sorted(facts["defaultCandidates"].items()):
        values = []
        for entry in entries:
            if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", entry["type"]):
                raise ValueError("Invalid default spawn type")
            if type(entry["weight"]) is not int or entry["weight"] < 0:
                raise ValueError("Invalid default spawn weight")
            values.append(f".init(entityType: {quoted(entry['type'])}, weight: {entry['weight']})")
        groups.append(quoted(category) + ": [" + ", ".join(values) + "]")
    result += "    static let defaultCandidates: [String: [MobSpawnSettings.Candidate]] = [" + (", ".join(groups) or ":") + "]\n}\n"
    return result


def trading_source(facts, notice):
    result = notice + "// " + facts["source"] + ". Trade contents are never bundled.\n"
    if type(facts["minimumLevel"]) is not int:
        raise ValueError("Invalid generated minimum villager level")
    result += "enum GeneratedTradingFacts {\n"
    result += "    // VillagerData constructor normalization, checked at signed-int boundaries.\n"
    result += f"    static let minimumLevel = {facts['minimumLevel']}\n"
    result += "    static let professions: [String: [Int: String]] = [\n"
    for profession, levels in sorted(facts["professions"].items()):
        for identifier in [profession] + list(levels.values()):
            if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
                raise ValueError("Unsupported trading identifier: " + identifier)
        values = ", ".join(f"{int(level)}: {quoted(value)}" for level, value in sorted(levels.items(), key=lambda x: int(x[0])))
        result += f"        {quoted(profession)}: [" + (values or ":") + "],\n"
    return result + "    ]\n}\n"


def block_defaults_source(blocks, notice):
    if not blocks:
        raise ValueError("No registered blocks extracted")
    groups = {}
    for identifier, entry in sorted(blocks.items()):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Unsupported block identifier: " + identifier)
        properties = entry["properties"]
        for key, value in properties.items():
            if not re.fullmatch(r"[a-z0-9_]+", key) or not re.fullmatch(r"[a-z0-9_-]+", value):
                raise ValueError("Unsupported block property: " + identifier + " " + key)
        if properties:
            groups.setdefault(json.dumps(properties, sort_keys=True), []).append(identifier)
    source = notice + "// Actual code defaults, not a block inventory or a property-domain validator.\n"
    source += "enum GeneratedBlockDefaults {\n    static let values: [String: [String: String]] = {\n"
    source += "        var result = [String: [String: String]]()\n"
    source += "        func add(_ names: String, _ properties: [String: String]) {\n"
    source += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = properties }\n        }\n"
    for encoded, names in sorted(groups.items()):
        properties = "[" + ", ".join(quoted(k) + ": " + quoted(v) for k, v in json.loads(encoded).items()) + "]"
        source += "        // BuiltInRegistries.BLOCK -> Block.defaultBlockState -> BlockState.getValue / Property.getName.\n"
        source += "        add(\"\"\"\n" + textwrap.indent(textwrap.fill(" ".join(names), width=100,
            break_long_words=False, break_on_hyphens=False), "        ") + "\n"
        source += f"        \"\"\", {properties})\n"
    source += "        return result\n    }()\n}\n"
    return source


def block_tints_source(facts, notice):
    def tint(value):
        if set(value) == {"rgb"} and type(value["rgb"]) is int and 0 <= value["rgb"] <= 0xffffff:
            return f".constant(0x{value['rgb']:06x})"
        if set(value) == {"biome", "yOffset"} and value["biome"] in {"grass", "foliage", "dryFoliage", "water"}:
            if type(value["yOffset"]) is int and -2147483648 <= value["yOffset"] <= 2147483647:
                return f".biome(.{value['biome']}, yOffset: {value['yOffset']})"
        raise ValueError("Unsupported extracted block tint")

    def source(entry):
        properties = entry["properties"]
        if any(not re.fullmatch(r"[a-z0-9_]+", p) for p in properties):
            raise ValueError("Unsupported color-driving property")
        if not properties:
            if len(entry["values"]) != 1 or entry["values"][0]["values"]:
                raise ValueError("Ambiguous constant tint")
            return ".fixed(" + tint(entry["values"][0]["tint"]) + ")"
        values = []
        for value in entry["values"]:
            if len(value["values"]) != len(properties) or any(not re.fullmatch(r"[a-z0-9_-]+", v) for v in value["values"]):
                raise ValueError("Unsupported color-driving value")
            key = "[" + ", ".join(quoted(v) for v in value["values"]) + "]"
            values.append(key + ": " + tint(value["tint"]))
        return ".states(properties: [" + ", ".join(quoted(p) for p in properties) + "], values: [" + ", ".join(values) + "])"

    result = notice + "// BlockColors.createDefault / BlockTintSource.colorInWorld; not an existence catalog.\n"
    result += "enum GeneratedBlockTints {\n    enum Source: Sendable {\n"
    result += "        case fixed(BlockTint)\n        case states(properties: [String], values: [[String]: BlockTint])\n    }\n"
    result += "    // ModelBlockRenderer.computeTintColor supplies the missing-index result.\n"
    result += "    static let missingSource: BlockTint = " + tint(facts["missingSource"]) + "\n"
    result += "    static let sources: [String: [Source]] = {\n        var result = [String: [Source]]()\n"
    result += "        func add(_ names: String, _ sources: [Source]) {\n"
    result += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = sources }\n        }\n"
    groups = {}
    for identifier, entries in sorted(facts["blocks"].items()):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Unsupported block-tint identifier")
        groups.setdefault(json.dumps(entries, sort_keys=True), []).append(identifier)
    for encoded, names in sorted(groups.items()):
        entries = json.loads(encoded)
        for entry in entries: result += "        // " + entry["source"] + ".\n"
        result += "        add(\"\"\"\n" + textwrap.indent(textwrap.fill(" ".join(names), width=100,
            break_long_words=False, break_on_hyphens=False), "        ") + "\n"
        result += "        \"\"\", [" + ", ".join(source(entry) for entry in entries) + "])\n"
    result += "        return result\n    }()\n}\n"
    return result


def block_fluids_source(facts, notice):
    result = notice + "// BlockState.getFluidState and isFaceSturdy(UP); not an existence catalog.\n"
    result += "enum GeneratedBlockFluids {\n"
    for name, key, swift_type in [("fluids", "fluid", "String"), ("upperFaces", "solidUpperFace", "Bool")]:
        result += f"    static let {name}: [String: BlockStateFact<{swift_type}>] = {{\n"
        result += f"        var result = [String: BlockStateFact<{swift_type}>]()\n"
        result += f"        func add(_ names: String, _ fact: BlockStateFact<{swift_type}>) {{\n"
        result += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = fact }\n        }\n"
        groups = {}
        for identifier, entry in sorted(facts["blocks"].items()):
            if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
                raise ValueError("Unsupported block-fluid identifier")
            groups.setdefault(json.dumps(entry[key], sort_keys=True), []).append(identifier)
        for encoded, names in sorted(groups.items()):
            entry = json.loads(encoded)
            properties = entry["properties"]
            if any(not re.fullmatch(r"[a-z0-9_]+", p) for p in properties):
                raise ValueError("Unsupported fluid/face property")
            values, seen = [], set()
            for row in entry["values"]:
                state = row["values"]
                if len(state) != len(properties) or any(not re.fullmatch(r"[a-z0-9_-]+", v) for v in state):
                    raise ValueError("Unsupported fluid/face property value")
                if tuple(state) in seen: raise ValueError("Duplicate fluid/face state")
                seen.add(tuple(state))
                value = row.get("result")
                if value is None:
                    if key != "solidUpperFace": raise ValueError("Missing fluid identity")
                    continue
                if key == "fluid":
                    if not isinstance(value, str) or (value and not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", value)):
                        raise ValueError("Unsupported fluid identity")
                    source = quoted(value)
                else:
                    if type(value) is not bool: raise ValueError("Unsupported solid-face fact")
                    source = "true" if value else "false"
                values.append("[" + ", ".join(quoted(v) for v in state) + "]: " + source)
            value_source = "[" + ", ".join(values) + "]" if values else "[:]"
            property_source = "[" + ", ".join(quoted(p) for p in properties) + "]"
            result += "        add(\"\"\"\n" + textwrap.indent(textwrap.fill(" ".join(names), width=100,
                break_long_words=False, break_on_hyphens=False), "        ") + "\n"
            result += f"        \"\"\", .init(properties: {property_source}, values: {value_source}))\n"
        result += "        return result\n    }()\n"
    return result + "}\n"


def block_flags_source(facts, notice, type_name, value_name):
    result = notice + "// " + facts["source"] + ". Not a block-existence catalog.\n"
    result += f"enum {type_name} {{\n    static let values: [String: Bool] = {{\n"
    result += "        var result = [String: Bool]()\n"
    result += f"        func add(_ names: String, _ {value_name}: Bool) {{\n"
    result += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = " + value_name + " }\n        }\n"
    groups = {False: [], True: []}
    for identifier, value in sorted(facts["flags"].items()):
        if type(value) is not bool or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Unsupported block code flag")
        groups[value].append(identifier)
    for value, names in groups.items():
        if not names: continue
        result += "        add(\"\"\"\n" + textwrap.indent(textwrap.fill(" ".join(names), width=100,
            break_long_words=False, break_on_hyphens=False), "        ") + "\n"
        result += "        \"\"\", " + ("true" if value else "false") + ")\n"
    return result + "        return result\n    }()\n}\n"


def generated_sources(facts, entities):
    notice = "// Generated by Tools/GameFacts/regenerate.py. Provenance: Tools/GameFacts/source.json.\n"
    dyes = sorted(facts["dyes"], key=lambda entry: entry["id"])
    if len({entry["id"] for entry in dyes}) != len(dyes) or len({entry["name"] for entry in dyes}) != len(dyes):
        raise ValueError("Duplicate dye identities")
    cases = {}
    for dye in dyes:
        if not re.fullmatch(r"[a-z]+(?:_[a-z]+)*", dye["name"]):
            raise ValueError("Unsupported dye identifier")
        parts = dye["name"].split("_")
        cases[dye["id"]] = parts[0] + "".join(part.title() for part in parts[1:])
    dye_source = notice + "// Source: net.minecraft.world.item.DyeColor getId/getSerializedName/getTextureDiffuseColor.\n"
    dye_source += "/// The game's saved dye identities. Display names stay client-owned.\n"
    dye_source += "public enum DyeColor: String, CaseIterable, Sendable, Hashable {\n"
    dye_source += "".join(f"    case {cases[d['id']]} = {quoted(d['name'])}\n" for d in dyes)
    dye_source += "\n    /// Invalid IDs remain unavailable instead of wrapping to another color.\n"
    dye_source += "    public init?(legacyID: Int) {\n        switch legacyID {\n"
    dye_source += "".join(f"        case {d['id']}: self = .{cases[d['id']]}\n" for d in dyes)
    dye_source += "        default: return nil\n        }\n    }\n\n"
    dye_source += "    /// Extracted texture multiplier, not a presentation palette.\n"
    dye_source += "    var textureDiffuseRGB: UInt32 {\n        switch self {\n"
    dye_source += "".join(f"        case .{cases[d['id']]}: 0x{d['textureRGB']:06x}\n" for d in dyes)
    dye_source += "        }\n    }\n}\n"

    # These are save-format adapters, not value inventories. Actual IDs and enum members are
    # obtained from the client's registries/classes. Inherited classes share the same schema.
    schemas = [
        ("axolotl", "net.minecraft.world.entity.animal.axolotl.Axolotl", "Variant", "net.minecraft.world.entity.animal.axolotl.Axolotl$Variant"),
        ("parrot", "net.minecraft.world.entity.animal.parrot.Parrot", "Variant", "net.minecraft.world.entity.animal.parrot.Parrot$Variant"),
        ("llama", "net.minecraft.world.entity.animal.equine.Llama", "Variant", "net.minecraft.world.entity.animal.equine.Llama$Variant"),
        ("horse", "net.minecraft.world.entity.animal.equine.Horse", "Variant", "net.minecraft.world.entity.animal.equine.Variant"),
        ("sheep", "net.minecraft.world.entity.animal.sheep.Sheep", "Color", None),
        ("cat", "net.minecraft.world.entity.animal.feline.Cat", "CatType", None),
        ("rabbit", "net.minecraft.world.entity.animal.rabbit.Rabbit", "RabbitType", "net.minecraft.world.entity.animal.rabbit.Rabbit$Variant"),
        ("tropicalFish", "net.minecraft.world.entity.animal.fish.TropicalFish", "Variant", "net.minecraft.world.entity.animal.fish.TropicalFish$Pattern"),
        ("fox", "net.minecraft.world.entity.animal.fox.Fox", "Type", None),
        ("mooshroom", "net.minecraft.world.entity.animal.cow.MushroomCow", "Type", None),
    ]
    source = notice + "enum GeneratedMobAppearance {\n"
    source += "    struct Schema: Sendable {\n        let field: String\n        var variants: [Int: String] = [:]\n        var markings: [Int: String]? = nil\n        var bodyShapes: [Int: String]? = nil\n    }\n\n"
    found = set()
    for label, superclass, field, enum in schemas:
        if label == "cat": values = keyed_values(facts["legacyCatTypes"], prefix="")
        elif label == "sheep": values = keyed_values({str(d['id']): d['name'] for d in dyes})
        elif enum is None: values = "[:]"
        else: values = keyed_values(facts["variants"][enum])
        markings = ""
        if label == "horse":
            markings = ", markings: " + keyed_values({key: value for key, value in
                facts["variants"]["net.minecraft.world.entity.animal.equine.Markings"].items() if value != "none"})
        if label == "tropicalFish":
            markings = ", bodyShapes: " + keyed_values(facts["fishBodyShapes"], prefix="")
        value_source = enum or {"sheep": "net.minecraft.world.item.DyeColor",
            "cat": "EntityVariantFix(CatType), then DataFixers through the current release"}.get(label, "saved string, retained as-is")
        source += f"    // {superclass}.{field}; values: {value_source}.\n"
        if label == "horse": source += "    // Markings.getId/code symbols; NONE is represented by absent markings.\n"
        source += f"    private static let {label} = Schema(field: {quoted(field)}, variants: {values}{markings})\n"
    source += "\n    static let schemas: [String: Schema] = [\n"
    for identifier, entity in sorted(entities.items()):
        matching = [label for label, superclass, _, _ in schemas if superclass in entity["ancestry"]]
        if len(matching) > 1: raise ValueError("Ambiguous appearance schema: " + identifier)
        if matching:
            found.add(matching[0])
            source += f"        {quoted(identifier)}: {matching[0]}, // {entity['class']}\n"
    if found != {schema[0] for schema in schemas}: raise ValueError("Unresolved appearance classes")
    source += "    ]\n\n"
    source += "    // TropicalFish.Base.id/code symbols supply bodyShapes; Pattern.getPackedId includes the size byte.\n"
    source += "    // Panda.Gene.getSerializedName/isRecessive and NORMAL supply dominance and the normal look.\n"
    source += "    static let pandaRecessiveGenes: [String: Bool] = [\n"
    source += "".join(f"        {quoted(name)}: {str(recessive).lower()},\n"
                      for name, recessive in sorted(facts["pandaRecessiveGenes"].items()))
    source += "    ]\n"
    source += f"    static let pandaNormalVariant = {quoted(facts['pandaNormalVariant'])}\n"
    source += "}\n"
    enchantments = notice + "enum GeneratedEnchantmentEffects {\n"
    enchantments += "    enum Component: Sendable { case attributes, conditionalEffects, conditionalValues, value, sounds, sound, soundList, unit }\n"
    enchantments += "    enum Effect: Sendable { case attribute, allOf, noAttribute, unavailable }\n"
    for category, type_name in [("components", "Component"), ("effects", "Effect")]:
        enchantments += f"\n    static let {category}: [String: {type_name}] = [\n"
        for identifier, entry in sorted(facts["enchantmentEffects"][category].items()):
            if not re.fullmatch(r"[a-zA-Z]+", entry["format"]): raise ValueError("Invalid effect format")
            enchantments += f"        // {entry['source']}\n"
            enchantments += f"        {quoted(identifier)}: .{entry['format']},\n"
        enchantments += "    ]\n"
    enchantments += "}\n"
    item_facts = facts["itemModels"]
    if set(item_facts["chargeNames"]) != {"NONE", "ARROW", "ROCKET"}:
        raise ValueError("New crossbow charge format requires inspection")
    item_source = notice + "// Sources: BuiltInRegistries.ITEM, Item.components, DataComponents.BLOCK_STATE/CHARGED_PROJECTILES.\n"
    item_source += "enum GeneratedItemModelFacts {\n"
    item_source += "    struct Prototype: Sendable {\n        let components: Set<String>\n        let blockState: [String: String]\n        let charge: String\n    }\n\n"
    item_source += "    // Charge.get uses Items.FIREWORK_ROCKET; names come from CrossbowItem.ChargeType.getSerializedName.\n"
    item_source += f"    static let rocketItem = {quoted(item_facts['rocketItem'])}\n"
    for key, value in item_facts["chargeNames"].items():
        item_source += f"    static let {key.lower()}Charge = {quoted(value)}\n"
    groups = {}
    for identifier, prototype in sorted(item_facts["prototypes"].items()):
        if not re.fullmatch(r"[a-z0-9_.:/-]+", identifier):
            raise ValueError("Unsupported prototype identifier")
        groups.setdefault(json.dumps(prototype, sort_keys=True), []).append(identifier)
    item_source += "\n    static let prototypes: [String: Prototype] = {\n        var result = [String: Prototype]()\n"
    item_source += "        func add(_ names: String, _ prototype: Prototype) {\n            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = prototype }\n        }\n"
    for encoded, names in sorted(groups.items()):
        prototype = json.loads(encoded)
        components = "[" + ", ".join(quoted(name) for name in prototype["components"]) + "]"
        properties = "[" + ", ".join(quoted(k) + ": " + quoted(v) for k, v in sorted(prototype["blockState"].items())) + "]" if prototype["blockState"] else "[:]"
        item_source += "        // Item.components for these registered items; value details stay in the game/save.\n        add(\"\"\"\n"
        item_source += textwrap.indent(textwrap.fill(" ".join(names), width=100, break_long_words=False,
                                                   break_on_hyphens=False), "        ") + "\n"
        item_source += f"        \"\"\", .init(components: {components}, blockState: {properties}, charge: {quoted(prototype['charge'])}))\n"
    item_source += "        return result\n    }()\n}\n"
    egg_source = notice + "enum GeneratedSpawnEggs {\n    static let items: [String: String] = [\n"
    for entity, item in sorted(facts["spawnEggs"].items()):
        if any(not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier) for identifier in [entity, item]):
            raise ValueError("Unsupported spawn-egg identifier")
        egg_source += "        // SpawnEggItem.byId: item-registry ENTITY_DATA / TypedEntityData.type.\n"
        egg_source += f"        {quoted(entity)}: {quoted(item)},\n"
    egg_source += "    ]\n}\n"
    equipment = facts["equipment"]
    for key in ["legacySaddleItem", "attachedChestItem"]:
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", equipment[key]):
            raise ValueError("Unsupported equipment item identifier: " + equipment[key])
    if not 0 < equipment["legacySaddleCount"] <= 2147483647:
        raise ValueError("Invalid legacy saddle count")
    equipment_source = notice + "enum GeneratedEquipmentFacts {\n"
    equipment_source += "    // SaddleEquipmentSlotFix.fixEntityWithSaddleFlag supplies the entire old flag's item.\n"
    equipment_source += f"    static let legacySaddleItem = {quoted(equipment['legacySaddleItem'])}\n"
    equipment_source += f"    static let legacySaddleCount = {equipment['legacySaddleCount']}\n"
    equipment_source += "    // AbstractChestedHorse.mobInteract tests Items.CHEST before setting ChestedHorse.\n"
    equipment_source += f"    static let attachedChestItem = {quoted(equipment['attachedChestItem'])}\n}}\n"
    seeds = facts["blockModelSeeds"]
    def vector(value):
        if len(value) != 3 or any(type(n) is not int or not -2147483648 <= n <= 2147483647 for n in value):
            raise ValueError("Invalid extracted seed offset")
        return "SIMD3<Int32>(" + ", ".join(str(n) for n in value) + ")"
    seed_source = notice + "// Code-only seed behavior, not a block-existence catalog.\n"
    seed_source += "// Sources: " + ", ".join(seeds["sources"]) + ".\n"
    seed_source += "enum GeneratedBlockModelSeeds {\n"
    seed_source += "    enum Format: Sendable { case ordinary, bed, doubleBlock }\n"
    seed_source += "    static let formats: [String: Format] = {\n        var result = [String: Format]()\n"
    seed_source += "        func add(_ names: String, _ format: Format) {\n"
    seed_source += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = format }\n        }\n"
    groups = {}
    for identifier, block in sorted(seeds["blocks"].items()):
        if not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Unsupported seed-rule identifier")
        if block["format"] not in {"ordinary", "bed", "doubleBlock"}:
            raise ValueError("Unsupported seed-rule format")
        groups.setdefault((block["format"], block["seedMethod"]), []).append(identifier)
    for (format_name, seed_method), names in sorted(groups.items()):
        seed_source += f"        // {seed_method}; every registered state checked by the extractor.\n        add(\"\"\"\n"
        seed_source += textwrap.indent(textwrap.fill(" ".join(names), width=100, break_long_words=False,
            break_on_hyphens=False), "        ") + "\n"
        seed_source += f"        \"\"\", .{format_name})\n"
    seed_source += "        return result\n    }()\n"
    seed_source += f"    static let ordinaryOffset = {vector(seeds['ordinaryOffset'])}\n"
    seed_source += "    static let doubleBlockOffsets: [String: SIMD3<Int32>] = [\n"
    for value, offset in sorted(seeds["doubleBlockOffsets"].items()):
        seed_source += f"        {quoted(value)}: {vector(offset)},\n"
    seed_source += "    ]\n    static let bedOffsets: [String: [String: SIMD3<Int32>]] = [\n"
    for part, values in sorted(seeds["bedOffsets"].items()):
        seed_source += f"        {quoted(part)}: [\n"
        for facing, offset in sorted(values.items()):
            seed_source += f"            {quoted(facing)}: {vector(offset)},\n"
        seed_source += "        ],\n"
    seed_source += "    ]\n}\n"
    statistic_units, statistic_proofs = statistic_unit_sources(facts["statisticUnits"], notice)
    potion_colors, potion_proofs = potion_color_sources(facts["potionColors"], notice)
    health_defaults, health_proofs = health_default_sources(facts["healthDefaults"], entities, notice)
    light_storage, light_proofs = light_storage_sources(facts["lightStorage"], notice)
    map_colors, map_proofs = map_color_sources(facts["mapColors"], notice)
    legacy_content, legacy_content_proofs = legacy_content_sources(facts["legacyContentIDs"], notice)
    return {**creature_color_sources(facts["creatureColors"], entities, notice),
            "Sources/ChunkseeKit/DyeColor.swift": dye_source,
            "Sources/ChunkseeKit/GeneratedMobAppearance.swift": source,
            "Sources/ChunkseeKit/GeneratedEnchantmentEffects.swift": enchantments,
            "Sources/ChunkseeKit/GeneratedItemModelFacts.swift": item_source,
            "Sources/ChunkseeKit/GeneratedBlockDefaults.swift": block_defaults_source(facts["blockDefaults"], notice),
            "Sources/ChunkseeKit/GeneratedBlockModelSeeds.swift": seed_source,
            "Sources/ChunkseeKit/GeneratedBlockTints.swift": block_tints_source(facts["blockTints"], notice),
            "Sources/ChunkseeKit/GeneratedBlockFluids.swift": block_fluids_source(facts["blockFluids"], notice),
            "Sources/ChunkseeKit/GeneratedAirBlocks.swift": block_flags_source(facts["airBlocks"], notice, "GeneratedAirBlocks", "air"),
            "Sources/ChunkseeKit/GeneratedBlockEntityRenderers.swift": block_flags_source(facts["blockEntityRenderers"], notice, "GeneratedBlockEntityRenderers", "hasRenderer"),
            "Sources/ChunkseeKit/GeneratedSpecialItemModels.swift": generated_special_models(facts["specialItemModels"], notice),
            "Sources/ChunkseeKit/GeneratedSpawnEggs.swift": egg_source,
            "Sources/ChunkseeKit/GeneratedBlockItems.swift": block_items_source(facts["blockItems"], notice),
            "Sources/ChunkseeKit/GeneratedEquipmentFacts.swift": equipment_source,
            "Sources/ChunkseeKit/GeneratedTradingFacts.swift": trading_source(facts["trading"], notice),
            "Sources/ChunkseeKit/GeneratedMobSpawnFacts.swift": mob_spawn_source(facts["mobSpawns"], notice),
            "Sources/ChunkseeKit/GeneratedStatisticUnits.swift": statistic_units,
            "Tests/ChunkseeKitTests/GeneratedStatisticUnitProofs.swift": statistic_proofs,
            "Sources/ChunkseeKit/GeneratedPotionColors.swift": potion_colors,
            "Tests/ChunkseeKitTests/GeneratedPotionColorProofs.swift": potion_proofs,
            "Sources/ChunkseeKit/GeneratedHealthDefaults.swift": health_defaults,
            "Tests/ChunkseeKitTests/GeneratedHealthDefaultProofs.swift": health_proofs,
            "Sources/ChunkseeKit/GeneratedLightStorage.swift": light_storage,
            "Tests/ChunkseeKitTests/GeneratedLightStorageProofs.swift": light_proofs,
            "Sources/ChunkseeKit/GeneratedMapColors.swift": map_colors,
            "Tests/ChunkseeKitTests/GeneratedMapColorProofs.swift": map_proofs,
            "Sources/ChunkseeKit/GeneratedLegacyContentIDs.swift": legacy_content,
            "Tests/ChunkseeKitTests/GeneratedLegacyContentProofs.swift": legacy_content_proofs,
            "Sources/ChunkseeKit/GeneratedNonBlockDefinitions.swift": non_block_definitions_source(facts["nonBlockDefinitions"], notice),
            "Sources/ChunkseeKit/GeneratedPortalFacts.swift": portal_source(facts["portals"], notice),
            "Sources/ChunkseeKit/GeneratedSaveRenames.swift": save_renames_source(facts["saveRenames"], notice),
            "Sources/ChunkseeKit/GeneratedLegacyChunkFacts.swift": legacy_chunk_source(facts["legacyChunks"], notice),
            "Tests/ChunkseeKitTests/GeneratedLegacyChunkProofs.swift": legacy_chunk_proofs(facts["legacyChunks"], notice),
            "Tests/ChunkseeKitTests/GeneratedSaveRenameProofs.swift": save_rename_proofs_source(facts["saveRenames"], notice)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("minecraft", type=Path)
    parser.add_argument("java_home", type=Path)
    parser.add_argument("evidence", type=Path, help="New directory; retains every command and attempt")
    parser.add_argument("version", help="Installed stable release; snapshots do not generate tables")
    parser.add_argument("--check", action="store_true", help="Compare generated files without replacing them")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    folder = args.minecraft / "versions" / args.version
    metadata = json.loads((folder / (args.version + ".json")).read_text())
    jar = folder / (args.version + ".jar")
    client_hash = digest(jar, "sha1")
    if client_hash != metadata["downloads"]["client"]["sha1"]:
        raise ValueError("Client download hash mismatch")
    with zipfile.ZipFile(jar) as archive:
        version = json.loads(archive.read("version.json"))
    if not version["stable"]: raise ValueError("Code-fact generation requires a stable release")
    libraries = [args.minecraft / "libraries" / entry["downloads"]["artifact"]["path"]
                 for entry in metadata["libraries"] if "artifact" in entry.get("downloads", {})]
    libraries = [path.resolve() for path in libraries if path.exists()]
    classpath = ":".join(str(path) for path in [jar.resolve()] + libraries)
    tool_sources = ["Tools/GameFacts/regenerate.py", "Tools/GameFacts/ExtractGameFacts.java", "Tools/GameFacts/ExtractItemModelFacts.java",
                    "Tools/GameFacts/ExtractBlockDefaults.java", "Tools/GameFacts/ExtractSpawnEggs.java", "Tools/GameFacts/ExtractBlockItems.java", "Tools/GameFacts/ExtractEquipmentFacts.java",
                    "Tools/GameFacts/ExtractBlockModelSeeds.java", "Tools/GameFacts/ExtractTradingFacts.java", "Tools/GameFacts/ExtractMobSpawnFacts.java", "Tools/GameFacts/ExtractStatisticUnits.java", "Tools/GameFacts/ExtractPotionColors.java", "Tools/GameFacts/ExtractHealthDefaults.java", "Tools/GameFacts/ExtractLightStorage.java", "Tools/GameFacts/ExtractMapColors.java", "Tools/GameFacts/ExtractLegacyContentIDs.java", "Tools/GameFacts/ExtractBlockDefinitionFacts.java", "Tools/GameFacts/ExtractPortalFacts.java",
                    "Tools/GameFacts/ExtractBlockTints.java", "Tools/GameFacts/ExtractBlockFluids.java", "Tools/GameFacts/ExtractAirBlocks.java", "Tools/GameFacts/ExtractBlockEntityRenderers.java", "Tools/GameFacts/ExtractSpecialItemModels.java", "Tools/GameFacts/special_item_models.py",
                    "Tools/GameFacts/ExtractEnchantmentEffects.java", "Tools/GameFacts/ExtractSaveRenames.java", "Tools/GameFacts/ExtractCreatureColors.java", "Tools/GameFacts/ExtractNumericItemIds.java", "Tools/GameFacts/ExtractEntityRenames.java", "Tools/GameFacts/ExtractEffectRenames.java", "Tools/GameFacts/ExtractProgressRenames.java", "Tools/GameFacts/ExtractLegacyChunkFacts.java", "Tools/EntityTypes/ExtractEntityTypes.java"]
    provenance = {"minecraft": version, "clientSHA1": client_hash,
                  "toolSHA256": {path: digest(root / path) for path in tool_sources},
                  "categories": ["dyes", "mob_appearance", "creature_color_sources", "enchantment_effect_formats", "item_model_prototypes", "block_default_properties", "block_model_seeds", "block_tints", "block_fluid_states", "air_flags", "block_entity_renderer_registrations", "special_item_models", "spawn_egg_relationships", "block_item_relationships", "equipment_attachments", "profession_trade_sets", "natural_spawn_defaults", "statistic_units", "potion_color_defaults", "health_defaults", "light_storage_defaults", "map_colors", "legacy_content_ids", "non_block_definitions", "portal_rules", "save_identifier_renames", "legacy_chunk_formats"]}
    (evidence / "inputs.json").write_text(json.dumps({**provenance,
        "librariesSHA256": {str(path): digest(path) for path in libraries}}, indent=2) + "\n")
    commands = [
        [str(args.java_home / "bin/javac"), "-cp", classpath, "-d", str(evidence)]
            + [str(root / path) for path in tool_sources if path.endswith(".java")],
        [str(args.java_home / "bin/java"), "-Djava.awt.headless=true", "-cp", str(evidence) + ":" + classpath,
         "ExtractGameFacts", str(evidence / "facts.raw.json"), str(evidence / "entity-types.raw.json"), str(version["world_version"])],
    ]
    (evidence / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    for index, command in enumerate(commands):
        with (evidence / f"{index}.log").open("w") as output:
            result = subprocess.run(command, cwd=evidence, stdout=output, stderr=subprocess.STDOUT, timeout=180)
        if result.returncode: raise RuntimeError(f"Extraction failed; see {evidence / f'{index}.log'}")
    extracted = {name: canonical_extraction(evidence / name.replace(".json", ".raw.json"), evidence / name)
                 for name in ["facts.json", "entity-types.json"]}
    sources = generated_sources(extracted["facts.json"], extracted["entity-types.json"])
    provenance["extractedSHA256"] = {name: digest(evidence / name) for name in ["facts.json", "entity-types.json"]}
    sources["Tools/GameFacts/source.json"] = json.dumps(provenance, indent=2, sort_keys=True) + "\n"
    for relative, content in sources.items():
        (evidence / Path(relative).name).write_text(content)
    if args.check:
        changed = [path for path, content in sources.items() if not (root / path).exists() or (root / path).read_text() != content]
        if changed: raise RuntimeError("Generated files differ: " + ", ".join(changed))
    else:
        for relative, content in sources.items(): (root / relative).write_text(content)
    print(f"{version['name']}: generated {len(sources)} files; client SHA-1 {client_hash}")


if __name__ == "__main__":
    main()
