/// User-adjustable controls for the experimental capture-exposure correction layer.
public struct CaptureExposureCompensationSettings: Equatable, Sendable {
    /// Compensation is opt-in until validated on real sequences.
    public var isEnabled: Bool
    /// Fraction of the estimated correction to apply, clamped to 0...1 by the engine.
    public var strength: Double
    /// ISO value used to express capture exposure relative to a stable reference.
    public var referenceISO: Double

    public init(isEnabled: Bool = false, strength: Double = 0.5, referenceISO: Double = 100) {
        self.isEnabled = isEnabled
        self.strength = strength
        self.referenceISO = referenceISO
    }

    var normalizedStrength: Double {
        guard strength.isFinite else { return 0 }
        return min(max(strength, 0), 1)
    }
}
