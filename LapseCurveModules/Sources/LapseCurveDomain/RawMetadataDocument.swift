import Foundation

/// Original opaque XMP packet retained for preservation-aware updates.
public struct RawMetadataDocument: Codable, Equatable, Sendable {
    /// Original packet bytes; callers must not discard unknown data on update.
    public var data: Data
    /// Declared packet media type, such as `application/rdf+xml`.
    public var mediaType: String
    /// Fingerprint of the source packet when it was read.
    public var sourceFingerprint: FileFingerprint?

    /// Creates an opaque metadata snapshot.
    public init(data: Data, mediaType: String, sourceFingerprint: FileFingerprint?) {
        self.data = data
        self.mediaType = mediaType
        self.sourceFingerprint = sourceFingerprint
    }
}