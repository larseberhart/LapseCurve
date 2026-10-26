import Foundation
import LapseCurveDomain

/// Failure while preparing a metadata update for an intermediate frame.
public enum XMPWriteError: Error, Equatable, LocalizedError, Sendable {
    /// Keyframe source metadata is immutable.
    case keyframeMetadataIsImmutable
    /// Conflicting frame metadata prevents a safe update.
    case conflictingFrameMetadata
    /// No writable definition exists for the requested parameter.
    case parameterNotApproved(DevelopmentParameter)
    /// The proposed scalar is invalid or outside its verified range.
    case invalidValue(DevelopmentParameter)
    /// The source packet does not contain the mapped property.
    case propertyMissing(DevelopmentParameter)
    /// Multiple properties match one mapped field.
    case duplicateProperty(DevelopmentParameter)
    /// The mapped property uses a non-XMP development namespace.
    case unsupportedNamespace(DevelopmentParameter)
    /// The mapped property is a structured value rather than a scalar.
    case structuredProperty(DevelopmentParameter)

    /// Human-readable explanation of the metadata update failure.
    public var errorDescription: String? {
        switch self {
        case .keyframeMetadataIsImmutable:
            "Keyframe metadata is read-only and cannot be updated."
        case .conflictingFrameMetadata:
            "Conflicting frame metadata must be reloaded before an update."
        case .parameterNotApproved(let parameter):
            "No writable mapping is enabled for \(parameter.rawValue)."
        case .invalidValue(let parameter):
            "Proposed value for \(parameter.rawValue) is non-finite or outside its configured range."
        case .propertyMissing(let parameter):
            "The source packet does not contain a scalar property for \(parameter.rawValue)."
        case .duplicateProperty(let parameter):
            "The source packet contains ambiguous properties for \(parameter.rawValue)."
        case .unsupportedNamespace(let parameter):
            "The mapping for \(parameter.rawValue) is not in the Camera Raw settings namespace."
        case .structuredProperty(let parameter):
            "The property for \(parameter.rawValue) is structured and cannot be replaced as a scalar."
        }
    }
}