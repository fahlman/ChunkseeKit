#!/usr/bin/env python3
"""Prepare one frozen release comparison; never modify installed game files."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def condition(rule, properties):
    if "OR" in rule:
        return any(condition(term, properties) for term in rule["OR"])
    if "AND" in rule:
        return all(condition(term, properties) for term in rule["AND"])
    # Vanilla inputs for this investigation use positive terms. Fail if a new
    # grammar appears, instead of quietly assigning an unverified interpretation.
    for key, values in rule.items():
        values = str(values).lower().split("|")
        if any(value.startswith("!") for value in values):
            raise ValueError("Negated condition needs a release-specific oracle")
        if properties[key] not in values:
            return False
    return True


def selected(root, properties):
    matched = []
    for key, value in root.get("variants", {}).items():
        terms = dict(term.split("=", 1) for term in key.split(",")) if key else {}
        if all(properties[k] == v for k, v in terms.items()):
            matched.append(value)
    if len(matched) > 1:
        raise ValueError("Overlapping variant selectors")
    if matched:
        return matched
    return [part["apply"] for part in root.get("multipart", [])
            if "when" not in part or condition(part["when"], properties)]


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("minecraft", type=Path)
    parser.add_argument("java_home", type=Path)
    parser.add_argument("evidence", type=Path, help="New directory for this attempt")
    parser.add_argument("version")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    folder = args.minecraft / "versions" / args.version
    jar = folder / (args.version + ".jar")
    metadata_path = folder / (args.version + ".json")
    metadata = json.loads(metadata_path.read_text())
    client_hash = digest(jar, "sha1")
    if client_hash != metadata["downloads"]["client"]["sha1"]:
        raise ValueError("Client download hash mismatch")
    libraries = [args.minecraft / "libraries" / entry["downloads"]["artifact"]["path"]
                 for entry in metadata["libraries"] if "artifact" in entry.get("downloads", {})]
    libraries = [path.resolve() for path in libraries if path.exists()]
    classpath = ":".join(str(path) for path in [jar.resolve()] + libraries)
    source = Path(__file__).with_name("ExtractBlockDefaults.java").resolve()
    provenance = {"client": str(jar), "clientSHA1": client_hash,
                  "metadataSHA256": digest(metadata_path),
                  "toolsSHA256": {path.name: digest(path) for path in [source, Path(__file__)]},
                  "librariesSHA256": {str(path): digest(path) for path in libraries}, "commands": []}
    commands = [[str(args.java_home / "bin/javac"), "-cp", classpath, "-d", str(evidence), str(source)],
                [str(args.java_home / "bin/java"), "-Djava.awt.headless=true", "-cp", str(evidence) + ":" + classpath,
                 "ExtractBlockDefaults", str(evidence / "defaults.json")]]
    for index, command in enumerate(commands):
        with (evidence / f"{index}.log").open("w") as output:
            result = subprocess.run(command, cwd=evidence, stdout=output, stderr=subprocess.STDOUT, timeout=180)
        provenance["commands"].append({"command": command, "exit": result.returncode})
        (evidence / "inputs.json").write_text(json.dumps(provenance, indent=2) + "\n")
        if result.returncode:
            raise RuntimeError(f"Extraction failed; see {evidence / f'{index}.log'}")
    defaults = json.loads((evidence / "defaults.json").read_text())
    cases = []
    with zipfile.ZipFile(jar) as archive, zipfile.ZipFile(evidence / "item-blocks.zip", "w", zipfile.ZIP_DEFLATED) as overlay:
        version = json.loads(archive.read("version.json"))
        if not version["stable"]:
            raise ValueError("Expected a stable release")
        provenance["version"] = version
        # The isolated fixture supplies item geometry as unrotated block geometry.
        # Original model/texture bytes are copied unchanged; inventory GUI transforms
        # deliberately do not enter the map projection.
        for name in archive.namelist():
            if name == "version.json" or name.startswith("assets/") and ("/models/" in name or "/textures/" in name):
                overlay.writestr(name, archive.read(name))
        for identifier, properties in defaults.items():
            if not properties:
                continue
            namespace, path = identifier.split(":", 1)
            block_path = f"assets/{namespace}/blockstates/{path}.json"
            item_path = f"assets/{namespace}/items/{path}.json"
            block = json.loads(archive.read(block_path))
            parts = selected(block, properties)
            models = [entry for part in parts for entry in (part if isinstance(part, list) else [part])]
            item = json.loads(archive.read(item_path))["model"] if item_path in archive.namelist() else None
            if item is None:
                category = "no_item"
            elif item.get("type") != "minecraft:model":
                category = "non_plain_item"
            elif models and all(entry["model"] == item["model"] for entry in models):
                category = "same_rotated" if any(entry.get(axis, 0) % 360 for entry in models for axis in ["x", "y", "z"]) else "same"
            else:
                category = "different"
            variants = list(block.get("variants", {}).values())
            independent = bool(variants) and len({canonical(v) for v in variants}) == 1 and "multipart" not in block
            if not variants:
                independent = "multipart" in block and all("when" not in p for p in block["multipart"])
            entry = {"id": identifier, "properties": properties, "category": category,
                     "selected": parts, "item": item, "stateIndependent": independent}
            if item and item.get("type") == "minecraft:model":
                entry["candidateID"] = "probe:" + namespace + "/" + path
                overlay.writestr(f"assets/probe/blockstates/{namespace}/{path}.json",
                                 json.dumps({"variants": {"": {"model": item["model"]}}}))
            cases.append(entry)
    (evidence / "cases.json").write_text(json.dumps(cases, indent=2) + "\n")
    provenance["outputsSHA256"] = {name: digest(evidence / name) for name in ["defaults.json", "cases.json", "item-blocks.zip"]}
    provenance["categoryCounts"] = dict(collections.Counter(case["category"] for case in cases))
    provenance["stateIndependent"] = sum(case["stateIndependent"] for case in cases)
    if digest(jar, "sha1") != client_hash:
        raise RuntimeError("Installed client changed during comparison preparation")
    (evidence / "inputs.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps({"version": args.version, "counts": provenance["categoryCounts"], "stateIndependent": provenance["stateIndependent"]}))


if __name__ == "__main__":
    main()
