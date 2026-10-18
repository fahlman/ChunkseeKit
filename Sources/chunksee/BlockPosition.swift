/// A containing block, or nil when an edited save has an unrepresentable position.
func blockPosition(x: Double, y: Double, z: Double) -> (x: Int, y: Int, z: Int)? {
    guard let x = Int(exactly: x.rounded(.down)),
          let y = Int(exactly: y.rounded(.down)),
          let z = Int(exactly: z.rounded(.down)) else { return nil }
    return (x, y, z)
}
