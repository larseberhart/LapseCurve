import Foundation
import LapseCurveDomain

/// Invalid engine input that prevents deterministic interpolation.
public enum InterpolationError: Error, Equatable, LocalizedError, Sendable {
    case duplicateFrameID(FrameID)
    case invalidSequenceIndex(Int)
    case duplicateSequenceIndex(Int)
    case duplicateKeyframeID(UUID)
    case missingKeyframeFrame(FrameID)
    case duplicateKeyframePosition(FrameID)
    case inconsistentFrameKeyframeID(FrameID)
    case duplicateParameterDefinition(DevelopmentParameter)
    case invalidParameterRange(DevelopmentParameter)
    case nonFiniteValue(DevelopmentParameter)
    case invalidProgress(Double)
    case valueOutOfRange(DevelopmentParameter, Double)
    case unsupportedStrategy(ParameterInterpolation)
    case overrideReferencesMissingFrame(FrameID)
    case overrideTargetsKeyframe(FrameID)
    case overrideOutsideInterpolationRange(FrameID)
    case duplicateOverride(FrameID, DevelopmentParameter)

    /// Human-readable explanation for invalid calculation input.
    public var errorDescription: String? {
        switch self {
        case .duplicateFrameID:
            "Input contains a duplicate frame identity."
        case .invalidSequenceIndex(let index):
            "Sequence index \(index) must not be negative."
        case .duplicateSequenceIndex(let index):
            "More than one frame uses sequence index \(index)."
        case .duplicateKeyframeID:
            "Input contains a duplicate keyframe identity."
        case .missingKeyframeFrame:
            "A keyframe refers to a missing frame."
        case .duplicateKeyframePosition(let frameID):
            "More than one keyframe occupies frame \(frameID.rawValue)."
        case .inconsistentFrameKeyframeID:
            "Frame and keyframe records disagree about keyframe identity."
        case .duplicateParameterDefinition(let parameter):
            "More than one definition exists for \(parameter.rawValue)."
        case .invalidParameterRange(let parameter):
            "The verified range for \(parameter.rawValue) is invalid."
        case .nonFiniteValue(let parameter):
            "A value for \(parameter.rawValue) is not finite."
        case .invalidProgress(let progress):
            "Interpolation progress \(progress) must be finite and between zero and one."
        case .valueOutOfRange(let parameter, let value):
            "Value \(value) is outside the verified range for \(parameter.rawValue)."
        case .unsupportedStrategy(let strategy):
            "Interpolation strategy \(strategy.rawValue) is not implemented."
        case .overrideReferencesMissingFrame:
            "A manual override refers to a missing frame."
        case .overrideTargetsKeyframe:
            "Keyframe values are authoritative; overrides cannot target keyframes."
        case .overrideOutsideInterpolationRange:
            "Overrides are supported only between consecutive keyframes."
        case .duplicateOverride:
            "A frame has multiple overrides for the same parameter."
        }
    }
}