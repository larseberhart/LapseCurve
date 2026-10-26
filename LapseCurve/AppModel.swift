import Foundation
import Observation
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveExport
import LapseCurveMetadata
import LapseCurvePersistence
import LapseCurvePreview
import LapseCurveSequence

@MainActor
@Observable
final class AppModel {
    private(set) var project: TimeLapseProject?
    private(set) var scanResult: SequenceScanResult?
    private(set) var editorSnapshot: EditorSnapshot?
    private(set) var isCalculating = false
    private(set) var isPreparingUpdatePlan = false
    private(set) var updatePlan: SidecarUpdatePlan?
    private(set) var selectedFrameID: FrameID?
    private(set) var selectedPreview: PreviewImage?
    private(set) var keyframeThumbnails: [FrameID: PreviewImage] = [:]
    private(set) var keyframeThumbnailFailures: [FrameID: String] = [:]
    private(set) var isExecutingSidecarUpdates = false
    private(set) var sidecarUpdateProgress: SidecarUpdateProgress?
    private(set) var sidecarUpdateReport: SidecarUpdateReport?
    private(set) var sourceFolderURL: URL?
    private(set) var projectURL: URL?
    private(set) var isScanning = false
    private(set) var isLoadingPreview = false
    private(set) var isProjectDirty = false
    private(set) var statusMessage = "Choose a working folder to begin."
    private(set) var errorMessage: String?
    private(set) var reloadMessage: String?

    let parameterDefinitions = XMPFieldRegistry.candidateDevelopmentParameters

    @ObservationIgnored private let scanner: any SequenceScanning
    @ObservationIgnored private let computation = EditorComputation()
    @ObservationIgnored private let previewProvider: any FramePreviewProviding
    @ObservationIgnored private let projectRepository: any ProjectStoring
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var activeSaveID: UUID?
    @ObservationIgnored private var previewRequestID = UUID()
    @ObservationIgnored private var calculationID = UUID()
    @ObservationIgnored private var preflightID = UUID()
    @ObservationIgnored private var calculationTask: Task<EditorSnapshot, Error>?
    @ObservationIgnored private var preflightTask: Task<SidecarUpdatePlan, Error>?
    @ObservationIgnored private let sidecarUpdateCoordinator = SidecarUpdateCoordinator()
    @ObservationIgnored private var activeSecurityScopedURL: URL?
    @ObservationIgnored private var ownsSecurityScope = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var sidecarUpdateTask: Task<Void, Never>?
    private struct EditState {
        let segmentInterpolations: [SegmentInterpolation]
    }

    @ObservationIgnored private var undoStack: [EditState] = []
    @ObservationIgnored private var redoStack: [EditState] = []

    init(
        scanner: (any SequenceScanning)? = nil,
        projectRepository: (any ProjectStoring)? = nil,
        previewProvider: (any FramePreviewProviding)? = nil
    ) {
        self.scanner = scanner ?? SequenceScanner(metadataReader: ImageIOMetadataReader())
        self.projectRepository = projectRepository ?? CodableProjectRepository(parameterDefinitions: XMPFieldRegistry.candidateDevelopmentParameters)
        self.previewProvider = previewProvider ?? ImageIOPreviewProvider()
    }

    var folderName: String? {
        sourceFolderURL?.lastPathComponent ?? project?.sourceRootPathHint.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
    }

    var frames: [ImageFrame] {
        project?.frames ?? scanResult?.frames ?? []
    }

    var keyframeIDs: Set<FrameID> {
        editorSnapshot?.keyframeIDs ?? []
    }

    var orderedKeyframes: [Keyframe] {
        editorSnapshot?.orderedKeyframes ?? []
    }

    var interpolationResult: InterpolationResult? {
        editorSnapshot?.result
    }

    var parameterGraphs: [FrameID: [SegmentParameterGraphModel]] {
        editorSnapshot?.graphs ?? [:]
    }

    var interpolationSegments: [InterpolationSegmentModel] {
        editorSnapshot?.segments ?? []
    }

