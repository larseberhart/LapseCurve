import LapseCurveDomain
import LapseCurveEngine

/// Applies the capture-derived correction as a distinct, adjustable output layer.
public struct CaptureExposureCompensationEngine: Sendable {
    public init() { }

    /// Returns the base result unchanged when disabled or at zero strength.
    /// Keyframes and manually overridden exposure samples are never modified.
    public func applying(
        curve: CaptureExposureCurve,
        to baseResult: InterpolationResult,
        frames: [ImageFrame],
        keyframeIDs: Set<FrameID>,
        settings: CaptureExposureCompensationSettings
    ) -> InterpolationResult {
        let strength = settings.normalizedStrength
        guard settings.isEnabled, strength > 0 else { return baseResult }

        var valuesByFrame = baseResult.valuesByFrame
        for frame in frames where !keyframeIDs.contains(frame.id) {
            guard let correction = curve.samplesByFrameID[frame.id]?.correctionEV,
                  let currentSample = valuesByFrame[frame.id]?.values[.exposure],
                  currentSample.origin == .interpolated else {
                continue
            }

            let compensatedValue = currentSample.value + correction * strength
            guard compensatedValue.isFinite else { continue }
            var parameterSet = valuesByFrame[frame.id] ?? ParameterSet()
            parameterSet.values[.exposure] = ParameterSample(
                value: compensatedValue,
                origin: .holyGrailCompensation,
                isLocked: currentSample.isLocked
            )
            valuesByFrame[frame.id] = parameterSet
        }

        return InterpolationResult(valuesByFrame: valuesByFrame, warnings: baseResult.warnings)
    }
}
