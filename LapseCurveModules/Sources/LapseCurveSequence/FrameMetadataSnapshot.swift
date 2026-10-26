import Foundation
import LapseCurveDomain

/// Read-only metadata collected for one image and its associated sidecars.
public struct FrameMetadataSnapshot: Sendable {
    /// Rating read from metadata embedded in the image, when supported.
    public var embeddedRating: RatingMetadataRead
    /// Rating read from the external XMP sidecar, when present.
    public var sidecarRating: RatingMetadataRead
    /// Capture time read from EXIF or equivalent metadata.
    public var captureTime: Date?
    /// Provenance of `captureTime`.
    public var captureTimeSource: CaptureTimeSource
    /// Shutter, aperture and ISO values, without guessed defaults.
    public var captureMetadata: CaptureMetadata
    /// Aggregate status of the metadata read.
    public var metadataStatus: MetadataStatus
    /// Original bytes of a pre-existing metadata sidecar, when readable.
    public var rawMetadataDocument: RawMetadataDocument?
    /// Numeric scalar development values imported from an existing sidecar.
    public var developmentParameters: ParameterSet
    /// Nonfatal problems observed while reading this frame.
    public var warnings: [ValidationIssue]

    /// Creates a read-only metadata snapshot.
    public init(
        embeddedRating: RatingMetadataRead = RatingMetadataRead(status: .missing),
        sidecarRating: RatingMetadataRead = RatingMetadataRead(status: .missing),
        captureTime: Date? = nil,
        captureTimeSource: CaptureTimeSource = .unavailable,
        captureMetadata: CaptureMetadata = CaptureMetadata(),
        metadataStatus: MetadataStatus = .notRead,
        rawMetadataDocument: RawMetadataDocument? = nil,
        developmentParameters: ParameterSet = ParameterSet(),
        warnings: [ValidationIssue] = []
    ) {
        self.embeddedRating = embeddedRating
        self.sidecarRating = sidecarRating
        self.captureTime = captureTime
        self.captureTimeSource = captureTimeSource
        self.captureMetadata = captureMetadata
        self.metadataStatus = metadataStatus
        self.rawMetadataDocument = rawMetadataDocument
        self.developmentParameters = developmentParameters
        self.warnings = warnings
    }
}