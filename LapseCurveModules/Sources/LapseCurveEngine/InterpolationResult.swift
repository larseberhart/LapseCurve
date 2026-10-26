import LapseCurveDomain

/// Calculated parameter values keyed by frame identity, plus diagnostics.
public struct InterpolationResult: Sendable {
    /// Values for keyframes and frames inside interpolated segments only.
    public var valuesByFrame: [FrameID: ParameterSet]
    /// Missing-data, timestamp and unsupported-mode diagnostics.
    public var warnings: [ValidationIssue]

    /// Creates an interpolation result.
    public init(valuesByFrame: [FrameID: ParameterSet], warnings: [ValidationIssue]) {
        self.valuesByFrame = valuesByFrame
        self.warnings = warnings
    }
}