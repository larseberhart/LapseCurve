import Foundation
import LapseCurveDomain

/// Estimates relative capture exposure from shutter duration, aperture and ISO metadata.
public struct CaptureExposureAnalyzer: Sendable {
    private let minimumShutterSeconds = 1.0 / 1_000_000
    private let maximumShutterSeconds = 3_600.0
    private let plausibleAperture = 0.5...128.0
    private let plausibleISO = 1.0...1_000_000.0
    private let maximumAdjacentExposureStepEV = 8.0

    public init() { }

    /// Computes median-centered capture EV values. Missing or invalid metadata is excluded and reported.
    public func analyze(
        frames: [ImageFrame],
        settings: CaptureExposureCompensationSettings = CaptureExposureCompensationSettings()
    ) -> CaptureExposureCurve {
        guard settings.referenceISO.isFinite, plausibleISO.contains(settings.referenceISO) else {
            return CaptureExposureCurve(
                referenceISO: settings.referenceISO,
                referenceEV: nil,
                samplesByFrameID: [:],
                diagnostics: [ValidationIssue(
                    severity: .warning,
                    code: "invalidReferenceISO",
                    message: "Reference ISO must be finite and between 1 and 1,000,000."
                )]
            )
        }

        let orderedFrames = frames.sorted { $0.sequenceIndex < $1.sequenceIndex }
        var diagnostics: [ValidationIssue] = []
        var exposures: [(frame: ImageFrame, captureEV: Double)] = []

        for frame in orderedFrames {
            let metadata = frame.captureMetadata
            guard let shutter = metadata.shutterDurationSeconds,
                  let aperture = metadata.apertureFNumber,
                  let iso = metadata.iso else {
                let code = metadata.shutterDurationSeconds == nil
                    && metadata.apertureFNumber == nil
                    && metadata.iso == nil
                    ? "captureExposureMissing"
                    : "captureExposureIncomplete"
                diagnostics.append(ValidationIssue(
                    severity: .warning,
                    code: code,
                    message: code == "captureExposureMissing"
                        ? "Shutter, aperture and ISO are required for capture-exposure analysis."
                        : "Capture-exposure analysis needs shutter, aperture and ISO; no values were inferred.",
                    frameID: frame.id
                ))
                continue
            }

            guard shutter.isFinite, aperture.isFinite, iso.isFinite,
                  (minimumShutterSeconds...maximumShutterSeconds).contains(shutter),
                  plausibleAperture.contains(aperture),
                  plausibleISO.contains(iso) else {
                diagnostics.append(ValidationIssue(
                    severity: .warning,
                    code: "captureExposureImplausible",
                    message: "Capture metadata is non-finite or outside the supported plausibility bounds; this frame was excluded.",
                    frameID: frame.id
                ))
                continue
            }

            let captureEV = log2(shutter) - 2 * log2(aperture) + log2(iso / settings.referenceISO)
            guard captureEV.isFinite else {
                diagnostics.append(ValidationIssue(
                    severity: .warning,
                    code: "captureExposureInvalid",
                    message: "Capture exposure could not be calculated; this frame was excluded.",
                    frameID: frame.id
                ))
                continue
            }
            exposures.append((frame, captureEV))
        }

        guard !exposures.isEmpty else {
            return CaptureExposureCurve(
                referenceISO: settings.referenceISO,
                referenceEV: nil,
                samplesByFrameID: [:],
                diagnostics: diagnostics
            )
        }

        let referenceEV = median(exposures.map(\.captureEV))
        var samples: [FrameID: CaptureExposureSample] = [:]
        for exposure in exposures {
            let relativeEV = exposure.captureEV - referenceEV
            samples[exposure.frame.id] = CaptureExposureSample(
                captureEV: exposure.captureEV,
                relativeEV: relativeEV,
                correctionEV: -relativeEV
            )
        }

        for pair in zip(exposures, exposures.dropFirst()) {
            let step = abs(pair.1.captureEV - pair.0.captureEV)
            if step > maximumAdjacentExposureStepEV {
                diagnostics.append(ValidationIssue(
                    severity: .warning,
                    code: "captureExposureJump",
                    message: String(format: "Capture exposure changes by %.1f EV between nearby valid frames; verify the metadata and sequence.", step),
                    frameID: pair.1.frame.id
                ))
            }
        }

        return CaptureExposureCurve(
            referenceISO: settings.referenceISO,
            referenceEV: referenceEV,
            samplesByFrameID: samples,
            diagnostics: diagnostics
        )
    }

    private func median(_ values: [Double]) -> Double {
        let orderedValues = values.sorted()
        let midpoint = orderedValues.count / 2
        if orderedValues.count.isMultiple(of: 2) {
            return (orderedValues[midpoint - 1] + orderedValues[midpoint]) / 2
        }
        return orderedValues[midpoint]
    }
}
