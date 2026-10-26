import AppKit
import SwiftUI
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveMetadata
import LapseCurvePreview

struct KeyframeSequenceListView: View {
    let model: AppModel

    var body: some View {
        let segments = model.interpolationSegments
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.isScanning && model.frames.isEmpty {
                    ContentUnavailableView("Scanning Sequence", systemImage: "photo.stack", description: Text(model.statusMessage))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if model.frames.isEmpty {
                    ContentUnavailableView(
                        model.folderName == nil ? "Choose a Working Folder" : "No Supported Photos",
                        systemImage: model.folderName == nil ? "folder" : "photo.stack",
                        description: Text(model.statusMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else if model.orderedKeyframes.isEmpty {
                    ContentUnavailableView(
                        "No Key Photos Found",
                        systemImage: "star.slash",
                        description: Text("No photo has a readable one-star Lightroom XMP rating.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(Array(model.orderedKeyframes.enumerated()), id: \.element.id) { index, keyframe in
                        if let frame = model.frame(for: keyframe.frameID) {
                            KeyframeRowView(
                                frame: frame,
                                keyframe: keyframe,
                                isSelected: model.selectedFrameID == frame.id,
                                thumbnail: model.keyframeThumbnails[frame.id],
                                thumbnailFailure: model.keyframeThumbnailFailures[frame.id],
                                onSelect: { model.selectFrame(frame.id) },
                                loadThumbnail: { await model.loadKeyframeThumbnail(frame.id) }
                            )
                            .padding(.horizontal, 18)
                            .padding(.top, index == 0 ? 16 : 0)

                            if index < segments.count {
                                let segment = segments[index]
                                InterpolationSegmentView(
                                    segment: segment,
                                    model: model
                                )
                                .padding(.leading, 54)
                                .padding(.trailing, 18)

                                if let graphs = model.parameterGraphs[segment.startFrame.id], !graphs.isEmpty {
                                    IntervalParameterGraphsView(graphs: graphs)
                                        .padding(.leading, 69)
                                        .padding(.trailing, 18)
                                        .padding(.bottom, 12)
                                }
                            }
                        }
                    }

                    if model.outOfInterpolationRangeCount > 0 {
                        Label(
                            "\(model.outOfInterpolationRangeCount) photo(s) outside the first/last key-photo range are not extrapolated.",
                            systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                        )
                        .font(.caption)
                        .foregroundStyle(EditorPalette.secondaryText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .accessibilityIdentifier("no-extrapolation-note")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(EditorPalette.window)
        .accessibilityIdentifier("keyframe-sequence-list")
    }
}

private struct KeyframeRowView: View {
    let frame: ImageFrame
    let keyframe: Keyframe
    let isSelected: Bool
    let thumbnail: PreviewImage?
    let thumbnailFailure: String?
    let onSelect: () -> Void
    let loadThumbnail: () async -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 13) {
                thumbnailView
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(URL(fileURLWithPath: frame.relativePath).lastPathComponent)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("KEY PHOTO")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(EditorPalette.accent)
                        Spacer(minLength: 0)
                        Text(String(format: "%04d", frame.sequenceIndex + 1))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(EditorPalette.secondaryText)
                    }

                    Text(captureSummary)
                        .font(.caption)
                        .foregroundStyle(EditorPalette.secondaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(ratingSourceLabel, systemImage: "star.fill")
                            .foregroundStyle(EditorPalette.accent)
                        Text("·")
                        Text(parameterSummary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if frame.metadataStatus != .valid {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(EditorPalette.secondaryText)
                                .help("Some metadata is incomplete or conflicted.")
                        }
                        if let thumbnailFailure {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(EditorPalette.secondaryText)
                                .help(thumbnailFailure)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? EditorPalette.accent.opacity(0.10) : EditorPalette.panel)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? EditorPalette.accent : Color.clear)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("key-photo-\(frame.sequenceIndex)")
        .accessibilityLabel("Key photo \(frame.sequenceIndex + 1), \(URL(fileURLWithPath: frame.relativePath).lastPathComponent), rating from \(ratingSourceLabel)")
        .task(id: frame.id) { await loadThumbnail() }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail, let image = NSImage(data: thumbnail.data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel("Key photo thumbnail")
        } else if thumbnailFailure != nil {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(EditorPalette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EditorPalette.insetPanel)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EditorPalette.insetPanel)
        }
    }

    private var captureSummary: String {
        var values: [String] = []
        if let captureTime = frame.captureTime {
            values.append(captureTime.formatted(date: .abbreviated, time: .shortened))
        }
        if let shutter = frame.captureMetadata.shutterDurationSeconds {
            values.append(shutter >= 1 ? String(format: "%.1f s", shutter) : String(format: "1/%.0f s", 1 / shutter))
        }
        if let aperture = frame.captureMetadata.apertureFNumber {
            values.append(String(format: "f/%.1f", aperture))
        }
        if let iso = frame.captureMetadata.iso {
            values.append(String(format: "ISO %.0f", iso))
        }
        if let focalLength = frame.captureMetadata.focalLengthMM {
            values.append(String(format: "%.0f mm", focalLength))
        }
        return values.isEmpty ? "Capture EXIF unavailable" : values.joined(separator: "  ·  ")
    }

    private var parameterSummary: String {
        let values = keyframe.parameters.values.sorted { $0.key.rawValue < $1.key.rawValue }
        guard !values.isEmpty else { return "No readable Camera Raw corrections" }
        let explicitNonzeroValues = values.filter { $0.value.origin != .assumedNeutral && abs($0.value.value) > 0.000_001 }
        guard !explicitNonzeroValues.isEmpty else {
            return values.contains(where: { $0.value.origin == .assumedNeutral })
                ? "No crs values; neutral adjustments assumed"
                : "Camera Raw corrections neutral"
        }
        let summary = explicitNonzeroValues.map { parameter, sample in
            "\(parameter.rawValue) \(sample.value.formatted(.number.precision(.fractionLength(0...2)).sign(strategy: .always())))"
        }.joined(separator: "  ·  ")
        return values.contains(where: { $0.value.origin == .assumedNeutral })
            ? "\(summary)  ·  other adjustments neutral"
            : summary
    }

    private var ratingSourceLabel: String {
        switch frame.ratingSource {
        case .xmpSidecar: return "XMP rating"
        case .embeddedMetadata: return "embedded rating"
        case .unavailable: return "rating unknown"
        }
    }
}

private struct InterpolationSegmentView: View {
    let segment: InterpolationSegmentModel
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if let firstIntermediate = segment.intermediateFrames.first {
                    model.selectFrame(firstIntermediate.id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.right")
                            .foregroundStyle(EditorPalette.accent)
                        Text("INTERPOLATION")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EditorPalette.accent)
                        Text("\(segment.intermediateFrames.count) intermediate photo(s)")
                            .font(.caption)
                            .foregroundStyle(EditorPalette.secondaryText)
                        Spacer(minLength: 0)
                        Text("\(segment.startFrame.sequenceIndex + 1)–\(segment.endFrame.sequenceIndex + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(EditorPalette.secondaryText)
                    }

                    HStack(spacing: 6) {
                        Text(URL(fileURLWithPath: segment.startFrame.relativePath).lastPathComponent)
                        Image(systemName: "arrow.right")
                        Text(URL(fileURLWithPath: segment.endFrame.relativePath).lastPathComponent)
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(segment.intermediateFrames.isEmpty)
            .accessibilityIdentifier("interpolation-segment-\(segment.startFrame.sequenceIndex)")
            .accessibilityLabel("Interpolation from frame \(segment.startFrame.sequenceIndex + 1) to \(segment.endFrame.sequenceIndex + 1), \(segment.intermediateFrames.count) intermediate photos")

            Picker("Curve", selection: Binding(
                get: { model.segmentInterpolation(for: segment) },
                set: { mode in Task { await model.setSegmentInterpolation(mode, for: segment) } }
            )) {
                Text("Default").tag(ParameterInterpolation?.none)
                Text("Linear").tag(ParameterInterpolation?.some(.linear))
                Text("Smoothstep").tag(ParameterInterpolation?.some(.smoothstep))
                Text("Hold").tag(ParameterInterpolation?.some(.hold))
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 240, alignment: .leading)
            .disabled(segment.intermediateFrames.isEmpty || model.isScanning || model.isExecutingSidecarUpdates)
            .accessibilityIdentifier("interpolation-curve-\(segment.startFrame.sequenceIndex)")
            .accessibilityLabel("Curve from frame \(segment.startFrame.sequenceIndex + 1) to \(segment.endFrame.sequenceIndex + 1)")

            if segment.interpolatedParameters.isEmpty {
                Text("No parameters change between these key photos")
                    .font(.caption2)
                    .foregroundStyle(EditorPalette.secondaryText)
            }

            if !segment.unavailableParameters.isEmpty {
                Text("Unavailable at one endpoint: \(segment.unavailableParameters.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if !segment.warnings.isEmpty {
                Label("\(segment.warnings.count) interpolation warning(s)", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(EditorPalette.secondaryText)
                    .help(segment.warnings.map(\.message).joined(separator: "\n"))
            }
        }
        .padding(.leading, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorPalette.insetPanel.opacity(0.65))
        .overlay(alignment: .leading) {
            Rectangle().fill(EditorPalette.accent.opacity(0.45)).frame(width: 2)
        }
        .padding(.vertical, 4)
    }

}
