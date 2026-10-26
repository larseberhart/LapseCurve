/// Interpolation behavior selected for a development parameter or segment.
public enum ParameterInterpolation: String, Codable, CaseIterable, Sendable {
    /// Interpolate proportionally between endpoint values.
    case linear
    /// Apply cubic smoothstep easing between endpoint values.
    case smoothstep
    /// Hold the left endpoint until the next keyframe.
    case hold
    /// Monotone cubic interpolation, reserved until separately implemented and tested.
    case monotoneCubic
}