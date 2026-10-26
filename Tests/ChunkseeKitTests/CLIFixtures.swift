import Foundation
import ChunkseeKitTestSupport

extension Fixtures {
    static func runCLI(_ world: URL, command: String? = nil, arguments: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process(), pipe = Pipe()
        // SwiftPM places the tool beside this test bundle, including Release and --scratch-path builds.
        process.executableURL = Bundle(for: CLITestBundle.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("chunksee")
        process.arguments = [world.path] + (command.map { [$0] } ?? []) + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}

private final class CLITestBundle: NSObject {}
