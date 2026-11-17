import Foundation
import ChunkseeKit

/// Keep readable results while collecting discovery failures for the command's final error.
struct RegionDiscovery {
    private var unavailable: [URL] = []

    mutating func files(in dimension: ChunkseeKit.Dimension, folder: ChunkseeKit.Dimension.Folder = .terrain) -> [(x: Int, z: Int, url: URL)]? {
        let listing = dimension.readRegionFiles(folder)
        guard listing.isComplete else {
            unavailable.append(dimension.directory(folder))
            return nil
        }
        return listing.files
    }

    func finish() throws {
        if !unavailable.isEmpty { throw Failure(folders: unavailable) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let folders: [URL]

        var description: String {
            folders.map { "could not list region folder: \($0.path)" }.joined(separator: "\n")
        }
    }
}
