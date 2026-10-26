import Foundation
import LapseCurveDomain
import LapseCurveEngine
import Testing
@testable import LapseCurveAnalysis

struct CaptureExposureAnalysisTests {
    @Test func compensationIsDisabledByDefault() {
        #expect(CaptureExposureCompensationSettings().isEnabled == false)
    }

    @Test func estimatesKnownShutterAndISOGainsAndInverseCorrection() {
        let frames = [
            frame(index: 0, shutter: 1.0 / 200, aperture: 4, iso: 100),
            frame(index: 1, shutter: 1.0 / 100, aperture: 4, iso: 100),
            frame(index: 2, shutter: 1.0 / 100, aperture: 4, iso: 200)
        ]

        let curve = CaptureExposureAnalyzer().analyze(frames: frames)

        #expect(abs((curve.samplesByFrameID[frames[0].id]?.relativeEV ?? 99) + 1) < 0.000_001)
        #expect(abs(curve.samplesByFrameID[frames[1].id]?.relativeEV ?? 99) < 0.000_001)
        #expect(abs((curve.samplesByFrameID[frames[2].id]?.relativeEV ?? 99) - 1) < 0.000_001)
        #expect(abs((curve.samplesByFrameID[frames[2].id]?.correctionEV ?? 99) + 1) < 0.000_001)
    }

    @Test func missingAndImplausibleMetadataAreReportedWithoutGuessing() {
        let missing = frame(index: 0, shutter: nil, aperture: nil, iso: nil)
        let incomplete = frame(index: 1, shutter: 0.01, aperture: nil, iso: 100)
        let invalid = frame(index: 2, shutter: -1, aperture: 4, iso: 100)

        let curve = CaptureExposureAnalyzer().analyze(frames: [missing, incomplete, invalid])

        #expect(curve.samplesByFrameID.isEmpty)
        #expect(curve.diagnostics.map(\.code).contains("captureExposureMissing"))
        #expect(curve.diagnostics.map(\.code).contains("captureExposureIncomplete"))
        #expect(curve.diagnostics.map(\.code).contains("captureExposureImplausible"))
    }

    @Test func largeAdjacentExposureChangesAreFlagged() {
        let frames = [
            frame(index: 0, shutter: 1.0 / 1000, aperture: 4, iso: 100),
            frame(index: 1, shutter: 1, aperture: 4, iso: 100)
        ]

        let curve = CaptureExposureAnalyzer().analyze(frames: frames)

        #expect(curve.diagnostics.contains { $0.code == "captureExposureJump" })
        #expect(curve.samplesByFrameID.count == 2)
    }

    @Test func enabledCompensationAdjustsOnlyInterpolatedIntermediateExposure() {
        let frames = [
            frame(index: 0, shutter: 1.0 / 200, aperture: 4, iso: 100),
            frame(index: 1, shutter: 1.0 / 50, aperture: 4, iso: 100),
            frame(index: 2, shutter: 1.0 / 100, aperture: 4, iso: 100)
        ]
        let keyframeIDs: Set<FrameID> = [frames[0].id, frames[2].id]
        let base = InterpolationResult(valuesByFrame: [
            frames[0].id: values(1, origin: .keyframe),
            frames[1].id: values(0, origin: .interpolated),
            frames[2].id: values(-1, origin: .keyframe)
        ], warnings: [])
        let curve = CaptureExposureAnalyzer().analyze(frames: frames)

        let adjusted = CaptureExposureCompensationEngine().applying(
            curve: curve,
            to: base,
            frames: frames,
            keyframeIDs: keyframeIDs,
            settings: CaptureExposureCompensationSettings(isEnabled: true, strength: 0.5)
        )

        #expect(adjusted.valuesByFrame[frames[0].id]?.values[.exposure]?.value == 1)
        #expect(adjusted.valuesByFrame[frames[1].id]?.values[.exposure]?.value == -0.5)
        #expect(adjusted.valuesByFrame[frames[1].id]?.values[.exposure]?.origin == .holyGrailCompensation)
        #expect(adjusted.valuesByFrame[frames[2].id]?.values[.exposure]?.value == -1)
        #expect(base.valuesByFrame[frames[1].id]?.values[.exposure]?.value == 0)
    }

    @Test func zeroStrengthIsIdentityAndCompensationPreservesAnchorsAndOverrides() {
        let frames = [
            frame(index: 0, shutter: 1.0 / 100, aperture: 4, iso: 100),
            frame(index: 1, shutter: 1.0 / 50, aperture: 4, iso: 100),
            frame(index: 2, shutter: 1.0 / 25, aperture: 4, iso: 100)
        ]
        let keyframeIDs: Set<FrameID> = [frames[0].id, frames[2].id]
        let base = InterpolationResult(valuesByFrame: [
            frames[0].id: values(2, origin: .keyframe),
            frames[1].id: values(1, origin: .manualOverride),
            frames[2].id: values(0, origin: .keyframe)
        ], warnings: [])
        let analyzer = CaptureExposureAnalyzer()
        let curve = analyzer.analyze(frames: frames)
        let engine = CaptureExposureCompensationEngine()

        let zeroStrength = engine.applying(
            curve: curve,
            to: base,
            frames: frames,
            keyframeIDs: keyframeIDs,
            settings: CaptureExposureCompensationSettings(isEnabled: true, strength: 0)
        )
        #expect(zeroStrength.valuesByFrame == base.valuesByFrame)

        let adjusted = engine.applying(
            curve: curve,
            to: base,
            frames: frames,
            keyframeIDs: keyframeIDs,
            settings: CaptureExposureCompensationSettings(isEnabled: true, strength: 1)
        )
        #expect(adjusted.valuesByFrame[frames[0].id]?.values[.exposure]?.value == 2)
        #expect(adjusted.valuesByFrame[frames[1].id]?.values[.exposure]?.value == 1)
        #expect(base.valuesByFrame[frames[0].id]?.values[.exposure]?.value == 2)
        #expect(adjusted.valuesByFrame[frames[1].id]?.values[.exposure]?.origin == .manualOverride)
    }

    private func frame(index: Int, shutter: Double?, aperture: Double?, iso: Double?) -> ImageFrame {
        ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: "frame-\(index).dng",
            sequenceIndex: index,
            captureMetadata: CaptureMetadata(
                shutterDurationSeconds: shutter,
                apertureFNumber: aperture,
                iso: iso
            )
        )
    }

    private func values(_ value: Double, origin: ParameterOrigin) -> ParameterSet {
        ParameterSet(values: [
            .exposure: ParameterSample(value: value, origin: origin, isLocked: origin == .keyframe)
        ])
    }
}
