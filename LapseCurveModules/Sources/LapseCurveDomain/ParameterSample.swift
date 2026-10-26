/// A parameter value together with its origin and lock state.
public struct ParameterSample: Codable, Equatable, Sendable {
    /// Value in the parameter definition's canonical unit.
    public var value: Double
    /// Source of this value.
    public var origin: ParameterOrigin
    /// Whether recalculation must preserve this sample.
    public var isLocked: Bool

    /// Creates a parameter sample.
    public init(value: Double, origin: ParameterOrigin, isLocked: Bool) {
        self.value = value
        self.origin = origin
        self.isLocked = isLocked
    }
}