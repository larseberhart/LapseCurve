import Foundation

/// Counts and context from one completed directory scan.
public struct SequenceScanSummary: Codable, Equatable, Sendable {
    /// Non-authoritative path hint for display and relinking.
    public var workingDirectoryPathHint: String
    /// Number of supported image files found.
    public var photoCount: Int
    /// Number of frames resolved as one-star keyframes.
    public var keyframeCount: Int
    /// Number of frames whose rating could not be read.
    public var unreadableRatingCount: Int
    /// Number of encountered files excluded as unsupported.
    public var unsupportedFileCount: Int
    /// Time the scan completed.
    public var scannedAt: Date

    /// Creates a sequence scan summary.
    public init(
        workingDirectoryPathHint: String,
        photoCount: Int,
        keyframeCount: Int,
        unreadableRatingCount: Int,
        unsupportedFileCount: Int,
        scannedAt: Date
    ) {
        self.workingDirectoryPathHint = workingDirectoryPathHint
        self.photoCount = photoCount
        self.keyframeCount = keyframeCount
        self.unreadableRatingCount = unreadableRatingCount
        self.unsupportedFileCount = unsupportedFileCount
        self.scannedAt = scannedAt
    }
}