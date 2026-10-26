/// Read outcome for one metadata source or field.
public enum MetadataReadStatus: String, Codable, CaseIterable, Sendable {
    /// The requested field was read successfully.
    case readable
    /// The source exists but does not contain the requested field.
    case missing
    /// The source could not be parsed or a value was malformed.
    case malformed
    /// The source format could not be read by the current implementation.
    case unsupported
}