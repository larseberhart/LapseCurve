/// Canonical unit used to store a development parameter value.
public enum ParameterUnit: String, Codable, CaseIterable, Sendable {
    /// Exposure adjustment in stops.
    case exposureEV
    /// Color temperature in Kelvin.
    case temperatureKelvin
    /// Tint adjustment in the verified Adobe representation.
    case tint
    /// Percentage-like scalar.
    case percent
    /// Unitless scalar.
    case dimensionless
}