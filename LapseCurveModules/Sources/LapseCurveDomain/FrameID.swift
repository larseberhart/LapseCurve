import Foundation

/// Stable identity for one imported image frame.
public struct FrameID: Codable, Hashable, Sendable {
    /// The UUID used as this frame's identity.
    public let rawValue: UUID

    /// Creates a frame identity from a UUID.
    /// - Parameter rawValue: UUID to wrap.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}