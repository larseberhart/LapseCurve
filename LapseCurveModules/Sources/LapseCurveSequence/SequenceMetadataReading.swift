import Foundation

/// Read-only boundary implemented by a metadata adapter.
public protocol SequenceMetadataReading: Sendable {
    /// Reads embedded image metadata and an optional pre-existing XMP sidecar.
    func readMetadata(imageURL: URL, sidecarURL: URL?) async -> FrameMetadataSnapshot
}