import SwiftUI
import LapseCurveDomain

struct MetadataInspectorView: View {
    let model: AppModel
    @State private var selectedSection: InspectorSection = .frame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Inspector", selection: $selectedSection) {
                ForEach(InspectorSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
                    case .frame:
                        frameInspector
                    case .development:
                        developmentInspector
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(EditorPalette.panel)
    }

    private var frameInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FRAME")
                .font(.caption.weight(.semibold))
                .foregroundStyle(EditorPalette.secondaryText)

            if let frame = model.selectedFrame {
                Text(URL(fileURLWithPath: frame.relativePath).lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .textSelection(.enabled)

                if model.keyframeIDs.contains(frame.id) {
                    Label("Keyframe · read only", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(EditorPalette.accent)
                        .accessibilityIdentifier("keyframe-read-only")
                }

                inspectorGroup("CAPTURE") {
                    valueRow("Capture time", value: frame.captureTime.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unavailable")
                    valueRow("Shutter", value: frame.captureMetadata.shutterDurationSeconds.map { "1/\(Int((1 / $0).rounded())) s" } ?? "Unavailable")
                    valueRow("Aperture", value: frame.captureMetadata.apertureFNumber.map { String(format: "f/%.1f", $0) } ?? "Unavailable")
                    valueRow("ISO", value: frame.captureMetadata.iso.map { String(format: "%.0f", $0) } ?? "Unavailable")
                }

                inspectorGroup("METADATA") {
                    valueRow("Rating", value: frame.rating.map(String.init) ?? "Unavailable")
                    valueRow("Rating source", value: String(describing: frame.ratingSource))
                    valueRow("Read status", value: String(describing: frame.metadataStatus))
                }
            } else {
                ContentUnavailableView(
                    "No Frame Selected",
                    systemImage: "viewfinder",
                    description: Text("Select a sequence frame to inspect its metadata.")
                )
                .frame(minHeight: 170)
            }
        }
    }

    private var developmentInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DEVELOPMENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(EditorPalette.secondaryText)

            if let frame = model.selectedFrame {
                let isKeyframe = model.keyframeIDs.contains(frame.id)
                let interpolatedParameters = model.selectedInterpolatedParameters
                if model.selectedParameters.values.isEmpty {
                    ContentUnavailableView(
                        "No Camera Raw Values",
                        systemImage: "slider.horizontal.3",
                        description: Text("No values are available at this frame. Missing endpoint data is not inferred.")
                    )
                    .frame(minHeight: 120)
                } else {
                    inspectorGroup(isKeyframe ? "KEY-PHOTO CORRECTIONS" : "INTERPOLATED CORRECTIONS") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(Array(model.selectedParameters.values.sorted { $0.key.rawValue < $1.key.rawValue }.enumerated()), id: \.offset) { _, entry in
                                parameterSampleRow(entry.key, sample: entry.value, isInterpolated: interpolatedParameters.contains(entry.key))
                            }
                        }
                    }
                }

            } else {
                ContentUnavailableView(
                    "No Values Available",
                    systemImage: "slider.horizontal.3",
                    description: Text("Select a frame to inspect its interpolated development values.")
                )
                .frame(minHeight: 170)
            }
        }
    }

    private func parameterSampleRow(_ parameter: DevelopmentParameter, sample: ParameterSample, isInterpolated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parameter.rawValue)
                    .foregroundStyle(isInterpolated ? Color.green : EditorPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
                Text(formattedParameterValue(parameter, value: sample.value))
                    .monospacedDigit()
                    .foregroundStyle(isInterpolated ? Color.green : Color.primary)
            }
            if let label = originLabel(sample.origin) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(EditorPalette.secondaryText)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isInterpolated ? "Interpolated between neighboring keyframes." : "")
    }

    private func formattedParameterValue(_ parameter: DevelopmentParameter, value: Double) -> String {
        if parameter == .temperature {
            return String(format: "%.0f K", value)
        }
        if parameter == .exposure {
            return String(format: "%+.2f EV", value)
        }
        return value.formatted(.number.precision(.fractionLength(0...2)).sign(strategy: .always()))
    }

    private func originLabel(_ origin: ParameterOrigin) -> String? {
        switch origin {
        case .importedSidecar: return "XMP"
        case .keyframe: return nil
        case .interpolated: return "calculated"
        case .manualOverride: return "manual override"
        case .holyGrailCompensation: return "capture compensation"
        case .assumedNeutral: return "assumed neutral"
        case .asShot: return "as shot"
        }
    }

    private func inspectorGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(EditorPalette.secondaryText)
            content()
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(EditorPalette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}