    var interpolationEligibleCount: Int {
        editorSnapshot?.eligibleFrameCount ?? 0
    }

    var outOfInterpolationRangeCount: Int {
        max(photoCount - keyframeCount - interpolationEligibleCount, 0)
    }

    var selectedFrame: ImageFrame? {
        guard let selectedFrameID else { return nil }
        return frame(for: selectedFrameID)
    }

    func frame(for frameID: FrameID) -> ImageFrame? {
        editorSnapshot?.framesByID[frameID]
    }

    var selectedParameters: ParameterSet {
        guard let selectedFrameID else { return ParameterSet() }
        return interpolationResult?.valuesByFrame[selectedFrameID] ?? ParameterSet()
    }

    var selectedInterpolatedParameters: Set<DevelopmentParameter> {
        guard let selectedFrameID else { return [] }
        let interpolatedParameters = editorSnapshot?.interpolatedParametersByFrameID[selectedFrameID] ?? []
        let values = selectedParameters.values
        return Set(parameterDefinitions.compactMap { definition in
            guard interpolatedParameters.contains(definition.parameter), definition.writable,
                  let sample = values[definition.parameter], sample.value.isFinite,
                  definition.validRange?.contains(sample.value) ?? true else { return nil }
            return definition.parameter
        })
    }

    var keyframeCount: Int {
        project?.keyframes.count ?? scanResult?.summary.keyframeCount ?? 0
    }

    var photoCount: Int {
        project?.frames.count ?? scanResult?.summary.photoCount ?? 0
    }

    var warnings: [ValidationIssue] {
        scanResult?.warnings ?? []
    }

    var canApplySidecarUpdates: Bool {
        parameterDefinitions.contains(where: \.writable)
    }

    var canUndo: Bool { !undoStack.isEmpty && !isScanning && !isExecutingSidecarUpdates }
    var canRedo: Bool { !redoStack.isEmpty && !isScanning && !isExecutingSidecarUpdates }

    func segmentInterpolation(for segment: InterpolationSegmentModel) -> ParameterInterpolation? {
        project?.settings.segmentInterpolations.first {
            $0.startFrameID == segment.startFrame.id && $0.endFrameID == segment.endFrame.id
        }?.mode
    }

    func setSegmentInterpolation(_ mode: ParameterInterpolation?, for segment: InterpolationSegmentModel) async {
        guard var project, !isScanning, !isExecutingSidecarUpdates,
              mode != .monotoneCubic,
              let currentSegment = interpolationSegments.first(where: {
                  $0.startFrame.id == segment.startFrame.id && $0.endFrame.id == segment.endFrame.id
              }),
              !currentSegment.intermediateFrames.isEmpty,
              segmentInterpolation(for: currentSegment) != mode else { return }
        recordEdit()
        project.settings.segmentInterpolations.removeAll {
            $0.startFrameID == segment.startFrame.id && $0.endFrameID == segment.endFrame.id
        }
        if let mode {
            project.settings.segmentInterpolations.append(SegmentInterpolation(
                startFrameID: segment.startFrame.id, endFrameID: segment.endFrame.id, mode: mode
            ))
        }
        self.project = project
        await recalculate()
    }

    /// Acquires user-selected folder access and begins a cancellable directory scan.
    func scanFolder(_ folderURL: URL) {
        guard !isExecutingSidecarUpdates else { return }
        let operationID = beginSourceOperation()
        editorSnapshot = nil
        endSecurityScopedAccess()
        beginSecurityScopedAccess(to: folderURL)
        undoStack.removeAll()
        redoStack.removeAll()
        sourceFolderURL = folderURL.standardizedFileURL
        selectedPreview = nil
        keyframeThumbnails.removeAll()
        keyframeThumbnailFailures.removeAll()
        errorMessage = nil
        reloadMessage = nil

        scanTask = Task { [weak self] in
            await self?.performInitialScan(in: folderURL.standardizedFileURL, operationID: operationID)
        }
    }

