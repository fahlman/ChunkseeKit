import Foundation
import ChunkseeKit

/// A subcommand: `chunksee <world> <name> <arguments>`.
struct Command {
    var name: String
    var arguments = ""
    var summary: String
    var run: (World, Arguments) async throws -> Void
}

/// The words after the command name, with the ways commands read them.
struct Arguments {
    let words: [String]

    /// The dimension named at `index`, or the Overworld when there's none.
    func dimension(_ index: Int, in world: World) -> ChunkseeKit.Dimension {
        let id = words.count > index ? words[index] : "minecraft:overworld"
        guard let dimension = world.dimension(id) else { fail("no such dimension: \(id)") }
        return dimension
    }

    /// The dimension named at `index`, or every dimension when there's none.
    func dimensions(_ index: Int, in world: World) -> [ChunkseeKit.Dimension] {
        words.count > index ? [dimension(index, in: world)] : world.dimensions()
    }

    func int(_ index: Int) -> Int {
        guard words.count > index, let value = Int(words[index]) else { fail(usage) }
        return value
    }

    func text(_ index: Int) -> String {
        guard words.count > index else { fail(usage) }
        return words[index]
    }
}

let commands: [Command] = [
    Command(name: "summary", arguments: "[game.jar]", summary: "world summary using the supplied game data", run: summaryAssetsCommand),
    Command(name: "chunk", arguments: "<cx> <cz> [dimension]", summary: "chunk summary", run: chunkCommand),
    Command(name: "block", arguments: "<x> <y> <z> [dimension]", summary: "block and biome at a position", run: blockCommand),
    Command(name: "scan", arguments: "[dimension]", summary: "decode every chunk and report errors", run: scanCommand),
    Command(name: "time", arguments: "[dimension]", summary: "chunks where players spent the most time", run: timeCommand),
    Command(name: "creatures", arguments: "[dimension]", summary: "villagers, named and owned creatures, and shoulder pets; counts by kind", run: creaturesCommand),
    Command(name: "maps", summary: "maps made in the game, with where they cover", run: mapsCommand),
    Command(name: "rules", summary: "game rules", run: rulesCommand),
    Command(name: "players", summary: "players' positions, deaths, respawn points and status", run: playersCommand),
    Command(name: "structures", arguments: "[dimension]", summary: "structures found in generated chunks, by kind", run: structuresCommand),
    Command(name: "poi", arguments: "[dimension]", summary: "points of interest (beds, workstations, portals…) by type", run: poiCommand),
    Command(name: "portals", summary: "Nether portals and where each one leads", run: portalsCommand),
    Command(name: "find", arguments: "<text> [dimension]", summary: "containers and players holding matching items", run: findCommand),
    Command(name: "text", arguments: "<text> [dimension]", summary: "signs and books containing the text", run: textCommand),
]

let usage = "usage:\n" + ([("", "world summary")] + commands.map { ("\($0.name) \($0.arguments)", $0.summary) })
    .map { "  " + "chunksee <world> \($0.0)".padding(toLength: 50, withPad: " ", startingAt: 0) + $0.1 }
    .joined(separator: "\n")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Orders counted things most first, ties by name, so output is the same on every run.
func byCount<Key: Comparable>(_ a: (key: Key, value: Int), _ b: (key: Key, value: Int)) -> Bool {
    a.value != b.value ? a.value > b.value : a.key < b.key
}

let words = Array(CommandLine.arguments.dropFirst())
guard let path = words.first else { fail(usage) }
do {
    let world = try World(contentsOf: URL(fileURLWithPath: path))
    let arguments = Arguments(words: Array(words.dropFirst()))
    if let name = arguments.words.first {
        guard let command = commands.first(where: { $0.name == name }) else { fail(usage) }
        try await command.run(world, arguments)
    } else {
        summaryCommand(world)
    }
} catch {
    fail("error: \(error)")
}
