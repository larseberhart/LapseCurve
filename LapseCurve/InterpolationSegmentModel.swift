import Foundation
import LapseCurveDomain

nonisolated struct InterpolationSegmentModel: Identifiable, Sendable {
    let startKeyframe: Keyframe
    let endKeyframe: Keyframe
    let startFrame: ImageFrame
    let endFrame: ImageFrame
    let intermediateFrames: [ImageFrame]
    let sharedParameters: Set<DevelopmentParameter>
    /// Shared parameters whose key-photo values differ, i.e. those that will actually change.
    let interpolatedParameters: [DevelopmentParameter]
    let unavailableParameters: Set<DevelopmentParameter>
    let warnings: [ValidationIssue]

    var id: UUID { startKeyframe.id }
}
