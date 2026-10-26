import Foundation

/// Authoritative development values imported from a keyframe image.
public struct Keyframe: Codable, Equatable, Identifiable, Sendable {
    /// Stable keyframe identity.
    public let id: UUID
    /// Frame containing this keyframe.
    public var frameID: FrameID
    /// Imported parameter values for this keyframe.
    public var parameters: ParameterSet
    /// Whether the complete keyframe is locked against editing.
    public var isLocked: Bool

    /// Creates a keyframe record.
    public init(id: UUID, frameID: FrameID, parameters: ParameterSet, isLocked: Bool) {
        self.id = id
        self.frameID = frameID
        self.parameters = parameters
        self.isLocked = isLocked
    }
}