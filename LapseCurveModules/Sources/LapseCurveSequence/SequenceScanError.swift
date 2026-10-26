import Foundation

/// Failure preventing a sequence directory scan from completing.
public enum SequenceScanError: Error, Equatable, LocalizedError, Sendable {
    /// The URL does not identify a file-system directory.
    case notDirectory
    /// The directory could not be enumerated.
    case unreadableDirectory

    /// Human-readable explanation of the scan failure.
    public var errorDescription: String? {
        switch self {
        case .notDirectory:
            "The selected source is not a directory."
        case .unreadableDirectory:
            "The selected directory could not be read."
        }
    }
}