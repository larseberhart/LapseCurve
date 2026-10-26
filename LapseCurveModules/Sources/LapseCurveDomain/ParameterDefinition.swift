/// Verified metadata mapping and validation rules for one parameter.
public struct ParameterDefinition: Codable, Equatable, Sendable {
    /// Domain parameter described by this definition.
    public let parameter: DevelopmentParameter
    /// Namespace URI, not a preferred XML prefix.
    public let namespaceURI: String
    /// Adobe property name within the namespace.
    public let xmpTag: String
    /// Canonical unit used by the application.
    public let unit: ParameterUnit
    /// Default interpolation strategy for this parameter.
    public let interpolation: ParameterInterpolation
    /// Verified inclusive range, or `nil` while no range is certified.
    public let validRange: ClosedRange<Double>?
    /// Whether this mapping is approved for writing.
    public let writable: Bool
    /// Compatibility evidence or limitations for this mapping.
    public let compatibilityNotes: String?

    /// Creates a parameter definition from a tested metadata mapping.
    public init(
        parameter: DevelopmentParameter,
        namespaceURI: String,
        xmpTag: String,
        unit: ParameterUnit,
        interpolation: ParameterInterpolation,
        validRange: ClosedRange<Double>?,
        writable: Bool,
        compatibilityNotes: String?
    ) {
        self.parameter = parameter
        self.namespaceURI = namespaceURI
        self.xmpTag = xmpTag
        self.unit = unit
        self.interpolation = interpolation
        self.validRange = validRange
        self.writable = writable
        self.compatibilityNotes = compatibilityNotes
    }
}