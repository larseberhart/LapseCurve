/// Origin of a frame's capture-time value.
public enum CaptureTimeSource: String, Codable, CaseIterable, Sendable {
    /// Read from embedded EXIF or equivalent image metadata.
    case exif
    /// Parsed from a filename using an explicit supported convention.
    case filename
    /// Inferred from filesystem metadata as a fallback.
    case filesystemFallback
    /// No reliable capture time is available.
    case unavailable
}