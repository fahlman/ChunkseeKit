#!/usr/bin/env python3
"""Collect official entity classes and mob save-code evidence; no product tables are generated."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("minecraft", type=Path)
    parser.add_argument("java_home", type=Path)
    parser.add_argument("evidence", type=Path, help="New directory for commands, raw facts and logs")
    parser.add_argument("versions", nargs="+", help="Installed versions to check; no built-in version list")
    args = parser.parse_args()
    args.evidence = args.evidence.resolve()
    args.evidence.mkdir(parents=True, exist_ok=False)
    here = Path(__file__).resolve().parent
    for version in args.versions:
        folder = args.minecraft / "versions" / version
        metadata = json.loads((folder / (version + ".json")).read_text())
        jar = folder / (version + ".jar")
        sha1 = hashlib.sha1(jar.read_bytes()).hexdigest()
        if sha1 != metadata["downloads"]["client"]["sha1"]:
            raise ValueError(f"Client hash mismatch: {version}")
        with zipfile.ZipFile(jar) as archive:
            game_version = json.loads(archive.read("version.json"))
        libraries = [args.minecraft / "libraries" / library["downloads"]["artifact"]["path"]
                     for library in metadata["libraries"] if "artifact" in library.get("downloads", {})]
        classpath = ":".join(str(p.resolve()) for p in [jar] + libraries if p.exists())
        output = args.evidence / version
        output.mkdir()
        commands = [
            [str(args.java_home / "bin/javac"), "-cp", classpath, "-d", str(output),
             str(here / "ExtractEntityTypes.java")],
            [str(args.java_home / "bin/java"), "-Djava.awt.headless=true", "-cp",
             str(output) + ":" + classpath, "ExtractEntityTypes", str(output / "entity-types.json")],
            [str(args.java_home / "bin/javap"), "-c", "-p", "-classpath", classpath,
             "net.minecraft.world.entity.Mob"],
        ]
        (output / "commands.json").write_text(json.dumps({"sha1": sha1, "commands": commands}, indent=2) + "\n")
        for index, command in enumerate(commands):
            result = subprocess.run(command, cwd=output, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (output / f"{index}.log").write_text(result.stdout)
            if result.returncode:
                raise RuntimeError(f"Source check failed; see {output / f'{index}.log'}")
        entries = json.loads((output / "entity-types.json").read_text())
        print(f"{version} / {game_version['world_version']}: {len(entries)} types, "
              f"{sum(entry['mob'] for entry in entries.values())} mobs; client SHA-1 {sha1}")


if __name__ == "__main__":
    main()
