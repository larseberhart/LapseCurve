import Foundation

/// Specific invalid-project condition that prevents loading or export.
public enum ProjectValidationError: Error, Equatable, LocalizedError, Sendable {
    /// The document schema is not supported by this build.
    case unsupportedSchemaVersion(Int)
    /// The user-visible project name is empty.
    case emptyProjectName
    /// A frame identity occurs more than once.
    case duplicateFrameID(FrameID)
    /// A frame sequence index is negative.
    case invalidSequenceIndex(Int)
    /// Two frames occupy the same sequence index.
    case duplicateSequenceIndex(Int)
    /// A keyframe identity occurs more than once.
    case duplicateKeyframeID(UUID)
    /// A keyframe refers to a frame that is absent from the project.
    case missingKeyframeFrame(FrameID)
    case missingMetadataBaselineFrame(FrameID)
    /// More than one keyframe refers to the same frame.
    case duplicateKeyframeForFrame(FrameID)
    /// The frame's optional keyframe identity disagrees with the keyframe list.
    case inconsistentFrameKeyframeID(FrameID)
    /// An override refers to a frame absent from the project.
    case missingOverrideFrame(FrameID)
    /// A frame has multiple overrides for one parameter.
    case duplicateOverride(FrameID, DevelopmentParameter)
    /// Multiple range definitions exist for one parameter.
    case duplicateParameterDefinition(DevelopmentParameter)
    /// A parameter range is non-finite or reversed.
    case invalidParameterRange(DevelopmentParameter)
    /// A stored parameter value is NaN or infinite.
    case nonFiniteParameter(DevelopmentParameter)
    /// A stored parameter value is outside its verified inclusive range.
    case parameterOutOfRange(DevelopmentParameter, Double)
    /// Capture metadata contains a non-finite or nonpositive value.
    case invalidCaptureMetadata(FrameID, String)
    /// A file fingerprint has a negative byte count.
    case invalidFileSize(Int64)
    /// A stored date has a non-finite timestamp.
    case invalidDate(String)
    /// A scan summary contains a negative count.
    case negativeScanCount
    case invalidSegmentInterpolation(FrameID, FrameID)

    /// Human-readable explanation suitable for diagnostics and tests.
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Project schema version \(version) is not supported."
        case .emptyProjectName:
            "Project name must not be empty."
        case .duplicateFrameID:
            "Project contains a duplicate frame identifier."
        case .invalidSequenceIndex(let index):
            "Sequence index \(index) must not be negative."
        case .duplicateSequenceIndex(let index):
            "More than one frame uses sequence index \(index)."
        case .duplicateKeyframeID:
            "Project contains a duplicate keyframe identifier."
        case .missingKeyframeFrame:
            "A keyframe refers to a frame that does not exist."
        case .missingMetadataBaselineFrame:
            "An imported metadata baseline refers to a frame that does not exist."
        case .duplicateKeyframeForFrame:
            "A frame has more than one keyframe."
        case .inconsistentFrameKeyframeID:
            "Frame and keyframe records disagree about keyframe identity."
        case .missingOverrideFrame:
            "A manual override refers to a frame that does not exist."
        case .duplicateOverride:
            "A frame has duplicate overrides for the same parameter."
        case .duplicateParameterDefinition:
            "More than one definition exists for the same parameter."
        case .invalidParameterRange:
            "A parameter definition has an invalid numeric range."
        case .nonFiniteParameter:
            "A parameter value must be finite."
        case .parameterOutOfRange(let parameter, let value):
            "Value \(value) is outside the verified range for \(parameter.rawValue)."
        case .invalidCaptureMetadata(let frameID, let field):
            "Capture metadata field \(field) is invalid for frame \(frameID.rawValue)."
        case .invalidFileSize:
            "File fingerprint byte count must not be negative."
        case .invalidDate(let field):
            "Date field \(field) must be finite."
        case .negativeScanCount:
            "Sequence scan counts must not be negative."
        case .invalidSegmentInterpolation:
            "Segment curves must be unique, use a supported mode, and connect consecutive keyframes."
        }
    }
}