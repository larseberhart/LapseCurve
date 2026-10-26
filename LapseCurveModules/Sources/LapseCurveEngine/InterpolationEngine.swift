import Foundation
import LapseCurveDomain

/// Pure, deterministic per-parameter interpolation between adjacent keyframes.
public struct InterpolationEngine: Sendable {
    /// Creates an interpolation engine with no external dependencies.
    public init() { }

    /// Calculates keyframe and intermediate-frame values without file or UI access.
    ///
    /// Frames outside the first and last keyframe are not extrapolated. Keyframe numeric
    /// values are copied exactly; overrides are accepted only for intermediate non-keyframes.
    public func calculate(
        frames: [ImageFrame],
        keyframes: [Keyframe],
        overrides: [ManualOverride],
        settings: ProjectSettings,
        parameterDefinitions: [ParameterDefinition]
    ) throws -> InterpolationResult {
        let framesByID = try indexFrames(frames)
        let definitionsByParameter = try indexDefinitions(parameterDefinitions)
        let anchors = try indexKeyframes(keyframes, framesByID: framesByID)
        for anchor in anchors {
            for (parameter, sample) in anchor.keyframe.parameters.values {
                try validate(
                    sample.value,
                    parameter: parameter,
                    definition: definitionsByParameter[parameter]
                )
            }
        }
        var valuesByFrame = keyframeValues(anchors)
        var warnings: [ValidationIssue] = []
        var intermediateFrameIDs = Set<FrameID>()

        if anchors.count >= 2 {
            for anchorIndex in 0..<(anchors.count - 1) {
                let leftAnchor = anchors[anchorIndex]
                let rightAnchor = anchors[anchorIndex + 1]
                let intermediateFrames = frames
                    .filter {
                        $0.sequenceIndex > leftAnchor.frame.sequenceIndex
                            && $0.sequenceIndex < rightAnchor.frame.sequenceIndex
                    }
                    .sorted { $0.sequenceIndex < $1.sequenceIndex }
                intermediateFrameIDs.formUnion(intermediateFrames.map(\.id))
                guard !intermediateFrames.isEmpty else {
                    continue
                }

                let segmentMode = settings.segmentInterpolations.first {
                    $0.startFrameID == leftAnchor.frame.id && $0.endFrameID == rightAnchor.frame.id
                }?.mode
                var parameters = Set(leftAnchor.keyframe.parameters.values.keys)
                    .union(rightAnchor.keyframe.parameters.values.keys)
                switch settings.missingValuePolicy {
                case .holdPrevious:
                    parameters.formUnion(anchors.flatMap { $0.keyframe.parameters.values.keys })
                case .useDefault:
                    parameters.formUnion(settings.parameterDefaults.keys)
                case .skip, .warn:
                    break
                }
                for parameter in parameters.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let definition = definitionsByParameter[parameter]
                    let strategy = segmentMode ?? definition?.interpolation ?? settings.defaultInterpolation
                    if strategy == .monotoneCubic {
                        throw InterpolationError.unsupportedStrategy(strategy)
                    }

                    let endpointValues = resolveEndpointValues(
                        parameter: parameter,
                        leftAnchorIndex: anchorIndex,
                        anchors: anchors,
                        settings: settings,
                        warnings: &warnings
                    )
                    guard let (startValue, endValue) = endpointValues else {
                        continue
                    }
                    try validate(startValue, parameter: parameter, definition: definition)
                    try validate(endValue, parameter: parameter, definition: definition)

                    for frame in intermediateFrames {
                        let segmentProgress = progress(
                            for: frame,
                            leftAnchor: leftAnchor.frame,
                            rightAnchor: rightAnchor.frame,
                            timeBasis: settings.timeBasis,
                            missingValuePolicy: settings.missingValuePolicy,
                            parameter: parameter,
                            warnings: &warnings
                        )
                        let value: Double
                        switch segmentProgress {
                        case .normalized(let progress):
                            value = try interpolate(
                                start: startValue,
                                end: endValue,
                                progress: progress,
                                strategy: strategy,
                                parameter: parameter
                            )
                        case .holdPrevious:
                            value = startValue
                        case .useDefault:
                            guard let defaultValue = settings.parameterDefaults[parameter] else {
                                warnings.append(missingParameterWarning(
                                    parameter,
                                    leftFrame: leftAnchor.frame,
                                    rightFrame: rightAnchor.frame
                                ))
                                continue
                            }
                            try validate(defaultValue, parameter: parameter, definition: definition)
                            value = defaultValue
                        case .skip:
                            continue
                        }
                        try validate(value, parameter: parameter, definition: definition)
                        var parameterSet = valuesByFrame[frame.id] ?? ParameterSet()
                        parameterSet.values[parameter] = ParameterSample(
                            value: value,
                            origin: .interpolated,
                            isLocked: false
                        )
                        valuesByFrame[frame.id] = parameterSet
                    }
                }
            }
        }

