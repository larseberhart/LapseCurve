import Foundation

/// Failure loading or safely storing a LapseCurve project document.
public enum ProjectRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidFileURL
    case parentDirectoryMissing
    case destinationNotRegularFile
    case decodingFailed
    case encodingFailed
    case unsupportedSchemaVersion(Int)
    case recoverySnapshotMissing
    case fileOperationFailed

    /// Human-readable error text without leaking source paths.
    public var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            "Project documents must use a local file URL."
        case .parentDirectoryMissing:
            "The parent directory for the project document does not exist."
        case .destinationNotRegularFile:
            "The project destination is not a regular file."
        case .decodingFailed:
            "The project document could not be decoded."
        case .encodingFailed:
            "The project document could not be encoded."
        case .unsupportedSchemaVersion(let version):
            "Project schema version \(version) is not supported."
        case .recoverySnapshotMissing:
            "No recovery snapshot is available for this project."
        case .fileOperationFailed:
            "The project document could not be safely read or written."
        }
    }
}