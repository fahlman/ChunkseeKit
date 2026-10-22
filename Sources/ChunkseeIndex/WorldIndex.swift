/// A world snapshot keyed by dimension ID. The payload can be the shared DimensionIndex or a
/// client's native projection of it. File access, scheduling and publication belong to clients.
public struct WorldIndex<Dimension: Sendable>: Sendable {
    public struct Placed<Value: Sendable>: Sendable {
        public var dimension: String
        public var value: Value

        public init(dimension: String, value: Value) {
            self.dimension = dimension
            self.value = value
        }
    }

    public var dimensions: [String: Dimension]

    public init(dimensions: [String: Dimension] = [:]) {
        self.dimensions = dimensions
    }

    /// One kind of record across the catalog, retaining its dimension even when another
    /// dimension contains an identical record. Member order is preserved; dimension order
    /// is unspecified. Clients apply their result ordering after matching and presentation.
    public func all<Value: Sendable>(_ part: KeyPath<Dimension, [Value]>) -> [Placed<Value>] {
        dimensions.flatMap { id, index in
            index[keyPath: part].map { Placed(dimension: id, value: $0) }
        }
    }
}
