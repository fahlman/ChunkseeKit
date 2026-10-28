/// A reader's complete persistence contract, independent of package and Minecraft versions.
/// Keep the whole value in a cache key. The reader revision covers handwritten interpretation;
/// the release tool supplies generated-fact digests, and dependencies retain their own owners.
/// Codable preserves these values across launches; Swift's hashValue is never a disk identity.
public struct InterpretationVersion: Sendable, Hashable, Codable {
    public let domain: String
    public let revision: Int
    public let generatedFacts: String
    public let dependencies: [InterpretationVersion]

    init(domain: String, revision: Int, generatedFacts: String,
         dependencies: [InterpretationVersion]) {
        self.domain = domain
        self.revision = revision
        self.generatedFacts = generatedFacts
        self.dependencies = dependencies
    }
}
