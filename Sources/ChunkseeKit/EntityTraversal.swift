/// The saved entity tree: each vehicle precedes its passengers, in their saved order.
enum EntityTraversal {
    static func flatten(_ roots: [NBT]) -> [NBT] {
        var pending = Array(roots.reversed())
        var entities: [NBT] = []
        // NBT reading already bounds nesting. An explicit stack also avoids recursive calls
        // for callers constructing NBT values directly, without dropping readable descendants.
        while let entity = pending.popLast() {
            entities.append(entity)
            if let passengers = entity["Passengers"]?.list {
                pending.append(contentsOf: passengers.reversed())
            }
        }
        return entities
    }
}
