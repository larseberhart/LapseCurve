import SwiftUI

struct EditorToolbarView: View {
    let model: AppModel
    let onChooseFolder: () -> Void
    let onSaveProject: () -> Void
    let onOpenProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timelapse")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(EditorPalette.accent, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("LapseCurve")
                    .font(.headline)
                Text(model.sourceFolderURL == nil ? "Source folder not linked" : model.folderName ?? "Source folder")
                    .font(.caption)
                    .foregroundStyle(EditorPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: 280, alignment: .leading)

            Spacer(minLength: 12)

            if model.isScanning || model.isLoadingPreview || model.isCalculating || model.isPreparingUpdatePlan {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.isScanning ? "Scanning" : model.isCalculating ? "Calculating" : model.isPreparingUpdatePlan ? "Preparing sidecar updates" : "Loading preview")
            }

            Label(model.reloadMessage ?? model.statusMessage, systemImage: model.isScanning ? "arrow.trianglehead.2.clockwise" : "circle.dashed")
                .font(.callout)
                .foregroundStyle(EditorPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("sequence-status")

            Button {
                Task { await model.undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo the last segment curve change")
            .accessibilityIdentifier("undo")

            Button {
                Task { await model.redo() }
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo the last segment curve change")
            .accessibilityIdentifier("redo")

            Button(action: model.refreshMetadata) {
                Label("Reload Metadata", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(model.sourceFolderURL == nil || model.isScanning || model.isExecutingSidecarUpdates)
            .help("Reload metadata after saving it in Lightroom")
            .accessibilityIdentifier("reload-metadata")

            Button(action: onOpenProject) {
                Label("Open", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Open a LapseCurve project")
            .accessibilityIdentifier("open-project")
            .disabled(model.isExecutingSidecarUpdates)

            Button(action: onSaveProject) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(model.project == nil || model.isScanning)
            .help("Save the current project")
            .accessibilityIdentifier("save-project")

            Button(action: onChooseFolder) {
                Label(folderButtonTitle, systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(EditorPalette.accent)
            .help("Choose a working folder")
            .accessibilityIdentifier("choose-folder")
            .disabled(model.isExecutingSidecarUpdates)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(EditorPalette.window)
    }

    private var folderButtonTitle: String {
        if model.project != nil && model.sourceFolderURL == nil { return "Relink Source" }
        return model.folderName == nil ? "Choose Folder" : "Change Folder"
    }
}