        try applyOverrides(
            overrides,
            framesByID: framesByID,
            keyframeFrameIDs: Set(anchors.map { $0.frame.id }),
            intermediateFrameIDs: intermediateFrameIDs,
            definitionsByParameter: definitionsByParameter,
            valuesByFrame: &valuesByFrame
        )

        return InterpolationResult(valuesByFrame: valuesByFrame, warnings: warnings)
    }

    private func indexFrames(_ frames: [ImageFrame]) throws -> [FrameID: ImageFrame] {
        var framesByID: [FrameID: ImageFrame] = [:]
        var sequenceIndices = Set<Int>()
        for frame in frames {
            guard framesByID[frame.id] == nil else {
                throw InterpolationError.duplicateFrameID(frame.id)
            }
            guard frame.sequenceIndex >= 0 else {
                throw InterpolationError.invalidSequenceIndex(frame.sequenceIndex)
            }
            guard sequenceIndices.insert(frame.sequenceIndex).inserted else {
                throw InterpolationError.duplicateSequenceIndex(frame.sequenceIndex)
            }
            framesByID[frame.id] = frame
        }
        return framesByID
    }

    private func indexDefinitions(
        _ definitions: [ParameterDefinition]
    ) throws -> [DevelopmentParameter: ParameterDefinition] {
        var definitionsByParameter: [DevelopmentParameter: ParameterDefinition] = [:]
        for definition in definitions {
            guard definitionsByParameter[definition.parameter] == nil else {
                throw InterpolationError.duplicateParameterDefinition(definition.parameter)
            }
            if let range = definition.validRange,
               (!range.lowerBound.isFinite || !range.upperBound.isFinite || range.lowerBound > range.upperBound) {
                throw InterpolationError.invalidParameterRange(definition.parameter)
            }
            definitionsByParameter[definition.parameter] = definition
        }
        return definitionsByParameter
    }

    private func indexKeyframes(
        _ keyframes: [Keyframe],
        framesByID: [FrameID: ImageFrame]
    ) throws -> [KeyframeAnchor] {
        var keyframeIDs = Set<UUID>()
        var keyframeFrameIDs = Set<FrameID>()
        var keyframeIDByFrameID: [FrameID: UUID] = [:]
        var anchors: [KeyframeAnchor] = []
        for keyframe in keyframes {
            guard keyframeIDs.insert(keyframe.id).inserted else {
                throw InterpolationError.duplicateKeyframeID(keyframe.id)
            }
            guard let frame = framesByID[keyframe.frameID] else {
                throw InterpolationError.missingKeyframeFrame(keyframe.frameID)
            }
            guard keyframeFrameIDs.insert(keyframe.frameID).inserted else {
                throw InterpolationError.duplicateKeyframePosition(keyframe.frameID)
            }
            guard frame.keyframeID == keyframe.id else {
                throw InterpolationError.inconsistentFrameKeyframeID(frame.id)
            }
            keyframeIDByFrameID[frame.id] = keyframe.id
            anchors.append(KeyframeAnchor(keyframe: keyframe, frame: frame))
        }
        for (frameID, frame) in framesByID {
            guard frame.keyframeID == keyframeIDByFrameID[frameID] else {
                throw InterpolationError.inconsistentFrameKeyframeID(frameID)
            }
        }
        return anchors.sorted { $0.frame.sequenceIndex < $1.frame.sequenceIndex }
    }

    private func keyframeValues(_ anchors: [KeyframeAnchor]) -> [FrameID: ParameterSet] {
        Dictionary(uniqueKeysWithValues: anchors.map { anchor in
            var keyframeSamples: [DevelopmentParameter: ParameterSample] = [:]
            for (parameter, sample) in anchor.keyframe.parameters.values {
                keyframeSamples[parameter] = ParameterSample(
                    value: sample.value,
                    origin: .keyframe,
                    isLocked: sample.isLocked
                )
            }
            return (anchor.frame.id, ParameterSet(values: keyframeSamples))
        })
    }

    private func resolveEndpointValues(
        parameter: DevelopmentParameter,
        leftAnchorIndex: Int,
        anchors: [KeyframeAnchor],
        settings: ProjectSettings,
        warnings: inout [ValidationIssue]
    ) -> (Double, Double)? {
        let leftFrame = anchors[leftAnchorIndex].frame
        let rightFrame = anchors[leftAnchorIndex + 1].frame
        let leftValue = anchors[leftAnchorIndex].keyframe.parameters.values[parameter]?.value
        let rightValue = anchors[leftAnchorIndex + 1].keyframe.parameters.values[parameter]?.value

        if let leftValue, let rightValue {
            return (leftValue, rightValue)
        }

        let previousValue = anchors[..<leftAnchorIndex].reversed().compactMap {
            $0.keyframe.parameters.values[parameter]?.value
        }.first
        let defaultValue = settings.parameterDefaults[parameter]
        switch settings.missingValuePolicy {
        case .skip:
            warnings.append(missingParameterWarning(parameter, leftFrame: leftFrame, rightFrame: rightFrame, severity: .info))
            return nil
        case .warn:
            warnings.append(missingParameterWarning(parameter, leftFrame: leftFrame, rightFrame: rightFrame))
            return nil
        case .holdPrevious:
            guard let heldValue = leftValue ?? previousValue else {
                warnings.append(missingParameterWarning(parameter, leftFrame: leftFrame, rightFrame: rightFrame))
                return nil
            }
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "missingParameterHeld",
                    message: "A missing endpoint for \(parameter.rawValue) is held at the previous value.",
                    frameID: leftFrame.id,
                    parameter: parameter
                )
            )
            return (leftValue ?? heldValue, rightValue ?? heldValue)
        case .useDefault:
            guard let defaultValue else {
                warnings.append(missingParameterWarning(parameter, leftFrame: leftFrame, rightFrame: rightFrame))
                return nil
            }
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "missingParameterDefaulted",
                    message: "A missing endpoint for \(parameter.rawValue) uses its explicit project default.",
                    frameID: leftFrame.id,
                    parameter: parameter
                )
            )
            return (leftValue ?? defaultValue, rightValue ?? defaultValue)
        }
    }

    private func progress(
        for frame: ImageFrame,
        leftAnchor: ImageFrame,
        rightAnchor: ImageFrame,
        timeBasis: TimeBasis,
        missingValuePolicy: MissingValuePolicy,
        parameter: DevelopmentParameter,
        warnings: inout [ValidationIssue]
    ) -> SegmentProgress {
        if timeBasis == .frameIndex {
            let duration = rightAnchor.sequenceIndex - leftAnchor.sequenceIndex
            guard duration > 0 else {
                return .skip
            }
            return .normalized(Double(frame.sequenceIndex - leftAnchor.sequenceIndex) / Double(duration))
        }

        guard let leftTime = leftAnchor.captureTime,
              let rightTime = rightAnchor.captureTime,
              let frameTime = frame.captureTime,
              rightTime > leftTime else {
                        let diagnosticSeverity: IssueSeverity = missingValuePolicy == .skip ? .info : .warning
            warnings.append(
                ValidationIssue(
                                        severity: diagnosticSeverity,
                    code: "captureTimeUnavailableForInterpolation",
                    message: "Capture-time interpolation is unavailable for this segment.",
                    frameID: frame.id,
                    parameter: parameter
                )
            )
            switch missingValuePolicy {
            case .holdPrevious:
                return .holdPrevious
            case .useDefault:
                return .useDefault
            case .skip, .warn:
                return .skip
            }
        }

        guard frameTime >= leftTime, frameTime <= rightTime else {
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "captureTimeOutsideKeyframes",
                    message: "Frame capture time falls outside its adjacent keyframe times.",
                    frameID: frame.id,
                    parameter: parameter
                )
            )
            return .skip
        }
        return .normalized(frameTime.timeIntervalSince(leftTime) / rightTime.timeIntervalSince(leftTime))
    }

    private func interpolate(
        start: Double,
        end: Double,
        progress: Double,
        strategy: ParameterInterpolation,
        parameter: DevelopmentParameter
    ) throws -> Double {
        guard progress.isFinite, (0.0...1.0).contains(progress) else {
            throw InterpolationError.invalidProgress(progress)
        }
        guard start.isFinite, end.isFinite else {
            throw InterpolationError.nonFiniteValue(parameter)
        }
        switch strategy {
        case .linear:
            return LinearInterpolation.value(start: start, end: end, progress: progress)
        case .smoothstep:
            return SmoothstepInterpolation.value(start: start, end: end, progress: progress)
        case .hold:
            return HoldInterpolation.value(start: start)
        case .monotoneCubic:
            throw InterpolationError.unsupportedStrategy(strategy)
        }
    }

    private func validate(
        _ value: Double,
        parameter: DevelopmentParameter,
        definition: ParameterDefinition?
    ) throws {
        guard value.isFinite else {
            throw InterpolationError.nonFiniteValue(parameter)
        }
        if let range = definition?.validRange, !range.contains(value) {
            throw InterpolationError.valueOutOfRange(parameter, value)
        }
    }

    private func applyOverrides(
        _ overrides: [ManualOverride],
        framesByID: [FrameID: ImageFrame],
        keyframeFrameIDs: Set<FrameID>,
        intermediateFrameIDs: Set<FrameID>,
        definitionsByParameter: [DevelopmentParameter: ParameterDefinition],
        valuesByFrame: inout [FrameID: ParameterSet]
    ) throws {
        var overrideKeys = Set<OverrideKey>()
        for override in overrides {
            guard framesByID[override.frameID] != nil else {
                throw InterpolationError.overrideReferencesMissingFrame(override.frameID)
            }
            guard !keyframeFrameIDs.contains(override.frameID) else {
                throw InterpolationError.overrideTargetsKeyframe(override.frameID)
            }
            guard intermediateFrameIDs.contains(override.frameID) else {
                throw InterpolationError.overrideOutsideInterpolationRange(override.frameID)
            }
            let key = OverrideKey(frameID: override.frameID, parameter: override.parameter)
            guard overrideKeys.insert(key).inserted else {
                throw InterpolationError.duplicateOverride(override.frameID, override.parameter)
            }
            try validate(
                override.value,
                parameter: override.parameter,
                definition: definitionsByParameter[override.parameter]
            )
            var parameterSet = valuesByFrame[override.frameID] ?? ParameterSet()
            parameterSet.values[override.parameter] = ParameterSample(
                value: override.value,
                origin: .manualOverride,
                isLocked: override.isLocked
            )
            valuesByFrame[override.frameID] = parameterSet
        }
    }

    private func missingParameterWarning(
        _ parameter: DevelopmentParameter,
        leftFrame: ImageFrame,
        rightFrame: ImageFrame,
        severity: IssueSeverity = .warning
    ) -> ValidationIssue {
        ValidationIssue(
            severity: severity,
            code: "keyframeParameterMissing",
            message: "A required endpoint value for \(parameter.rawValue) is missing.",
            frameID: leftFrame.id,
            parameter: parameter
        )
    }

    private struct KeyframeAnchor {
        let keyframe: Keyframe
        let frame: ImageFrame
    }

    private enum SegmentProgress {
        case normalized(Double)
        case holdPrevious
        case useDefault
        case skip
    }

    private struct OverrideKey: Hashable {
        let frameID: FrameID
        let parameter: DevelopmentParameter
    }
}