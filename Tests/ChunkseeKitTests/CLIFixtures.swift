import Foundation
import ChunkseeKitTestSupport

extension Fixtures {
    static func runCLI(_ world: URL, command: String? = nil, arguments: [String] = []) throws -> (status: Int32, output: String, standardError: String) {
        let process = Process(), pipe = Pipe()
        let capture = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: capture) }
        let errorURL = capture.appendingPathComponent("stderr")
        try Data().write(to: errorURL)
        let errorFile = try FileHandle(forWritingTo: errorURL)
        defer { try? errorFile.close() }
        // SwiftPM places the tool beside this test bundle, including Release and --scratch-path builds.
        process.executableURL = Bundle(for: CLITestBundle.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("chunksee")
        process.arguments = [world.path] + (command.map { [$0] } ?? []) + arguments
        process.standardOutput = pipe
        // A file keeps a full error stream from blocking while stdout is drained.
        process.standardError = errorFile
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let error = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
        return (process.terminationStatus, String(decoding: output, as: UTF8.self) + error, error)
    }
}

private final class CLITestBundle: NSObject {}
