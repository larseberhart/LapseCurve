import Foundation

/// Failure to obtain or encode an allowed preview representation.
public enum PreviewError: Error, Equatable, LocalizedError, Sendable {
    case invalidMaximumPixelSize
    case invalidSourceURL
    case sourceChangedDuringRead
    case previewUnavailable
    case encodingFailed

    /// Human-readable explanation for the preview failure.
    public var errorDescription: String? {
        switch self {
        case .invalidMaximumPixelSize:
            "Maximum preview size must be positive."
        case .invalidSourceURL:
            "Preview source must be a local file URL."
        case .sourceChangedDuringRead:
            "Preview source changed while its image was being read."
        case .previewUnavailable:
            "No embedded preview or explicitly associated JPEG is available."
        case .encodingFailed:
            "The downsampled preview could not be encoded."
        }
    }
}