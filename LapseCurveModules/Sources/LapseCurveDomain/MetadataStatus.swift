/// Read status for a frame's metadata.
public enum MetadataStatus: String, Codable, CaseIterable, Sendable {
    /// Metadata has not been read yet.
    case notRead
    /// All required metadata was read successfully.
    case valid
    /// Some metadata was readable, but fields are missing.
    case partial
    /// Metadata sources disagree.
    case conflict
    /// Metadata could not be parsed.
    case malformed
    /// The file or metadata format is not supported.
    case unsupported
}