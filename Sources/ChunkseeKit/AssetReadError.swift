/// Why a selected game resource could not be resolved. Only confirmed absent resources
/// are missing; an unreadable archive or a limitation of this reader is not evidence of absence.
public enum AssetReadError: Error, Sendable, Equatable {
    /// A model, item definition or blockstate definition is absent at this archive path.
    case missingModel(String)
    /// A plain texture PNG is absent at this archive path. A generated atlas sprite may still
    /// resolve through palettedTexture; this is not a verdict on the final rendered picture.
    case missingTexture(String)
    /// The selected format or transform is not supported by this reader.
    case unsupportedFeature
    /// The selected branch needs a saved/default fact that is not available.
    case incompleteState
    /// Malformed input, an invalid identifier or contradictory/cyclic definitions.
    case invalidData
    /// The archive changed, an entry could not be read/validated, or required atlas context is absent.
    case unavailableResource(String)
    /// The bounded reader's byte, element, node or reference allowance was exhausted.
    case limitExceeded
    /// A helper could not resolve the resource without enough evidence for a narrower reason.
    case unresolved

    static func resolving<T>(_ operation: () throws -> T) throws(AssetReadError) -> T {
        do { return try operation() }
        catch let error as AssetReadError { throw error }
        catch is DecodingError { throw .invalidData }
        catch is AssetReadBudget.Exceeded { throw .limitExceeded }
        catch { throw .unresolved }
    }
}
