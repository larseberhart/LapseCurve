/// Development parameter samples associated with one frame or keyframe.
public struct ParameterSet: Codable, Equatable, Sendable {
    /// Samples keyed by their domain parameter identifiers.
    public var values: [DevelopmentParameter: ParameterSample]

    /// Creates a parameter set.
    public init(values: [DevelopmentParameter: ParameterSample] = [:]) {
        self.values = values
    }
}