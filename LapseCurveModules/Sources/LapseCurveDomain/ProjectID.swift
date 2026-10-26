import Foundation

/// Stable identity for one LapseCurve project.
public struct ProjectID: Codable, Hashable, Sendable {
    /// The UUID used as this project's identity.
    public let rawValue: UUID

    /// Creates a project identity from a UUID.
    /// - Parameter rawValue: UUID to wrap.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}