//
//  ContentView.swift
//  LapseCurve
//
//  Created by Lars EBERHART on 14.10.26.
//

import SwiftUI
import UniformTypeIdentifiers
import LapseCurveDomain
import LapseCurveExport

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isFolderImporterPresented = false
    @State private var hasScheduledStartupFolderPicker = false
    @State private var isErrorPresented = false
    @State private var isExecutionPresented = false
    @State private var folderPickerError = ""

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbarView(
                model: model,
                onChooseFolder: { isFolderImporterPresented = true },
                onSaveProject: saveProject,
                onOpenProject: openProject
            )

            Divider()

            if model.project != nil || !model.frames.isEmpty {
                SequenceStatsBarView(model: model)
                Divider()
            }

            HSplitView {
                KeyframeSequenceListView(model: model)
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

                MetadataInspectorView(model: model)
                    .frame(minWidth: 260, idealWidth: 310, maxWidth: 370)
            }
            .frame(minHeight: 380, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                if model.interpolationEligibleCount > 0 {
                    Label("\(model.interpolationEligibleCount) intermediate photo(s) in range", systemImage: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(EditorPalette.secondaryText)
                }
                Spacer()
                Button(action: openExecutionWorkflow) {
                    Label("Execute Interpolations", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(EditorPalette.accent)
                .disabled(model.project == nil || model.interpolationEligibleCount == 0 || model.isScanning || model.isCalculating || model.isPreparingUpdatePlan || model.isExecutingSidecarUpdates)
                .accessibilityIdentifier("execute-interpolations")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(EditorPalette.panel)
        }
        .background(EditorPalette.window)
        .onAppear {
            guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
            guard !hasScheduledStartupFolderPicker, model.sourceFolderURL == nil else { return }
            hasScheduledStartupFolderPicker = true
            Task { @MainActor in
                await Task.yield()
                guard model.sourceFolderURL == nil else { return }
                isFolderImporterPresented = true
            }
        }
        .onKeyPress(.leftArrow) {
            model.selectAdjacentFrame(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.selectAdjacentFrame(1)
            return .handled
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
        .onChange(of: model.errorMessage) { _, newValue in
            if let newValue {
                folderPickerError = newValue
                isErrorPresented = true
            }
        }
        .alert("LapseCurve", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(folderPickerError)
        }
        .sheet(isPresented: $isExecutionPresented) {
            SidecarPreflightSheet(model: model)
                .frame(minWidth: 560, minHeight: 460)
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let folders):
            if let folderURL = folders.first {
                if model.project != nil {
                    model.relinkSourceFolder(folderURL)
                } else {
                    model.scanFolder(folderURL)
                }
            }
        case .failure(let error):
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
                model.folderSelectionCancelled()
                return
            }
            folderPickerError = error.localizedDescription
            isErrorPresented = true
        }
    }

    private func saveProject() {
        guard let project = model.project else { return }
        let projectURL = model.projectURL ?? ProjectFilePanels.saveURL(suggestedName: project.name)
        guard let projectURL else { return }
        Task { await model.saveProject(to: projectURL) }
    }

    private func openProject() {
        guard let projectURL = ProjectFilePanels.openURL() else { return }
        Task { await model.openProject(from: projectURL) }
    }

    private func openExecutionWorkflow() {
        Task {
            await model.prepareSidecarUpdatePlan()
            guard model.updatePlan != nil else { return }
            isExecutionPresented = true
        }
    }
}

private struct SidecarPreflightSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var plan: SidecarUpdatePlan? { model.updatePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Execute Interpolations")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done", action: { dismiss() })
                    .keyboardShortcut(.defaultAction)
            }

            Text("Review carefully before writing. These mappings are experimental and have not yet been verified by Lightroom read-back.")
                .font(.callout)
                .foregroundStyle(EditorPalette.secondaryText)

            if let plan {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Intermediate photos", value: "\(model.interpolationEligibleCount)")
                    summaryRow("Photos ready to write", value: "\(plan.updates.count)")
                    summaryRow("Skipped / unavailable", value: "\(max(model.interpolationEligibleCount - plan.updates.count, 0))")
                    summaryRow("Supported parameters", value: supportedParameterSummary(plan))
                    summaryRow("Existing XMP files", value: "\(model.project?.metadataBaselines.count ?? 0)")
                    summaryRow("Output location", value: "In-place: \(model.sourceFolderURL?.path ?? "source folder unavailable")")
                    summaryRow("Overwrite behavior", value: "Existing sidecars are replaced in place; no backups are created")
                }

                summaryRow("Potential conflicts", value: "\(plan.warnings.count) warning(s)")

                if !plan.updates.isEmpty {
                    List {
                        Section("Existing Sidecars") {
                            ForEach(Array(plan.updates.enumerated()), id: \.offset) { _, update in
                                Label(update.sidecar.url.lastPathComponent, systemImage: "doc.text")
                            }
                        }
                    }
                    .listStyle(.inset)
                }

                if !plan.warnings.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning.message, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(EditorPalette.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }

                if model.canApplySidecarUpdates {
                    Label("Experimental write: Lightroom recognition is unverified. Existing XMP sidecars only; missing sidecars are skipped.", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(EditorPalette.accent)
                        .accessibilityIdentifier("execution-experimental-notice")

                    Label("Close Lightroom Classic before execution. A later catalog save can overwrite these sidecars.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(EditorPalette.accent)
                }

                if model.isExecutingSidecarUpdates, let progress = model.sidecarUpdateProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                        HStack {
                            Text("Processing sidecars")
                            Spacer()
                            Text("\(progress.completedCount) / \(progress.totalCount)")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Button("Cancel Execution", systemImage: "xmark.circle", action: model.cancelSidecarUpdates)
                            .buttonStyle(.borderless)
                    }
                    .accessibilityIdentifier("execution-progress")
                }

            } else if model.sidecarUpdateReport == nil {
                ContentUnavailableView("Preflight Unavailable", systemImage: "exclamationmark.triangle")
            }

            if let report = model.sidecarUpdateReport {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Results: \(report.updatedCount) updated · \(report.failedCount) failed · \(report.notAttemptedCount) skipped/cancelled")
                        .font(.callout.weight(.semibold))
                    ForEach(Array(report.frameResults.enumerated()), id: \.offset) { _, result in
                        Label(
                            "\(result.sidecarURL.lastPathComponent) · \(result.status.rawValue)",
                            systemImage: result.status == .updated ? "checkmark.circle" : "exclamationmark.circle"
                        )
                        .font(.caption)
                        .help(result.message ?? "")
                    }
                }
                .accessibilityIdentifier("execution-results")
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Execute Interpolations", action: model.executeSidecarUpdates)
                    .buttonStyle(.borderedProminent)
                    .tint(EditorPalette.accent)
                    .disabled(!model.canApplySidecarUpdates || plan?.updates.isEmpty != false || model.isExecutingSidecarUpdates)
                    .accessibilityIdentifier("confirm-execute-interpolations")
            }
        }
        .padding(18)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(EditorPalette.secondaryText)
                .frame(width: 180, alignment: .leading)
            Text(value).fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func supportedParameterSummary(_ plan: SidecarUpdatePlan) -> String {
        let parameters = Set(plan.updates.flatMap { $0.values.keys })
        guard !parameters.isEmpty else { return "None verified" }
        return parameters.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ", ")
    }
}

#Preview {
    ContentView(model: AppModel())
}
