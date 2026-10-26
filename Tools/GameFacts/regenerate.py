#!/usr/bin/env python3
"""Regenerate code-only game facts from an installed, hash-verified official release."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import textwrap
import zipfile
from special_item_models import generated_special_models


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def keyed_values(values, prefix="minecraft:"):
    entries = []
    for key, value in sorted(values.items(), key=lambda item: int(item[0])):
        if not re.fullmatch(r"[a-z0-9_.:/-]+", value):
            raise ValueError("Unsupported appearance identifier: " + value)
        entries.append(f"{int(key)}: {quoted(prefix + value)}")
    if not entries:
        raise ValueError("An extracted mapping was empty")
    return "[" + ", ".join(entries) + "]"


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


def air_blocks_source(facts, notice):
    result = notice + "// " + facts["source"] + ". Not a block-existence catalog.\n"
    result += "enum GeneratedAirBlocks {\n    static let values: [String: Bool] = {\n"
    result += "        var result = [String: Bool]()\n"
    result += "        func add(_ names: String, _ air: Bool) {\n"
    result += "            for name in names.split(whereSeparator: \\.isWhitespace) { result[String(name)] = air }\n        }\n"
    groups = {False: [], True: []}
    for identifier, value in sorted(facts["flags"].items()):
        if type(value) is not bool or not re.fullmatch(r"[a-z0-9_.-]+:[a-z0-9_./-]+", identifier):
            raise ValueError("Unsupported air flag")
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
    return {"Sources/ChunkseeKit/DyeColor.swift": dye_source,
            "Sources/ChunkseeKit/GeneratedMobAppearance.swift": source,
            "Sources/ChunkseeKit/GeneratedEnchantmentEffects.swift": enchantments,
            "Sources/ChunkseeKit/GeneratedItemModelFacts.swift": item_source,
            "Sources/ChunkseeKit/GeneratedBlockDefaults.swift": block_defaults_source(facts["blockDefaults"], notice),
            "Sources/ChunkseeKit/GeneratedBlockModelSeeds.swift": seed_source,
            "Sources/ChunkseeKit/GeneratedBlockTints.swift": block_tints_source(facts["blockTints"], notice),
            "Sources/ChunkseeKit/GeneratedBlockFluids.swift": block_fluids_source(facts["blockFluids"], notice),
            "Sources/ChunkseeKit/GeneratedAirBlocks.swift": air_blocks_source(facts["airBlocks"], notice),
            "Sources/ChunkseeKit/GeneratedSpecialItemModels.swift": generated_special_models(facts["specialItemModels"], notice),
            "Sources/ChunkseeKit/GeneratedSpawnEggs.swift": egg_source,
            "Sources/ChunkseeKit/GeneratedEquipmentFacts.swift": equipment_source,
            "Sources/ChunkseeKit/GeneratedTradingFacts.swift": trading_source(facts["trading"], notice)}


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
                    "Tools/GameFacts/ExtractBlockDefaults.java", "Tools/GameFacts/ExtractSpawnEggs.java", "Tools/GameFacts/ExtractEquipmentFacts.java",
                    "Tools/GameFacts/ExtractBlockModelSeeds.java", "Tools/GameFacts/ExtractTradingFacts.java",
                    "Tools/GameFacts/ExtractBlockTints.java", "Tools/GameFacts/ExtractBlockFluids.java", "Tools/GameFacts/ExtractAirBlocks.java", "Tools/GameFacts/ExtractSpecialItemModels.java", "Tools/GameFacts/special_item_models.py",
                    "Tools/GameFacts/ExtractEnchantmentEffects.java", "Tools/EntityTypes/ExtractEntityTypes.java"]
    provenance = {"minecraft": version, "clientSHA1": client_hash,
                  "toolSHA256": {path: digest(root / path) for path in tool_sources},
                  "categories": ["dyes", "mob_appearance", "enchantment_effect_formats", "item_model_prototypes", "block_default_properties", "block_model_seeds", "block_tints", "block_fluid_states", "air_flags", "special_item_models", "spawn_egg_relationships", "equipment_attachments", "profession_trade_sets"]}
    (evidence / "inputs.json").write_text(json.dumps({**provenance,
        "librariesSHA256": {str(path): digest(path) for path in libraries}}, indent=2) + "\n")
    commands = [
        [str(args.java_home / "bin/javac"), "-cp", classpath, "-d", str(evidence)]
            + [str(root / path) for path in tool_sources if path.endswith(".java")],
        [str(args.java_home / "bin/java"), "-Djava.awt.headless=true", "-cp", str(evidence) + ":" + classpath,
         "ExtractGameFacts", str(evidence / "facts.json"), str(evidence / "entity-types.json"), str(version["world_version"])],
    ]
    (evidence / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    for index, command in enumerate(commands):
        with (evidence / f"{index}.log").open("w") as output:
            result = subprocess.run(command, cwd=evidence, stdout=output, stderr=subprocess.STDOUT, timeout=180)
        if result.returncode: raise RuntimeError(f"Extraction failed; see {evidence / f'{index}.log'}")
    sources = generated_sources(json.loads((evidence / "facts.json").read_text()),
                                json.loads((evidence / "entity-types.json").read_text()))
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
