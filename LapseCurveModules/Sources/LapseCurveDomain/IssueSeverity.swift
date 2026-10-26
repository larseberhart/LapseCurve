/// User-facing importance of a validation or scan diagnostic.
public enum IssueSeverity: String, Codable, CaseIterable, Sendable {
    /// Informational context that does not block the operation.
    case info
    /// Recoverable condition that should be shown to the user.
    case warning
    /// Invalid state that blocks the requested operation.
    case error
}