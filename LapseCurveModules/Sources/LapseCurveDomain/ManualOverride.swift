import Foundation

/// Explicit per-frame value applied after interpolation and compensation.
public struct ManualOverride: Codable, Equatable, Identifiable, Sendable {
    /// Stable override identity.
    public let id: UUID
    /// Frame that receives this override.
    public var frameID: FrameID
    /// Parameter changed by this override.
    public var parameter: DevelopmentParameter
    /// Override value in the parameter's canonical unit.
    public var value: Double
    /// Whether recalculation must retain this override.
    public var isLocked: Bool

    /// Creates a manual parameter override.
    public init(
        id: UUID,
        frameID: FrameID,
        parameter: DevelopmentParameter,
        value: Double,
        isLocked: Bool
    ) {
        self.id = id
        self.frameID = frameID
        self.parameter = parameter
        self.value = value
        self.isLocked = isLocked
    }
}