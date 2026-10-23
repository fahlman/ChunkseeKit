/// One budget spans an asset definition and every model reached through its selected branches.
struct AssetReadBudget {
    private var remainingBytes = ZipResources.maximumResourceSize
    private var remainingElements = 4096
    enum Exceeded: Error { case limit }

    mutating func consume(bytes: Int) throws {
        guard bytes <= remainingBytes else { throw Exceeded.limit }
        remainingBytes -= bytes
    }

    mutating func consume(elements: Int) throws {
        guard elements <= remainingElements else { throw Exceeded.limit }
        remainingElements -= elements
    }
}
