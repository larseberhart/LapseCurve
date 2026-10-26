import Foundation
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveMetadata

nonisolated struct SegmentParameterGraphModel: Identifiable, Equatable, Sendable {
    struct Point: Identifiable, Equatable, Sendable {
        let id: FrameID
        let frameNumber: Int
        let filename: String
        let value: Double
        let origin: ParameterOrigin
        let isEndpoint: Bool
        let run: Int
    }

    let parameter: DevelopmentParameter
    let unit: ParameterUnit
    let mode: ParameterInterpolation
    let startFrameID: FrameID
    let endFrameID: FrameID
    let frameDomain: ClosedRange<Double>
    let points: [Point]
    let valueDomain: ClosedRange<Double>

    var id: DevelopmentParameter { parameter }

    var unitLabel: String {
        switch unit {
        case .exposureEV: "EV"
        case .temperatureKelvin: "K"
        case .tint: "tint"
        case .percent: "%"
        case .dimensionless: ""
        }
    }

    private static func valueDomain(for points: [Point]) -> ClosedRange<Double> {
        let minimum = points.map(\.value).min() ?? 0
        let maximum = points.map(\.value).max() ?? 0
        let padding = max((maximum - minimum) * 0.08, max(abs(minimum), abs(maximum)) * 0.01, 0.01)
        let lower = minimum - padding
        let upper = maximum + padding
        return (lower.isFinite ? lower : minimum)...(upper.isFinite ? upper : maximum)
    }

    func formattedValue(_ value: Double) -> String {
        let formatted = XMPFieldRegistry.formattedValue(value, for: parameter)
        return unitLabel.isEmpty ? formatted : "\(formatted) \(unitLabel)"
    }

    func nearestPoint(to frameNumber: Double) -> Point? {
        guard !points.isEmpty, frameNumber.isFinite else { return nil }
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Double(points[middle].frameNumber) < frameNumber {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return points.first }
        guard lower < points.count else { return points.last }
        let previous = points[lower - 1]
        let next = points[lower]
        return frameNumber - Double(previous.frameNumber) <= Double(next.frameNumber) - frameNumber ? previous : next
    }

    static func makeGraphs(
        for segment: InterpolationSegmentModel,
        result: InterpolationResult,
        settings: ProjectSettings,
        definitions: [ParameterDefinition]
    ) -> [Self] {
        guard !segment.intermediateFrames.isEmpty else { return [] }
        let frames = [segment.startFrame] + segment.intermediateFrames.sorted {
            $0.sequenceIndex < $1.sequenceIndex
        } + [segment.endFrame]
        let segmentMode = settings.segmentInterpolations.first {
            $0.startFrameID == segment.startFrame.id && $0.endFrameID == segment.endFrame.id
        }?.mode
        let definitionsByParameter = Dictionary(definitions.map { ($0.parameter, $0) }, uniquingKeysWith: { first, _ in first })
        return segment.interpolatedParameters.map { parameter in
            let definition = definitionsByParameter[parameter]
            var run = 0
            var points: [Point] = []
            points.reserveCapacity(frames.count)
            for frame in frames {
                guard let sample = result.valuesByFrame[frame.id]?.values[parameter], sample.value.isFinite else {
                    run += 1
                    continue
                }
                points.append(Point(
                    id: frame.id, frameNumber: frame.sequenceIndex + 1,
                    filename: URL(fileURLWithPath: frame.relativePath).lastPathComponent,
                    value: sample.value, origin: sample.origin,
                    isEndpoint: frame.id == segment.startFrame.id || frame.id == segment.endFrame.id,
                    run: run
                ))
            }
            return Self(
                parameter: parameter, unit: definition?.unit ?? .dimensionless,
                mode: segmentMode ?? definition?.interpolation ?? settings.defaultInterpolation,
                startFrameID: segment.startFrame.id, endFrameID: segment.endFrame.id,
                frameDomain: Double(segment.startFrame.sequenceIndex + 1)...Double(segment.endFrame.sequenceIndex + 1),
                points: points, valueDomain: valueDomain(for: points)
            )
        }
    }
}