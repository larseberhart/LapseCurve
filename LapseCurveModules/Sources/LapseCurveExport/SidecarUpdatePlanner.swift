import Foundation
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveMetadata

/// Builds a read-only update plan for existing intermediate-frame XMP sidecars.
public struct SidecarUpdatePlanner: Sendable {
    private let packetReader: XMPPacketReader

    /// Creates a planner with a bounded XMP parser.
    public init(maximumPacketSizeBytes: Int = 16 * 1024 * 1024) {
        packetReader = XMPPacketReader(maximumPacketSizeBytes: maximumPacketSizeBytes)
    }

    /// Preflights frames without creating files or changing metadata.
    ///
    /// Only frames strictly between consecutive keyframes are considered. Keyframe records,
    /// frame ratings, packet ratings, conflicts and missing sidecars all fail closed.
    public func makePlan(
        frames: [ImageFrame],
        keyframes: [Keyframe],
        interpolation: InterpolationResult,
        existingSidecars: [FrameID: ExistingSidecarSnapshot],
        parameterDefinitions: [ParameterDefinition]
    ) -> SidecarUpdatePlan {
        let framesByID = Dictionary(frames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let definitionsByParameter = Dictionary(
            parameterDefinitions.map { ($0.parameter, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let keyframeIDs = Set(keyframes.map(\.frameID))
        let orderedKeyframes = keyframes.compactMap { keyframe -> (keyframe: Keyframe, frame: ImageFrame)? in
            guard let frame = framesByID[keyframe.frameID] else {
                return nil
            }
            return (keyframe, frame)
        }
        .sorted { $0.frame.sequenceIndex < $1.frame.sequenceIndex }

        var intermediateFrameIDs = Set<FrameID>()
        var segmentByFrameID: [FrameID: (left: Keyframe, right: Keyframe)] = [:]
        if orderedKeyframes.count > 1 {
            for anchorIndex in 0..<(orderedKeyframes.count - 1) {
                let leftIndex = orderedKeyframes[anchorIndex].frame.sequenceIndex
                let rightIndex = orderedKeyframes[anchorIndex + 1].frame.sequenceIndex
                let segmentFrameIDs = frames
                    .filter { $0.sequenceIndex > leftIndex && $0.sequenceIndex < rightIndex }
                    .map(\.id)
                intermediateFrameIDs.formUnion(segmentFrameIDs)
                for frameID in segmentFrameIDs {
                    segmentByFrameID[frameID] = (
                        orderedKeyframes[anchorIndex].keyframe,
                        orderedKeyframes[anchorIndex + 1].keyframe
                    )
                }
            }
        }

        var updates: [PlannedSidecarUpdate] = []
        var warnings: [ValidationIssue] = []
        for frame in frames.sorted(by: { $0.sequenceIndex < $1.sequenceIndex }) {
            if keyframeIDs.contains(frame.id) || frame.keyframeID != nil || frame.rating == 1 {
                continue
            }
            guard intermediateFrameIDs.contains(frame.id),
                  let parameterSet = interpolation.valuesByFrame[frame.id] else {
                continue
            }
            guard frame.metadataStatus != .conflict else {
                warnings.append(issue(
                    "frameMetadataConflict",
                    "Conflicting frame metadata must be reloaded before sidecar updates.",
                    frameID: frame.id
                ))
                continue
            }
            guard let sidecar = existingSidecars[frame.id] else {
                warnings.append(issue(
                    "xmpSidecarMissing",
                    "No Lightroom-generated sidecar exists; this frame is skipped and no XMP will be created.",
                    frameID: frame.id
                ))
                continue
            }
            guard sidecar.frameID == frame.id,
                  sidecar.url.pathExtension.lowercased() == "xmp" else {
                warnings.append(issue(
                    "xmpSidecarInvalidAssociation",
                    "Sidecar snapshot does not match this frame or is not an XMP file.",
                    frameID: frame.id
                ))
                continue
            }

            let packet: XMPPacket
            do {
                packet = try packetReader.read(sidecar.data)
            } catch {
                warnings.append(issue(
                    "xmpSidecarUnreadable",
                    "Existing XMP sidecar is unreadable; this frame is skipped.",
                    frameID: frame.id
                ))
                continue
            }

            let ratingValues = packet.properties.filter {
                $0.namespaceURI == "http://ns.adobe.com/xap/1.0/" && $0.localName == "Rating"
            }.compactMap { Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if ratingValues.contains(1) {
                warnings.append(issue(
                    "keyframeSidecarImmutable",
                    "XMP packet rating identifies a keyframe; it is excluded from all updates.",
                    frameID: frame.id
                ))
                continue
            }
            if Set(ratingValues).count > 1 {
                warnings.append(issue(
                    "xmpRatingConflict",
                    "XMP packet contains conflicting ratings; this frame is skipped.",
                    frameID: frame.id
                ))
                continue
            }

            let currentValues = XMPFieldRegistry.developmentValues(in: packet, definitions: parameterDefinitions).parameters
            let segment = segmentByFrameID[frame.id]
            var writableValues: [DevelopmentParameter: Double] = [:]
            for (parameter, sample) in parameterSet.values {
                if XMPFieldRegistry.parametersWithoutDefault.contains(parameter),
                   sample.origin == .interpolated,
                   segment?.left.parameters.values[parameter]?.origin == .asShot,
                   segment?.right.parameters.values[parameter]?.origin == .asShot {
                    // Both key photos are As Shot, so each intermediate keeps its own camera white balance.
                    continue
                }
                guard let definition = definitionsByParameter[parameter] else {
                    // Outside the allowed field list; never written.
                    continue
                }
                guard definition.writable else {
                    warnings.append(issue(
                        "parameterWriteNotApproved",
                        "No writable mapping is enabled for \(parameter.rawValue); the field is skipped.",
                        frameID: frame.id,
                        parameter: parameter
                    ))
                    continue
                }
                guard sample.value.isFinite,
                      definition.validRange?.contains(sample.value) ?? true else {
                    warnings.append(issue(
                        "parameterValueInvalid",
                        "Value for \(parameter.rawValue) is non-finite or outside its configured range.",
                        frameID: frame.id,
                        parameter: parameter
                    ))
                    continue
                }
                let plannedText = XMPFieldRegistry.formattedValue(sample.value, for: parameter)
                if let currentValue = currentValues.values[parameter]?.value {
                    if XMPFieldRegistry.formattedValue(currentValue, for: parameter) == plannedText {
                        continue
                    }
                }
                writableValues[parameter] = sample.value
            }

            if !writableValues.isEmpty {
                updates.append(
                    PlannedSidecarUpdate(frame: frame, sidecar: sidecar, values: writableValues)
                )
            }
        }

        return SidecarUpdatePlan(updates: updates, warnings: warnings)
    }

    private func issue(
        _ code: String,
        _ message: String,
        frameID: FrameID,
        parameter: DevelopmentParameter? = nil
    ) -> ValidationIssue {
        ValidationIssue(
            severity: .warning,
            code: code,
            message: message,
            frameID: frameID,
            parameter: parameter
        )
    }
}