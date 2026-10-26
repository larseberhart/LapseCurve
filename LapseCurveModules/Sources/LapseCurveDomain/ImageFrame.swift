import Foundation

/// One supported image in the ordered source sequence.
public struct ImageFrame: Codable, Equatable, Identifiable, Sendable {
    /// Stable frame identity retained across rescans when possible.
    public var id: FrameID
    /// Path relative to the selected working directory.
    public var relativePath: String
    /// Zero-based deterministic position in the sequence.
    public var sequenceIndex: Int
    /// Capture time, if it could be resolved.
    public var captureTime: Date?
    /// Source of `captureTime` or reason it is unavailable.
    public var captureTimeSource: CaptureTimeSource
    /// Camera settings used by capture-exposure analysis.
    public var captureMetadata: CaptureMetadata
    /// Current status of readable metadata.
    public var metadataStatus: MetadataStatus
    /// Resolved rating, or `nil` if unavailable or unreadable.
    public var rating: Int?
    /// Source that supplied the resolved rating.
    public var ratingSource: RatingSource
    /// Associated keyframe identity, if this frame is a keyframe.
    public var keyframeID: UUID?
    /// Source-file snapshot used for change detection.
    public var fileFingerprint: FileFingerprint?

    /// Creates a frame record from scanned sequence values.
    public init(
        id: FrameID,
        relativePath: String,
        sequenceIndex: Int,
        captureTime: Date? = nil,
        captureTimeSource: CaptureTimeSource = .unavailable,
        captureMetadata: CaptureMetadata = CaptureMetadata(),
        metadataStatus: MetadataStatus = .notRead,
        rating: Int? = nil,
        ratingSource: RatingSource = .unavailable,
        keyframeID: UUID? = nil,
        fileFingerprint: FileFingerprint? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sequenceIndex = sequenceIndex
        self.captureTime = captureTime
        self.captureTimeSource = captureTimeSource
        self.captureMetadata = captureMetadata
        self.metadataStatus = metadataStatus
        self.rating = rating
        self.ratingSource = ratingSource
        self.keyframeID = keyframeID
        self.fileFingerprint = fileFingerprint
    }
}