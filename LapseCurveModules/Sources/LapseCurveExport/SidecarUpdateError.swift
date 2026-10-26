import Foundation
import LapseCurveDomain

/// Failure preventing an unsafe sidecar update.
public enum SidecarUpdateError: Error, Equatable, LocalizedError, Sendable {
    case explicitApprovalRequired
    case keyframeIsImmutable(FrameID)
    case sidecarMissing(URL)
    case invalidSidecarURL(URL)
    case sourceChanged(FrameID)
    case writtenValueMismatch(DevelopmentParameter)
    case fileOperationFailed(String)

    /// Human-readable explanation for an update failure.
    public var errorDescription: String? {
        switch self {
        case .explicitApprovalRequired:
            "Updating an existing XMP sidecar requires explicit user approval."
        case .keyframeIsImmutable(let frameID):
            "Keyframe metadata for frame \(frameID.rawValue) is immutable."
        case .sidecarMissing:
            "The planned XMP sidecar no longer exists; no sidecar was created."
        case .invalidSidecarURL:
            "The planned destination is not a local XMP sidecar URL."
        case .sourceChanged:
            "The source sidecar changed after preflight; reload and recalculate before updating."
        case .writtenValueMismatch(let parameter):
            "The written sidecar could not be verified for \(parameter.rawValue)."
        case .fileOperationFailed(let message):
            "The sidecar update failed: \(message)"
        }
    }
}