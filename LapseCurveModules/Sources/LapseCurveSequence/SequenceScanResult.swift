import Foundation
import LapseCurveDomain

/// Frames, diagnostics and counts produced by one completed directory scan.
public struct SequenceScanResult: Sendable {
    /// Supported photos in deterministic sequence order.
    public var frames: [ImageFrame]
    /// Keyframe anchors with read-only parameter samples imported from metadata.
    public var keyframes: [Keyframe]
    /// Resolved existing Lightroom XMP paths, keyed by frame identity.
    public var sidecarURLsByFrameID: [FrameID: URL]
    /// Original metadata packets for frames whose existing sidecar was read successfully.
    public var metadataBaselinesByFrameID: [FrameID: RawMetadataDocument]
    /// Scan and metadata warnings; source files are never modified.
    public var warnings: [ValidationIssue]
    /// Counts and path hint for the scan.
    public var summary: SequenceScanSummary

    /// Creates a completed scan result.
    public init(
        frames: [ImageFrame],
        keyframes: [Keyframe] = [],
        sidecarURLsByFrameID: [FrameID: URL] = [:],
        metadataBaselinesByFrameID: [FrameID: RawMetadataDocument] = [:],
        warnings: [ValidationIssue],
        summary: SequenceScanSummary
    ) {
        self.frames = frames
        self.keyframes = keyframes
        self.sidecarURLsByFrameID = sidecarURLsByFrameID
        self.metadataBaselinesByFrameID = metadataBaselinesByFrameID
        self.warnings = warnings
        self.summary = summary
    }
}