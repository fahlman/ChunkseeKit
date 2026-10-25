import ChunkseeKit
import Foundation

/// Compare public decoding with every official registry entry, not just the generated mob list.
@main struct VerifyEntityTypes {
    struct Entry: Decodable { let mob: Bool }

    @MainActor static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else {
            fatalError("Expected pairs of data-version (or nil) and entity-types.json")
        }
        var checked = 0
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let versionText = arguments[index]
            let version = Int(versionText)
            precondition(version != nil || versionText == "nil")
            let entries = try JSONDecoder().decode([String: Entry].self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])))
            for (id, expected) in entries {
                for healthPresent in [false, true] {
                    var fields: [String: NBT] = [
                        "id": .string(id), "Pos": .list([.double(1), .double(64), .double(2)]),
                        "Owner": .intArray([1, 2, 3, 4]), "CustomName": .string("Registry check"),
                        "CanPickUpLoot": .byte(1), "PersistenceRequired": .byte(1), "LeftHanded": .byte(0),
                    ]
                    if healthPresent { fields["Health"] = .float(5) }
                    let creature = Creature(.compound(fields), dataVersion: version)
                    precondition((creature != nil) == expected.mob, "\(versionText): \(id), health \(healthPresent)")
                    if let creature {
                        precondition(creature.id == id)
                        precondition(creature.isRecognizedType == true)
                        precondition(creature.health == (healthPresent ? 5 : nil))
                    }
                    checked += 1
                }
            }
            print("MATCHED \(versionText): \(entries.count) registered types")
        }
        print("PASS \(checked) public creature decodes")
    }
}
