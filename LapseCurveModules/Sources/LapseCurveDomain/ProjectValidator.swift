import Foundation

/// Validates decoded project values before editing, calculation or export.
public enum ProjectValidator {
    /// Validates project structure, references, dates and parameter values.
    /// - Parameters:
    ///   - project: Decoded project to validate.
    ///   - parameterDefinitions: Verified definitions used for range checks.
    /// - Throws: A specific `ProjectValidationError` for the first invalid value.
    public static func validate(
        _ project: TimeLapseProject,
        parameterDefinitions: [ParameterDefinition] = []
    ) throws {
        guard project.schemaVersion == ProjectSchema.currentVersion else {
            throw ProjectValidationError.unsupportedSchemaVersion(project.schemaVersion)
        }
        guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectValidationError.emptyProjectName
        }
        try validateDate(project.createdAt, field: "createdAt")
        try validateDate(project.modifiedAt, field: "modifiedAt")

        var framesByID: [FrameID: ImageFrame] = [:]
        var sequenceIndices = Set<Int>()
        for frame in project.frames {
            guard framesByID[frame.id] == nil else {
                throw ProjectValidationError.duplicateFrameID(frame.id)
            }
            guard frame.sequenceIndex >= 0 else {
                throw ProjectValidationError.invalidSequenceIndex(frame.sequenceIndex)
            }
            guard sequenceIndices.insert(frame.sequenceIndex).inserted else {
                throw ProjectValidationError.duplicateSequenceIndex(frame.sequenceIndex)
            }
            framesByID[frame.id] = frame
            if let captureTime = frame.captureTime {
                try validateDate(captureTime, field: "captureTime")
            }
            try validateFingerprint(frame.fileFingerprint)
            try validateCaptureMetadata(frame.captureMetadata, frameID: frame.id)
        }

        for (frameID, metadataBaseline) in project.metadataBaselines {
            guard framesByID[frameID] != nil else {
                throw ProjectValidationError.missingMetadataBaselineFrame(frameID)
            }
            try validateFingerprint(metadataBaseline.sourceFingerprint)
        }

        var definitionsByParameter: [DevelopmentParameter: ParameterDefinition] = [:]
        for definition in parameterDefinitions {
            guard definitionsByParameter[definition.parameter] == nil else {
                throw ProjectValidationError.duplicateParameterDefinition(definition.parameter)
            }
            if let range = definition.validRange,
               (!range.lowerBound.isFinite || !range.upperBound.isFinite || range.lowerBound > range.upperBound) {
                throw ProjectValidationError.invalidParameterRange(definition.parameter)
            }
            definitionsByParameter[definition.parameter] = definition
        }

        var keyframeIDs = Set<UUID>()
        var keyframesByFrameID: [FrameID: Keyframe] = [:]
        for keyframe in project.keyframes {
            guard keyframeIDs.insert(keyframe.id).inserted else {
                throw ProjectValidationError.duplicateKeyframeID(keyframe.id)
            }
            guard framesByID[keyframe.frameID] != nil else {
                throw ProjectValidationError.missingKeyframeFrame(keyframe.frameID)
            }
            guard keyframesByFrameID[keyframe.frameID] == nil else {
                throw ProjectValidationError.duplicateKeyframeForFrame(keyframe.frameID)
            }
            keyframesByFrameID[keyframe.frameID] = keyframe
            try validateParameterSet(keyframe.parameters, definitions: definitionsByParameter)
        }

        for frame in project.frames {
            let expectedKeyframeID = keyframesByFrameID[frame.id]?.id
            guard frame.keyframeID == expectedKeyframeID else {
                throw ProjectValidationError.inconsistentFrameKeyframeID(frame.id)
            }
        }

        let orderedKeyframes = project.keyframes.sorted {
            framesByID[$0.frameID]!.sequenceIndex < framesByID[$1.frameID]!.sequenceIndex
        }
        var segmentStarts = Set<FrameID>()
        for segment in project.settings.segmentInterpolations {
            guard segment.mode != .monotoneCubic,
                  segmentStarts.insert(segment.startFrameID).inserted,
                  zip(orderedKeyframes, orderedKeyframes.dropFirst()).contains(where: {
                      $0.0.frameID == segment.startFrameID && $0.1.frameID == segment.endFrameID
                  }) else {
                throw ProjectValidationError.invalidSegmentInterpolation(segment.startFrameID, segment.endFrameID)
            }
        }

        var overrideKeys = Set<OverrideKey>()
        for override in project.overrides {
            guard framesByID[override.frameID] != nil else {
                throw ProjectValidationError.missingOverrideFrame(override.frameID)
            }
            let key = OverrideKey(frameID: override.frameID, parameter: override.parameter)
            guard overrideKeys.insert(key).inserted else {
                throw ProjectValidationError.duplicateOverride(override.frameID, override.parameter)
            }
            try validateParameter(
                override.value,
                parameter: override.parameter,
                definitions: definitionsByParameter
            )
        }

        if let summary = project.lastScanSummary {
            let counts = [summary.photoCount, summary.keyframeCount, summary.unreadableRatingCount, summary.unsupportedFileCount]
            guard counts.allSatisfy({ $0 >= 0 }) else {
                throw ProjectValidationError.negativeScanCount
            }
            try validateDate(summary.scannedAt, field: "lastScanSummary.scannedAt")
        }
    }

    private static func validateParameterSet(
        _ parameterSet: ParameterSet,
        definitions: [DevelopmentParameter: ParameterDefinition]
    ) throws {
        for (parameter, sample) in parameterSet.values {
            try validateParameter(sample.value, parameter: parameter, definitions: definitions)
        }
    }

    private static func validateParameter(
        _ value: Double,
        parameter: DevelopmentParameter,
        definitions: [DevelopmentParameter: ParameterDefinition]
    ) throws {
        guard value.isFinite else {
            throw ProjectValidationError.nonFiniteParameter(parameter)
        }
        if let range = definitions[parameter]?.validRange, !range.contains(value) {
            throw ProjectValidationError.parameterOutOfRange(parameter, value)
        }
    }

    private static func validateCaptureMetadata(_ metadata: CaptureMetadata, frameID: FrameID) throws {
        let fields: [(String, Double?)] = [
            ("shutterDurationSeconds", metadata.shutterDurationSeconds),
            ("apertureFNumber", metadata.apertureFNumber),
            ("iso", metadata.iso)
        ]
        for (field, value) in fields {
            if let value, (!value.isFinite || value <= 0) {
                throw ProjectValidationError.invalidCaptureMetadata(frameID, field)
            }
        }
    }

    private static func validateFingerprint(_ fingerprint: FileFingerprint?) throws {
        guard let fingerprint else {
            return
        }
        guard fingerprint.byteCount >= 0 else {
            throw ProjectValidationError.invalidFileSize(fingerprint.byteCount)
        }
        if let modificationDate = fingerprint.modificationDate {
            try validateDate(modificationDate, field: "fileFingerprint.modificationDate")
        }
    }

    private static func validateDate(_ date: Date, field: String) throws {
        guard date.timeIntervalSince1970.isFinite else {
            throw ProjectValidationError.invalidDate(field)
        }
    }

    private struct OverrideKey: Hashable {
        let frameID: FrameID
        let parameter: DevelopmentParameter
    }
}