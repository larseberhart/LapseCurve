import Charts
import SwiftUI
import LapseCurveDomain

struct IntervalParameterGraphsView: View {
    let graphs: [SegmentParameterGraphModel]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], alignment: .leading, spacing: 18) {
            ForEach(graphs) { graph in
                ParameterGraphView(graph: graph)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct ParameterGraphView: View {
    let graph: SegmentParameterGraphModel
    @State private var hoveredPoint: SegmentParameterGraphModel.Point?

    private var startValue: String {
        graph.points.first(where: { $0.id == graph.startFrameID }).map { graph.formattedValue($0.value) } ?? "Unavailable"
    }

    private var endValue: String {
        graph.points.last(where: { $0.id == graph.endFrameID }).map { graph.formattedValue($0.value) } ?? "Unavailable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(graph.parameter.rawValue)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .help(graph.parameter.rawValue)

            HStack(spacing: 5) {
                Text(startValue)
                Image(systemName: "arrow.right")
                Text(endValue)
                Spacer(minLength: 4)
                Text(graph.mode.rawValue.capitalized)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(EditorPalette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            if graph.points.count >= 2 {
                chart
            } else {
                Text("Values unavailable")
                    .font(.caption)
                    .foregroundStyle(EditorPalette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 174, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hoveredPoint.map {
            "\(graph.parameter.rawValue), Frame \($0.frameNumber), \($0.filename), \(graph.formattedValue($0.value)), \(graph.mode.rawValue)"
        } ?? "\(graph.parameter.rawValue), frames \(Int(graph.frameDomain.lowerBound)) to \(Int(graph.frameDomain.upperBound)), \(graph.mode.rawValue)")
        .accessibilityValue(hoveredPoint.map {
            "Frame \($0.frameNumber), \($0.filename), \(graph.formattedValue($0.value))"
        } ?? "\(startValue) to \(endValue)")
        .accessibilityIdentifier("parameter-graph-\(graph.startFrameID.rawValue)-\(graph.parameter.rawValue)")
        .onChange(of: graph) { hoveredPoint = nil }
        .onDisappear { hoveredPoint = nil }
    }

    private var chart: some View {
        Chart {
            ForEach(graph.points) { point in
                LineMark(
                    x: .value("Frame", Double(point.frameNumber)),
                    y: .value(graph.parameter.rawValue, point.value),
                    series: .value("Run", point.run)
                )
                .interpolationMethod(graph.mode == .hold ? .stepEnd : .linear)
                .lineStyle(StrokeStyle(lineWidth: 1.7))
                .foregroundStyle(EditorPalette.accent)

                if point.isEndpoint || graph.points.count <= 16 {
                    PointMark(
                        x: .value("Frame", Double(point.frameNumber)),
                        y: .value(graph.parameter.rawValue, point.value)
                    )
                    .symbolSize(point.isEndpoint ? 32 : 9)
                    .foregroundStyle(point.isEndpoint ? Color.primary : EditorPalette.accent)
                }
            }
            if let hoveredPoint {
                RuleMark(x: .value("Frame", Double(hoveredPoint.frameNumber)))
                    .foregroundStyle(EditorPalette.secondaryText.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Frame", Double(hoveredPoint.frameNumber)),
                    y: .value(graph.parameter.rawValue, hoveredPoint.value)
                )
                .symbolSize(40)
                .foregroundStyle(EditorPalette.accent)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: graph.frameDomain, range: .plotDimension(padding: 5))
        .chartYScale(domain: graph.valueDomain)
        .chartXAxis {
            AxisMarks(values: [graph.frameDomain.lowerBound,
                ((graph.frameDomain.lowerBound + graph.frameDomain.upperBound) / 2).rounded(),
                graph.frameDomain.upperBound]) { value in
                AxisTick()
                if let number = value.as(Double.self) {
                    AxisValueLabel(anchor: number == graph.frameDomain.lowerBound ? .topLeading
                        : number == graph.frameDomain.upperBound ? .topTrailing : .top) {
                        Text(Int(number), format: .number)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(EditorPalette.separator.opacity(0.5))
                AxisValueLabel(anchor: .trailing)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard plot.contains(location),
                                          let frameNumber = proxy.value(atX: location.x - plot.minX, as: Double.self) else {
                                        hoveredPoint = nil
                                        return
                                    }
                                    hoveredPoint = graph.nearestPoint(to: frameNumber)
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }

                        if let hoveredPoint,
                           let position = proxy.position(forX: Double(hoveredPoint.frameNumber)) {
                            let width = min(210, geometry.size.width)
                            hoverLabel(hoveredPoint)
                                .frame(width: width, height: 64)
                                .offset(
                                    x: min(max(plot.minX + position - width / 2, 0), max(geometry.size.width - width, 0)),
                                    y: min(plot.minY + 3, max(geometry.size.height - 64, 0))
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    private func hoverLabel(_ point: SegmentParameterGraphModel.Point) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("Frame \(point.frameNumber)")
                Spacer(minLength: 2)
                Text(graph.formattedValue(point.value))
                    .monospacedDigit()
            }
            Text(point.filename)
                .truncationMode(.middle)
            Text(point.isEndpoint ? "Keyframe" : "Calculated")
                .foregroundStyle(EditorPalette.secondaryText)
        }
        .font(.caption2)
        .lineLimit(1)
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4).strokeBorder(EditorPalette.separator, lineWidth: 0.5)
        }
        .accessibilityIdentifier("parameter-graph-tooltip")
    }
}