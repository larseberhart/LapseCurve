/// Behavior when a required endpoint parameter value is absent.
public enum MissingValuePolicy: String, Codable, CaseIterable, Sendable {
    /// Do not calculate a value for the affected segment.
    case skip
    /// Carry the previous available value forward.
    case holdPrevious
    /// Use an explicit configured parameter default.
    case useDefault
    /// Leave the value unresolved and emit a warning.
    case warn
}