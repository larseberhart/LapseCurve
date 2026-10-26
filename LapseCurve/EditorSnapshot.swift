import Foundation
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveExport
import LapseCurveMetadata

nonisolated struct EditorSnapshot: Sendable {
    let result: InterpolationResult
    let framesByID: [FrameID: ImageFrame]
    let orderedKeyframes: [Keyframe]
    let keyframeIDs: Set<FrameID>
    let segments: [InterpolationSegmentModel]
    let graphs: [FrameID: [SegmentParameterGraphModel]]
    let interpolatedParametersByFrameID: [FrameID: Set<DevelopmentParameter>]
    let eligibleFrameCount: Int

    init(project: TimeLapseProject, definitions: [ParameterDefinition]) throws {
        try Task.checkCancellation()
        try ProjectValidator.validate(project, parameterDefinitions: definitions)
        let result = try InterpolationEngine().calculate(
            frames: project.frames, keyframes: project.keyframes, overrides: [],
            settings: project.settings, parameterDefinitions: definitions
        )
        let framesByID = Dictionary(uniqueKeysWithValues: project.frames.map { ($0.id, $0) })
        let orderedFrames = project.frames.sorted { $0.sequenceIndex < $1.sequenceIndex }
        let keyframes = project.keyframes.sorted {
            framesByID[$0.frameID]!.sequenceIndex < framesByID[$1.frameID]!.sequenceIndex
        }
        let warningsByFrame = Dictionary(grouping: result.warnings.compactMap { warning in
            warning.frameID.map { ($0, warning) }
        }, by: { $0.0 })
        var segments: [InterpolationSegmentModel] = []
        var graphs: [FrameID: [SegmentParameterGraphModel]] = [:]
        var parametersByFrame: [FrameID: Set<DevelopmentParameter>] = [:]
        var eligibleFrameCount = 0
        var cursor = 0

        for (start, end) in zip(keyframes, keyframes.dropFirst()) {
            try Task.checkCancellation()
            let startFrame = framesByID[start.frameID]!
            let endFrame = framesByID[end.frameID]!
            while cursor < orderedFrames.count && orderedFrames[cursor].sequenceIndex <= startFrame.sequenceIndex {
                cursor += 1
            }
            let firstIntermediate = cursor
            while cursor < orderedFrames.count && orderedFrames[cursor].sequenceIndex < endFrame.sequenceIndex {
                cursor += 1
            }
            let intermediateFrames = Array(orderedFrames[firstIntermediate..<cursor])
            let sharedParameters = Set(start.parameters.values.keys).intersection(end.parameters.values.keys)
            let changedParameters = sharedParameters.filter { parameter in
                guard let left = start.parameters.values[parameter], let right = end.parameters.values[parameter] else { return false }
                if left.origin == .asShot && right.origin == .asShot { return false }
                return XMPFieldRegistry.formattedValue(left.value, for: parameter)
                    != XMPFieldRegistry.formattedValue(right.value, for: parameter)
            }.sorted { $0.rawValue < $1.rawValue }
            let segment = InterpolationSegmentModel(
                startKeyframe: start, endKeyframe: end, startFrame: startFrame, endFrame: endFrame,
                intermediateFrames: intermediateFrames, sharedParameters: sharedParameters,
                interpolatedParameters: changedParameters,
                unavailableParameters: Set(start.parameters.values.keys).union(end.parameters.values.keys).subtracting(sharedParameters),
                warnings: intermediateFrames.flatMap { warningsByFrame[$0.id, default: []].map { $0.1 } }
            )
            segments.append(segment)
            graphs[start.frameID] = SegmentParameterGraphModel.makeGraphs(
                for: segment, result: result, settings: project.settings, definitions: definitions
            )
            eligibleFrameCount += intermediateFrames.count
            if !intermediateFrames.isEmpty {
                for frame in [startFrame] + intermediateFrames + [endFrame] {
                    parametersByFrame[frame.id, default: []].formUnion(changedParameters)
                }
            }
        }
        self.result = result
        self.framesByID = framesByID
        orderedKeyframes = keyframes
        keyframeIDs = Set(keyframes.map(\.frameID))
        self.segments = segments
        self.graphs = graphs
        interpolatedParametersByFrameID = parametersByFrame
        self.eligibleFrameCount = eligibleFrameCount
    }
}

actor EditorComputation {
    func snapshot(for project: TimeLapseProject, definitions: [ParameterDefinition]) throws -> EditorSnapshot {
        try EditorSnapshot(project: project, definitions: definitions)
    }

    func preflight(
        project: TimeLapseProject,
        result: InterpolationResult,
        sidecarURLs: [FrameID: URL],
        definitions: [ParameterDefinition]
    ) throws -> SidecarUpdatePlan {
        try Task.checkCancellation()
        var sidecars: [FrameID: ExistingSidecarSnapshot] = [:]
        for (frameID, metadata) in project.metadataBaselines {
            guard let url = sidecarURLs[frameID] else { continue }
            sidecars[frameID] = ExistingSidecarSnapshot(
                frameID: frameID, url: url, data: metadata.data,
                fingerprint: metadata.sourceFingerprint
                    ?? FileFingerprint(byteCount: Int64(metadata.data.count), modificationDate: nil, digest: nil)
            )
        }
        let plan = SidecarUpdatePlanner().makePlan(
            frames: project.frames, keyframes: project.keyframes, interpolation: result,
            existingSidecars: sidecars, parameterDefinitions: definitions
        )
        try Task.checkCancellation()
        return plan
    }
}