    /// Reconnects a project to source files without importing their current metadata.
    func relinkSourceFolder(_ folderURL: URL, markProjectDirty: Bool = true) {
        guard !isExecutingSidecarUpdates else { return }
        guard var project else {
            scanFolder(folderURL)
            return
        }
        let operationID = beginSourceOperation()
        endSecurityScopedAccess()
        beginSecurityScopedAccess(to: folderURL)
        let directory = folderURL.standardizedFileURL
        sourceFolderURL = directory
        selectedPreview = nil
        keyframeThumbnails.removeAll()
        keyframeThumbnailFailures.removeAll()
        errorMessage = nil

        let bookmark = try? directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        project.sourceRootPathHint = directory.path
        project.sourceBookmark = bookmark
        project.workingDirectoryBookmark = bookmark
        if markProjectDirty {
            project.modifiedAt = Date()
            isProjectDirty = true
        }
        self.project = project
        statusMessage = "Indexing linked source folder…"
        scanTask = Task { [weak self] in
            await self?.performSourceRelink(in: directory, preserving: project, operationID: operationID)
        }
    }

    /// Requests cancellation of the active scan.
    func cancelScan() {
        scanTask?.cancel()
    }

    func folderSelectionCancelled() {
        guard sourceFolderURL == nil, project == nil else { return }
        statusMessage = "Folder selection cancelled. Choose a folder to scan."
    }

