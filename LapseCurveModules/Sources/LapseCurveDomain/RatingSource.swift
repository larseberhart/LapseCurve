/// Metadata location from which a rating was resolved.
public enum RatingSource: String, Codable, CaseIterable, Sendable {
    /// Rating embedded in a readable image format.
    case embeddedMetadata
    /// Rating read from an external XMP sidecar.
    case xmpSidecar
    /// No rating source was available.
    case unavailable
}