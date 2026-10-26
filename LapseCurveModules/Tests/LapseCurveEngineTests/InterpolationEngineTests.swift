import Foundation
import LapseCurveDomain
import Testing
@testable import LapseCurveEngine

struct InterpolationEngineTests {
    @Test func preservesKeyframesAndDoesNotExtrapolate() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [1, 3],
            keyframeValues: [1: 0, 3: 4]
        )
        let result = try calculate(sequence)

        #expect(value(at: 0, sequence: sequence, result: result) == nil)
        #expect(value(at: 1, sequence: sequence, result: result) == 0)
        #expect(value(at: 2, sequence: sequence, result: result) == 2)
        #expect(value(at: 3, sequence: sequence, result: result) == 4)
        #expect(value(at: 4, sequence: sequence, result: result) == nil)
        #expect(result.valuesByFrame[sequence.frames[1].id]?.values[.exposure]?.origin == .keyframe)
        #expect(result.valuesByFrame[sequence.frames[2].id]?.values[.exposure]?.origin == .interpolated)
    }

    @Test func interpolatesEachConsecutiveKeyframeSegmentIndependently() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...6),
            keyframePositions: [1, 3, 5],
            keyframeValues: [1: 0, 3: 4, 5: 0]
        )
        let result = try calculate(sequence)

        #expect(value(at: 2, sequence: sequence, result: result) == 2)
        #expect(value(at: 4, sequence: sequence, result: result) == 2)
        #expect(value(at: 0, sequence: sequence, result: result) == nil)
        #expect(value(at: 6, sequence: sequence, result: result) == nil)
    }

    @Test func implementsLinearSmoothstepAndHold() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [0, 4],
            keyframeValues: [0: 0, 4: 4]
        )

        let linear = try calculate(sequence, interpolation: .linear)
        let smoothstep = try calculate(sequence, interpolation: .smoothstep)
        let hold = try calculate(sequence, interpolation: .hold)

        #expect(value(at: 1, sequence: sequence, result: linear) == 1)
        #expect(value(at: 1, sequence: sequence, result: smoothstep) == 0.625)
        #expect(value(at: 1, sequence: sequence, result: hold) == 0)
        #expect(value(at: 4, sequence: sequence, result: hold) == 4)
    }

    @Test func segmentChoicesOverrideDefinitionsWithoutChangingNeighbors() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...8),
            keyframePositions: [0, 4, 8],
            keyframeValues: [0: 0, 4: 4, 8: 0]
        )
        for mode in [ParameterInterpolation.smoothstep, .hold] {
            let result = try calculate(sequence, segmentInterpolations: [
                SegmentInterpolation(startFrameID: sequence.frames[0].id, endFrameID: sequence.frames[4].id, mode: mode)
            ])
            #expect(value(at: 1, sequence: sequence, result: result) == (mode == .hold ? 0 : 0.625))
            #expect(value(at: 5, sequence: sequence, result: result) == 3)
            #expect(value(at: 4, sequence: sequence, result: result) == 4)
            #expect(value(at: 8, sequence: sequence, result: result) == 0)
        }
        let overridden = try calculate(sequence, overrides: [makeOverride(frameID: sequence.frames[1].id, value: 7)],
            segmentInterpolations: [SegmentInterpolation(startFrameID: sequence.frames[0].id,
                endFrameID: sequence.frames[4].id, mode: .hold)])
        #expect(value(at: 1, sequence: sequence, result: overridden) == 7)
    }

    @Test func captureTimeUsesElapsedTimeInsteadOfFrameIndex() throws {
        let start = Date(timeIntervalSince1970: 100)
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [0, 4],
            keyframeValues: [0: 0, 4: 4],
            captureTimes: [
                0: start,
                1: start.addingTimeInterval(10),
                2: start.addingTimeInterval(30),
                3: start.addingTimeInterval(35),
                4: start.addingTimeInterval(40)
            ]
        )

        let result = try calculate(sequence, timeBasis: .captureTime)

        #expect(value(at: 2, sequence: sequence, result: result) == 3)
    }

    @Test func missingParameterPoliciesAreExplicit() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...2),
            keyframePositions: [0, 2],
            keyframeValues: [0: 2]
        )

        let skipped = try calculate(sequence, missingValuePolicy: .skip)
        #expect(value(at: 1, sequence: sequence, result: skipped) == nil)
        #expect(skipped.warnings.contains { $0.code == "keyframeParameterMissing" })
        #expect(skipped.warnings.first(where: { $0.code == "keyframeParameterMissing" })?.severity == .info)

        let warned = try calculate(sequence, missingValuePolicy: .warn)
        #expect(value(at: 1, sequence: sequence, result: warned) == nil)
        #expect(warned.warnings.contains { $0.severity == .warning })

        let held = try calculate(sequence, missingValuePolicy: .holdPrevious)
        #expect(value(at: 1, sequence: sequence, result: held) == 2)
        #expect(held.warnings.contains { $0.code == "missingParameterHeld" })

        let defaulted = try calculate(
            sequence,
            missingValuePolicy: .useDefault,
            parameterDefaults: [.exposure: -2]
        )
        #expect(value(at: 1, sequence: sequence, result: defaulted) == 0)
        #expect(defaulted.warnings.contains { $0.code == "missingParameterDefaulted" })
    }

    @Test func holdPreviousAndDefaultsCoverParametersMissingAtBothEndpoints() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [0, 2, 4],
            keyframeValues: [0: 3]
        )

        let held = try calculate(sequence, missingValuePolicy: .holdPrevious)
        #expect(value(at: 3, sequence: sequence, result: held) == 3)
        #expect(held.warnings.contains { $0.code == "missingParameterHeld" })

        let defaulted = try calculate(
            sequence,
            missingValuePolicy: .useDefault,
            parameterDefaults: [.exposure: -2]
        )
        #expect(value(at: 1, sequence: sequence, result: defaulted) == 0.5)
        #expect(value(at: 3, sequence: sequence, result: defaulted) == -2)
    }

    @Test func invalidCaptureTimesFollowMissingValuePolicy() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...2),
            keyframePositions: [0, 2],
            keyframeValues: [0: 2, 2: 8]
        )

        let held = try calculate(sequence, timeBasis: .captureTime, missingValuePolicy: .holdPrevious)
        #expect(value(at: 1, sequence: sequence, result: held) == 2)
        #expect(held.warnings.contains { $0.code == "captureTimeUnavailableForInterpolation" })

        let defaulted = try calculate(
            sequence,
            timeBasis: .captureTime,
            missingValuePolicy: .useDefault,
            parameterDefaults: [.exposure: -3]
        )
        #expect(value(at: 1, sequence: sequence, result: defaulted) == -3)

        let skipped = try calculate(sequence, timeBasis: .captureTime, missingValuePolicy: .skip)
        #expect(value(at: 1, sequence: sequence, result: skipped) == nil)

        let skippedWithWarning = try calculate(sequence, timeBasis: .captureTime, missingValuePolicy: .warn)
        #expect(value(at: 1, sequence: sequence, result: skippedWithWarning) == nil)
        #expect(skippedWithWarning.warnings.contains {
            $0.code == "captureTimeUnavailableForInterpolation" && $0.severity == .warning
        })

        let start = Date(timeIntervalSince1970: 500)
        let equalTimes = makeSequence(
            frameIndices: Array(0...2),
            keyframePositions: [0, 2],
            keyframeValues: [0: 2, 2: 8],
            captureTimes: [0: start, 1: start, 2: start]
        )
        let equalTimesHeld = try calculate(
            equalTimes,
            timeBasis: .captureTime,
            missingValuePolicy: .holdPrevious
        )
        #expect(value(at: 1, sequence: equalTimes, result: equalTimesHeld) == 2)
        #expect(equalTimesHeld.warnings.contains { $0.code == "captureTimeUnavailableForInterpolation" })
    }

    @Test func manualOverrideRunsLastAndLockedStateSurvives() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [0, 4],
            keyframeValues: [0: 0, 4: 4]
        )
        let override = makeOverride(frameID: sequence.frames[2].id, value: 7)
        let result = try calculate(sequence, overrides: [override])
        let sample = try #require(result.valuesByFrame[sequence.frames[2].id]?.values[.exposure])

        #expect(sample.value == 7)
        #expect(sample.origin == .manualOverride)
        #expect(sample.isLocked)
        #expect(value(at: 0, sequence: sequence, result: result) == 0)
        #expect(value(at: 4, sequence: sequence, result: result) == 4)
    }

    @Test func rejectsKeyframeAndOutOfRangeOverrides() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...4),
            keyframePositions: [1, 3],
            keyframeValues: [1: 0, 3: 4]
        )
        let keyframeOverride = makeOverride(frameID: sequence.frames[1].id, value: 1)
        #expect(throws: InterpolationError.overrideTargetsKeyframe(sequence.frames[1].id)) {
            try calculate(sequence, overrides: [keyframeOverride])
        }

        let outsideOverride = makeOverride(frameID: sequence.frames[0].id, value: 1)
        #expect(throws: InterpolationError.overrideOutsideInterpolationRange(sequence.frames[0].id)) {
            try calculate(sequence, overrides: [outsideOverride])
        }

        let mismatchedSequence = (
            frames: sequence.frames.map { frame -> ImageFrame in
                var adjustedFrame = frame
                if frame.id == sequence.keyframes[0].frameID {
                    adjustedFrame.keyframeID = nil
                }
                return adjustedFrame
            },
            keyframes: sequence.keyframes
        )
        #expect(throws: InterpolationError.inconsistentFrameKeyframeID(sequence.keyframes[0].frameID)) {
            try calculate(mismatchedSequence)
        }
    }

    @Test func rejectsDuplicateFramePositionsKeyframesAndOverrides() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...2),
            keyframePositions: [0, 2],
            keyframeValues: [0: 0, 2: 2]
        )

        var duplicateIndexFrames = sequence.frames
        duplicateIndexFrames[1].sequenceIndex = 0
        #expect(throws: InterpolationError.duplicateSequenceIndex(0)) {
            try calculate((duplicateIndexFrames, sequence.keyframes))
        }

        var duplicateKeyframes = sequence.keyframes
        duplicateKeyframes.append(
            Keyframe(
                id: UUID(),
                frameID: sequence.keyframes[0].frameID,
                parameters: ParameterSet(),
                isLocked: false
            )
        )
        #expect(throws: InterpolationError.duplicateKeyframePosition(sequence.keyframes[0].frameID)) {
            try calculate((sequence.frames, duplicateKeyframes))
        }

        let override = makeOverride(frameID: sequence.frames[1].id, value: 1)
        #expect(throws: InterpolationError.duplicateOverride(override.frameID, override.parameter)) {
            try calculate(sequence, overrides: [override, override])
        }
    }

    @Test func rejectsInvalidValuesRangesAndUnsupportedStrategies() throws {
        let nonFiniteSequence = makeSequence(
            frameIndices: [0, 1, 2],
            keyframePositions: [0, 2],
            keyframeValues: [0: .infinity, 1: 1]
        )
        #expect(throws: InterpolationError.nonFiniteValue(.exposure)) {
            try calculate(nonFiniteSequence)
        }

        let outOfRangeSequence = makeSequence(
            frameIndices: [0, 1, 2],
            keyframePositions: [0, 2],
            keyframeValues: [0: 0, 2: 12]
        )
        #expect(throws: InterpolationError.valueOutOfRange(.exposure, 12)) {
            try calculate(outOfRangeSequence)
        }

        let validSequence = makeSequence(
            frameIndices: [0, 1, 2],
            keyframePositions: [0, 2],
            keyframeValues: [0: 0, 2: 4]
        )
        #expect(throws: InterpolationError.unsupportedStrategy(.monotoneCubic)) {
            try calculate(validSequence, interpolation: .monotoneCubic)
        }
    }

    @Test func repeatedCalculationsAreDeterministic() throws {
        let sequence = makeSequence(
            frameIndices: Array(0...6),
            keyframePositions: [1, 5],
            keyframeValues: [1: -1.25, 5: 2.75]
        )

        let firstResult = try calculate(sequence, interpolation: .smoothstep)
        let secondResult = try calculate(sequence, interpolation: .smoothstep)

        #expect(firstResult.valuesByFrame == secondResult.valuesByFrame)
        #expect(firstResult.warnings == secondResult.warnings)
    }

    private func calculate(
        _ sequence: (frames: [ImageFrame], keyframes: [Keyframe]),
        overrides: [ManualOverride] = [],
        interpolation: ParameterInterpolation = .linear,
        timeBasis: TimeBasis = .frameIndex,
        missingValuePolicy: MissingValuePolicy = .warn,
        parameterDefaults: [DevelopmentParameter: Double] = [:],
        segmentInterpolations: [SegmentInterpolation] = []
    ) throws -> InterpolationResult {
        try InterpolationEngine().calculate(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            overrides: overrides,
            settings: ProjectSettings(
                timeBasis: timeBasis,
                defaultInterpolation: interpolation,
                missingValuePolicy: missingValuePolicy,
                parameterDefaults: parameterDefaults,
                exportMode: .updateExistingSidecars,
                segmentInterpolations: segmentInterpolations
            ),
            parameterDefinitions: [exposureDefinition(interpolation: interpolation)]
        )
    }

    private func makeSequence(
        frameIndices: [Int],
        keyframePositions: [Int],
        keyframeValues: [Int: Double],
        captureTimes: [Int: Date] = [:]
    ) -> (frames: [ImageFrame], keyframes: [Keyframe]) {
        let keyframeIDsByPosition = Dictionary(uniqueKeysWithValues: keyframePositions.map { ($0, UUID()) })
        let frames = frameIndices.map { index in
            ImageFrame(
                id: FrameID(rawValue: UUID()),
                relativePath: "frame\(index).dng",
                sequenceIndex: index,
                captureTime: captureTimes[index],
                captureTimeSource: captureTimes[index] == nil ? .unavailable : .exif,
                metadataStatus: .valid,
                rating: keyframeIDsByPosition[index] == nil ? 0 : 1,
                ratingSource: .xmpSidecar,
                keyframeID: keyframeIDsByPosition[index]
            )
        }
        let frameIDsByPosition = Dictionary(uniqueKeysWithValues: frames.map { ($0.sequenceIndex, $0.id) })
        let keyframes = keyframePositions.map { index in
            var parameterValues: [DevelopmentParameter: ParameterSample] = [:]
            if let value = keyframeValues[index] {
                parameterValues[.exposure] = ParameterSample(value: value, origin: .keyframe, isLocked: false)
            }
            return Keyframe(
                id: keyframeIDsByPosition[index]!,
                frameID: frameIDsByPosition[index]!,
                parameters: ParameterSet(values: parameterValues),
                isLocked: false
            )
        }
        return (frames, keyframes)
    }

    private func exposureDefinition(interpolation: ParameterInterpolation) -> ParameterDefinition {
        ParameterDefinition(
            parameter: .exposure,
            namespaceURI: "http://ns.adobe.com/camera-raw-settings/1.0/",
            xmpTag: "Exposure2012",
            unit: .exposureEV,
            interpolation: interpolation,
            validRange: -10...10,
            writable: false,
            compatibilityNotes: "Test definition only."
        )
    }

    private func makeOverride(frameID: FrameID, value: Double) -> ManualOverride {
        ManualOverride(id: UUID(), frameID: frameID, parameter: .exposure, value: value, isLocked: true)
    }

    private func value(
        at sequenceIndex: Int,
        sequence: (frames: [ImageFrame], keyframes: [Keyframe]),
        result: InterpolationResult
    ) -> Double? {
        guard let frame = sequence.frames.first(where: { $0.sequenceIndex == sequenceIndex }) else {
            return nil
        }
        return result.valuesByFrame[frame.id]?.values[.exposure]?.value
    }
}