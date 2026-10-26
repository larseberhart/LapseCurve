import SwiftUI
import LapseCurveDomain

struct SequenceStatsBarView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            stat(value: model.photoCount, label: "SUPPORTED PHOTOS", identifier: "stats-photo-count")
            Divider().frame(height: 34)
            stat(value: model.keyframeCount, label: "KEY PHOTOS", identifier: "stats-keyframe-count")
            Divider().frame(height: 34)
            stat(value: model.interpolationEligibleCount, label: "IN RANGE", identifier: "stats-interpolation-count")

            Spacer(minLength: 18)

            HStack(spacing: 7) {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                }
                Text(model.statusMessage)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(EditorPalette.secondaryText)
            .help(model.warnings.map(\.message).joined(separator: "\n"))
            .accessibilityIdentifier("sequence-scan-status")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(EditorPalette.panel)
        .accessibilityIdentifier("sequence-stats-bar")
    }

    private func stat(value: Int, label: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted())
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.primary)
                .accessibilityIdentifier(identifier)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(EditorPalette.secondaryText)
        }
        .frame(minWidth: 105, alignment: .leading)
        .padding(.horizontal, 14)
    }
}