    func selectAdjacentFrame(_ offset: Int) {
        guard let selectedFrameID,
              let currentIndex = frames.firstIndex(where: { $0.id == selectedFrameID }) else { return }
        let nextIndex = min(max(currentIndex + offset, 0), frames.count - 1)
        guard nextIndex != currentIndex else { return }
        selectFrame(frames[nextIndex].id)
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Explicitly reloads metadata after the user saves it through Lightroom.
    func refreshMetadata() {
        guard !isExecutingSidecarUpdates, let sourceFolderURL, let project else { return }
        let operationID = beginSourceOperation()
        scanTask = Task { [weak self] in
            await self?.performMetadataRefresh(in: sourceFolderURL, previousProject: project, operationID: operationID)
        }
    }

    /// Selects an existing sequence frame and requests its source preview.
    func selectFrame(_ frameID: FrameID) {
        guard frames.contains(where: { $0.id == frameID }) else { return }
        selectedFrameID = frameID
        selectedPreview = nil
        previewTask?.cancel()
        let requestID = UUID()
        previewRequestID = requestID
        let previewSessionID = sessionID

        guard let sourceFolderURL,
              let frame = frames.first(where: { $0.id == frameID }) else {
            statusMessage = "Project loaded; relink its source folder to view previews."
            return
        }

        let frameURL = sourceFolderURL.appendingPathComponent(frame.relativePath)
        previewTask = Task { [weak self, previewProvider] in
            guard let self, sessionID == previewSessionID, previewRequestID == requestID else { return }
            isLoadingPreview = true
            defer {
                if sessionID == previewSessionID, previewRequestID == requestID { isLoadingPreview = false }
            }
            do {
                let image = try await previewProvider.preview(
                    for: frame,
                    sourceURL: frameURL,
                    companionJPEGURL: nil,
                    maximumPixelSize: 1_600
                )
                try Task.checkCancellation()
                guard sessionID == previewSessionID, previewRequestID == requestID else { return }
                selectedPreview = image
            } catch is CancellationError {
                return
            } catch {
                guard sessionID == previewSessionID, previewRequestID == requestID else { return }
                statusMessage = error.localizedDescription
            }
        }
    }

    func loadKeyframeThumbnail(_ frameID: FrameID) async {
        let thumbnailSessionID = sessionID
        guard keyframeIDs.contains(frameID),
              keyframeThumbnails[frameID] == nil,
              let sourceFolderURL,
              let frame = frames.first(where: { $0.id == frameID }) else { return }
        let frameURL = sourceFolderURL.appendingPathComponent(frame.relativePath)
        do {
            let thumbnail = try await previewProvider.preview(
                for: frame,
                sourceURL: frameURL,
                companionJPEGURL: nil,
                maximumPixelSize: 180
            )
            try Task.checkCancellation()
            guard sessionID == thumbnailSessionID else { return }
            keyframeThumbnails[frameID] = thumbnail
            keyframeThumbnailFailures[frameID] = nil
        } catch is CancellationError {
            return
        } catch {
            guard sessionID == thumbnailSessionID else { return }
            keyframeThumbnailFailures[frameID] = error.localizedDescription
        }
    }

    func undo() async {
        guard canUndo, var project, let previousState = undoStack.popLast() else { return }
        redoStack.append(EditState(segmentInterpolations: project.settings.segmentInterpolations))
        project.settings.segmentInterpolations = previousState.segmentInterpolations
        self.project = project
        await recalculate()
    }

    func redo() async {
        guard canRedo, var project, let nextState = redoStack.popLast() else { return }
        undoStack.append(EditState(segmentInterpolations: project.settings.segmentInterpolations))
        project.settings.segmentInterpolations = nextState.segmentInterpolations
        self.project = project
        await recalculate()
    }

    /// Recalculates from imported keyframe anchors and segment curve settings.
    func recalculate(markDirty: Bool = true) async {
        guard var project else {
            editorSnapshot = nil
            return
        }
        calculationTask?.cancel()
        preflightTask?.cancel()
        preflightID = UUID()
        isPreparingUpdatePlan = false
        updatePlan = nil
        let requestID = UUID()
        calculationID = requestID
        let calculationSessionID = sessionID
        if markDirty {
            project.modifiedAt = Date()
            self.project = project
            isProjectDirty = true
        }
        isCalculating = true
        let definitions = parameterDefinitions
        let task = Task { [computation] in
            try await computation.snapshot(for: project, definitions: definitions)
        }
        calculationTask = task
        defer {
            if calculationID == requestID {
                isCalculating = false
                calculationTask = nil
            }
        }
        do {
            let snapshot = try await task.value
            guard sessionID == calculationSessionID, calculationID == requestID else { return }
            editorSnapshot = snapshot
            statusMessage = snapshot.result.warnings.first?.message ?? "Values recalculated."
        } catch is CancellationError {
            return
        } catch {
            guard sessionID == calculationSessionID, calculationID == requestID else { return }
            editorSnapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Builds a preflight plan for experimental, explicitly approved writes to existing sidecars.
    func prepareSidecarUpdatePlan() async {
        guard !isScanning, !isCalculating, !isExecutingSidecarUpdates,
              let project, let interpolationResult else { return }
        sidecarUpdateReport = nil
        preflightTask?.cancel()
        updatePlan = nil
        let requestID = UUID()
        preflightID = requestID
        let preflightSessionID = sessionID
        let sidecarURLs = scanResult?.sidecarURLsByFrameID ?? [:]
        let definitions = parameterDefinitions
        isPreparingUpdatePlan = true
        let task = Task { [computation] in
            try await computation.preflight(project: project, result: interpolationResult,
                sidecarURLs: sidecarURLs, definitions: definitions)
        }
        preflightTask = task
        defer {
            if preflightID == requestID {
                isPreparingUpdatePlan = false
                preflightTask = nil
            }
        }
        do {
            let plan = try await task.value
            guard sessionID == preflightSessionID, preflightID == requestID, self.project == project else { return }
            updatePlan = plan
            statusMessage = "Experimental sidecar preflight ready; Lightroom field recognition is unverified."
        } catch is CancellationError {
            return
        } catch {
            guard sessionID == preflightSessionID, preflightID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func executeSidecarUpdates() {
        guard !isScanning, !isCalculating, !isPreparingUpdatePlan else { return }
        guard canApplySidecarUpdates else {
            statusMessage = "No writable parameter mappings are enabled. No files were changed."
            return
        }
        guard !isExecutingSidecarUpdates, let updatePlan else {
            statusMessage = "Run preflight before executing sidecar updates."
            return
        }
        guard !updatePlan.updates.isEmpty else {
            statusMessage = "No eligible existing intermediate XMP sidecars were found. No files were changed."
            return
        }
        isExecutingSidecarUpdates = true
        sidecarUpdateReport = nil
        sidecarUpdateProgress = SidecarUpdateProgress(
            completedCount: 0,
            totalCount: updatePlan.updates.count,
            frameID: nil
        )
        let definitions = parameterDefinitions
        let executionProjectID = project?.id
        let executionSourceURL = sourceFolderURL
        sidecarUpdateTask = Task { [weak self, sidecarUpdateCoordinator] in
            guard let self else { return }
            let report = await sidecarUpdateCoordinator.update(
                updatePlan,
                using: definitions,
                explicitlyApproved: true,
                progress: { [weak self] progress in
                    await self?.recordSidecarUpdateProgress(progress)
                }
            )
            if var project, project.id == executionProjectID, sourceFolderURL == executionSourceURL {
                var didUpdateBaseline = false
                for result in report.frameResults where result.status == .updated {
                    guard let metadata = result.updatedMetadata else { continue }
                    project.metadataBaselines[result.frameID] = metadata
                    scanResult?.metadataBaselinesByFrameID[result.frameID] = metadata
                    didUpdateBaseline = true
                }
                if didUpdateBaseline {
                    project.modifiedAt = Date()
                    self.project = project
                    isProjectDirty = true
                }
                self.updatePlan = nil
            }
            sidecarUpdateReport = report
            isExecutingSidecarUpdates = false
            sidecarUpdateTask = nil
            statusMessage = report.isComplete
                ? "Updated \(report.updatedCount) sidecar(s)."
                : "Execution finished with \(report.failedCount) failure(s) and \(report.notAttemptedCount) skipped/cancelled file(s)."
        }
    }

    func cancelSidecarUpdates() {
        sidecarUpdateTask?.cancel()
    }

    private func recordSidecarUpdateProgress(_ progress: SidecarUpdateProgress) {
        sidecarUpdateProgress = progress
    }

    /// Saves through the versioned Codable repository.
    func saveProject(to url: URL) async {
        guard let project else { return }
        let savingSessionID = sessionID
        let saveID = UUID()
        activeSaveID = saveID
        do {
            try await projectRepository.save(project, to: url)
            guard sessionID == savingSessionID, self.project?.id == project.id, activeSaveID == saveID else { return }
            projectURL = url
            if self.project == project {
                isProjectDirty = false
                statusMessage = "Project saved."
            } else {
                statusMessage = "Project saved; newer changes remain unsaved."
            }
        } catch {
            guard sessionID == savingSessionID, self.project?.id == project.id, activeSaveID == saveID else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Opens and validates a project; source relinking remains available if its bookmark is stale.
    func openProject(from url: URL) async {
        guard !isExecutingSidecarUpdates else { return }
        let operationID = beginSourceOperation()
        defer {
            if sessionID == operationID { isScanning = false }
        }
        do {
            let loadedProject = try await projectRepository.load(from: url)
            try Task.checkCancellation()
            guard sessionID == operationID else { return }
            previewTask?.cancel()
            endSecurityScopedAccess()
            project = loadedProject
            editorSnapshot = nil
            keyframeThumbnails.removeAll()
            keyframeThumbnailFailures.removeAll()
            undoStack.removeAll()
            redoStack.removeAll()
            projectURL = url
            scanResult = SequenceScanResult(
                frames: loadedProject.frames,
                keyframes: loadedProject.keyframes,
                metadataBaselinesByFrameID: loadedProject.metadataBaselines,
                warnings: [],
                summary: loadedProject.lastScanSummary ?? SequenceScanSummary(
                    workingDirectoryPathHint: loadedProject.sourceRootPathHint ?? "",
                    photoCount: loadedProject.frames.count,
                    keyframeCount: loadedProject.keyframes.count,
                    unreadableRatingCount: 0,
                    unsupportedFileCount: 0,
                    scannedAt: Date()
                )
            )
            sourceFolderURL = nil
            selectedFrameID = loadedProject.frames.first?.id
            isProjectDirty = false
            await recalculate(markDirty: false)
            guard sessionID == operationID, editorSnapshot != nil else { return }
            isProjectDirty = false
            let resolvedSourceFolder = resolveProjectSource(loadedProject)
            statusMessage = resolvedSourceFolder == nil
                ? "Project opened; relink the source folder to browse previews."
                : "Project opened; indexing its source folder."
            if let resolvedSourceFolder {
                relinkSourceFolder(resolvedSourceFolder, markProjectDirty: false)
            }
            if let selectedFrameID { selectFrame(selectedFrameID) }
        } catch {
            guard sessionID == operationID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func performInitialScan(in directory: URL, operationID: UUID) async {
        guard sessionID == operationID else { return }
        isScanning = true
        statusMessage = "Scanning source folder…"
        defer {
            if sessionID == operationID { isScanning = false }
        }
        do {
            let result = try await scanner.scan(
                directory: directory,
                options: SequenceScanOptions(previousFrames: project?.frames ?? [])
            )
            try Task.checkCancellation()
            guard sessionID == operationID else { return }
            scanResult = result
            let bookmarkData = try? directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let now = Date()
            let newProject = TimeLapseProject(
                schemaVersion: ProjectSchema.currentVersion,
                id: ProjectID(rawValue: UUID()),
                name: directory.lastPathComponent,
                sourceBookmark: bookmarkData,
                sourceRootPathHint: directory.path,
                frames: result.frames,
                keyframes: result.keyframes,
                metadataBaselines: result.metadataBaselinesByFrameID,
                lastScanSummary: result.summary,
                overrides: [],
                settings: defaultProjectSettings,
                createdAt: now,
                modifiedAt: now
            )
            project = newProject
            isProjectDirty = true
            await recalculate(markDirty: false)
            guard sessionID == operationID, editorSnapshot != nil else { return }
            selectedFrameID = newProject.frames.first?.id
            statusMessage = newProject.frames.isEmpty
                ? "No supported photos were found."
                : "Scanned \(result.summary.photoCount) photos; \(result.summary.keyframeCount) one-star keyframes."
            if let selectedFrameID { selectFrame(selectedFrameID) }
        } catch is CancellationError {
            guard sessionID == operationID else { return }
            statusMessage = "Scan cancelled."
        } catch {
            guard sessionID == operationID else { return }
            errorMessage = error.localizedDescription
            statusMessage = "Scan failed."
        }
    }

    private func performMetadataRefresh(in directory: URL, previousProject: TimeLapseProject, operationID: UUID) async {
        guard sessionID == operationID else { return }
        isScanning = true
        statusMessage = "Reloading Lightroom metadata…"
        defer {
            if sessionID == operationID { isScanning = false }
        }
        do {
            let result = try await scanner.scan(
                directory: directory,
                options: SequenceScanOptions(previousFrames: previousProject.frames)
            )
            try Task.checkCancellation()
            guard sessionID == operationID else { return }
            let oldKeyframes = Dictionary(previousProject.keyframes.map { ($0.frameID, $0) }, uniquingKeysWith: { first, _ in first })
            let changedKeyframeCount = result.keyframes.filter { newKeyframe in
                oldKeyframes[newKeyframe.frameID]?.parameters != newKeyframe.parameters
            }.count
            var refreshedProject = previousProject
            refreshedProject.frames = result.frames
            refreshedProject.keyframes = result.keyframes
            refreshedProject.metadataBaselines = result.metadataBaselinesByFrameID
            refreshedProject.lastScanSummary = result.summary
            refreshedProject.modifiedAt = Date()
            let indices = Dictionary(uniqueKeysWithValues: result.frames.map { ($0.id, $0.sequenceIndex) })
            let refreshedKeyframes = result.keyframes.sorted {
                indices[$0.frameID, default: Int.max] < indices[$1.frameID, default: Int.max]
            }
            refreshedProject.settings.segmentInterpolations.removeAll { segment in
                !zip(refreshedKeyframes, refreshedKeyframes.dropFirst()).contains {
                    $0.0.frameID == segment.startFrameID && $0.1.frameID == segment.endFrameID
                }
            }
            let resetCurveCount = previousProject.settings.segmentInterpolations.count
                - refreshedProject.settings.segmentInterpolations.count
            try ProjectValidator.validate(refreshedProject, parameterDefinitions: parameterDefinitions)
            if orderedKeyframes.map(\.frameID) != refreshedKeyframes.map(\.frameID) {
                undoStack.removeAll()
                redoStack.removeAll()
            }
            scanResult = result
            project = refreshedProject
            isProjectDirty = true
            reloadMessage = "Reloaded sidecars; \(changedKeyframeCount) keyframe(s) changed."
            if resetCurveCount > 0 {
                reloadMessage = "\(reloadMessage ?? "") Reset \(resetCurveCount) curve choice(s) for changed keyframe intervals."
            }
            await recalculate()
            guard sessionID == operationID else { return }
            if let selectedFrameID { selectFrame(selectedFrameID) }
        } catch is CancellationError {
            guard sessionID == operationID else { return }
            statusMessage = "Metadata reload cancelled."
        } catch {
            guard sessionID == operationID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func performSourceRelink(in directory: URL, preserving project: TimeLapseProject, operationID: UUID) async {
        guard sessionID == operationID else { return }
        isScanning = true
        defer {
            if sessionID == operationID { isScanning = false }
        }
        do {
            var result = try await scanner.scan(
                directory: directory,
                options: SequenceScanOptions(previousFrames: project.frames)
            )
            try Task.checkCancellation()
            guard sessionID == operationID else { return }
            result.frames = project.frames
            result.keyframes = project.keyframes
            result.metadataBaselinesByFrameID = project.metadataBaselines
            scanResult = result
            await recalculate(markDirty: false)
            guard sessionID == operationID else { return }
            statusMessage = "Source linked; reloaded metadata only when explicitly requested."
            if let selectedFrameID { selectFrame(selectedFrameID) }
        } catch is CancellationError {
            guard sessionID == operationID else { return }
            statusMessage = "Source indexing cancelled."
        } catch {
            guard sessionID == operationID else { return }
            errorMessage = error.localizedDescription
            statusMessage = "Source indexing failed."
        }
    }

    private func recordEdit() {
        guard let project else { return }
        undoStack.append(EditState(segmentInterpolations: project.settings.segmentInterpolations))
        redoStack.removeAll()
    }

    private var defaultProjectSettings: ProjectSettings {
        ProjectSettings(
            timeBasis: .frameIndex,
            defaultInterpolation: .smoothstep,
            missingValuePolicy: .warn,
            exportMode: .updateExistingSidecars
        )
    }

    private func beginSourceOperation() -> UUID {
        sessionID = UUID()
        activeSaveID = nil
        previewRequestID = UUID()
        calculationID = UUID()
        preflightID = UUID()
        calculationTask?.cancel()
        preflightTask?.cancel()
        isCalculating = false
        isPreparingUpdatePlan = false
        scanTask?.cancel()
        previewTask?.cancel()
        isScanning = true
        isLoadingPreview = false
        updatePlan = nil
        sidecarUpdateReport = nil
        errorMessage = nil
        return sessionID
    }

    private func beginSecurityScopedAccess(to url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        activeSecurityScopedURL = url
        ownsSecurityScope = didStart
    }

    private func endSecurityScopedAccess() {
        if ownsSecurityScope {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURL = nil
        ownsSecurityScope = false
    }

    private func resolveProjectSource(_ project: TimeLapseProject) -> URL? {
        if let bookmarkData = project.workingDirectoryBookmark ?? project.sourceBookmark {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return bookmarkedURL
            }
        }
        guard let sourceRootPathHint = project.sourceRootPathHint else { return nil }
        let pathURL = URL(fileURLWithPath: sourceRootPathHint, isDirectory: true)
        return FileManager.default.fileExists(atPath: pathURL.path) ? pathURL : nil
    }
}