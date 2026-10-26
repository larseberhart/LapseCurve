//
//  LapseCurveTests.swift
//  LapseCurveTests
//
//  Created by Lars EBERHART on 14.10.26.
//

import Foundation
import AppKit
import SwiftUI
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveExport
import LapseCurvePersistence
import LapseCurveSequence
import Testing
@testable import LapseCurve

struct LapseCurveTests {

    @MainActor
    @Test func appEntryPointIsAvailable() {
        #expect(String(reflecting: LapseCurveApp.self) == "LapseCurve.LapseCurveApp")
    }

    @MainActor
    @Test func segmentCurvesRecalculateAndIgnoreLegacyOverrides() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("curves.lapsecurve")
        var fixture = makeCurveProject()
        fixture.overrides = [ManualOverride(id: UUID(), frameID: fixture.frames[1].id,
            parameter: .exposure, value: 2, isLocked: false)]
        try ProjectDocumentCodec().encode(fixture).write(to: url)
        let model = AppModel()
        await model.openProject(from: url)
        let segment = try #require(model.interpolationSegments.first)
        let frameID = fixture.frames[1].id
        let initialGraphs = model.parameterGraphs
        #expect(initialGraphs[segment.startFrame.id]?.first?.points[1].value == 1)

        await model.prepareSidecarUpdatePlan()
        #expect(model.updatePlan != nil)
        await model.setSegmentInterpolation(.smoothstep, for: segment)
        #expect(model.updatePlan == nil)
        #expect(model.isProjectDirty)
        #expect(model.interpolationResult?.valuesByFrame[frameID]?.values[.exposure]?.value == 0.625)
        #expect(model.interpolationResult?.valuesByFrame[fixture.frames[5].id]?.values[.exposure]?.value == 3)
        #expect(model.project?.keyframes == fixture.keyframes)
        #expect(model.parameterGraphs[segment.startFrame.id]?.first?.points[1].value == 0.625)
        #expect(model.parameterGraphs[fixture.frames[4].id] == initialGraphs[fixture.frames[4].id])

        await model.setSegmentInterpolation(.hold, for: segment)
        model.selectFrame(frameID)
        #expect(model.selectedParameters.values[.exposure]?.value == 0)
        #expect(model.parameterGraphs[segment.startFrame.id]?.first?.mode == .hold)
        #expect(model.parameterGraphs[segment.startFrame.id]?.first?.points[1].value == 0)
        await model.undo()
        #expect(model.segmentInterpolation(for: segment) == .smoothstep)
        #expect(model.project?.overrides.count == 1)
        #expect(model.interpolationResult?.valuesByFrame[frameID]?.values[.exposure]?.value == 0.625)
        await model.undo()
        #expect(model.segmentInterpolation(for: segment) == nil)
        #expect(!model.canUndo)
        #expect(model.parameterGraphs == initialGraphs)
        #expect(model.interpolationResult?.valuesByFrame[frameID]?.values[.exposure]?.value == 1)
        await model.redo()
        await model.redo()
        #expect(model.segmentInterpolation(for: segment) == .hold)
        #expect(model.project?.overrides.count == 1)

        await model.saveProject(to: url)
        #expect(!model.isProjectDirty)
        await model.setSegmentInterpolation(.hold, for: segment)
        #expect(!model.isProjectDirty)
        let reopened = AppModel()
        await reopened.openProject(from: url)
        #expect(reopened.errorMessage == nil)
        #expect(reopened.segmentInterpolation(for: segment) == .hold)
        #expect(reopened.parameterGraphs == model.parameterGraphs)
        #expect(reopened.project?.overrides == model.project?.overrides)
        await reopened.setSegmentInterpolation(nil, for: segment)
        #expect(reopened.project?.settings.segmentInterpolations.isEmpty == true)
    }

    @MainActor
    @Test func segmentCurvesSurviveReloadAndResetWhenKeyframesChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0...8 {
            try Data("image-placeholder".utf8).write(to: directory.appendingPathComponent("frame-\(index).jpg"))
            try sidecar(index: index, isKeyframe: [0, 4, 8].contains(index))
                .write(to: directory.appendingPathComponent("frame-\(index).xmp"))
        }
        let model = AppModel()
        model.scanFolder(directory)
        try await waitUntil { model.project != nil && !model.isScanning }
        #expect(model.errorMessage == nil)
        var legacyProject = try #require(model.project)
        let overriddenFrameID = legacyProject.frames[1].id
        legacyProject.overrides = [ManualOverride(id: UUID(), frameID: overriddenFrameID,
            parameter: .exposure, value: 2, isLocked: false)]
        let projectURL = directory.appendingPathComponent("legacy.lapsecurve")
        try ProjectDocumentCodec().encode(legacyProject).write(to: projectURL)
        await model.openProject(from: projectURL)
        try await waitUntil { model.scanResult?.sidecarURLsByFrameID.count == 9 && !model.isScanning }
        let first = try #require(model.interpolationSegments.first)
        let second = try #require(model.interpolationSegments.last)
        await model.setSegmentInterpolation(.smoothstep, for: first)
        await model.setSegmentInterpolation(.smoothstep, for: second)
        let priorModification = model.project?.modifiedAt
        model.refreshMetadata()
        try await waitUntil { model.project?.modifiedAt != priorModification && !model.isScanning }
        #expect(model.errorMessage == nil)
        #expect(model.segmentInterpolation(for: first) == .smoothstep)
        #expect(model.segmentInterpolation(for: second) == .smoothstep)
        #expect(model.parameterGraphs[first.startFrame.id]?.first?.points[1].value == 0.625)
        #expect(model.canUndo)
        await model.prepareSidecarUpdatePlan()
        #expect(model.updatePlan?.updates.isEmpty == false)
        let plannedExposure = try #require(model.updatePlan?.updates.first {
            $0.frame.id == overriddenFrameID
        }?.values[.exposure])
        #expect(abs(plannedExposure - 0.625) < 0.01)
        #expect(model.project?.overrides == legacyProject.overrides)

        try sidecar(index: 4, isKeyframe: false).write(to: directory.appendingPathComponent("frame-4.xmp"))
        let beforeRosterChange = model.project?.modifiedAt
        model.refreshMetadata()
        try await waitUntil { model.project?.modifiedAt != beforeRosterChange && !model.isScanning }
        #expect(model.errorMessage == nil)
        #expect(model.project?.settings.segmentInterpolations.isEmpty == true)
        #expect(model.parameterGraphs.count == 1)
        #expect(model.parameterGraphs[first.startFrame.id]?.isEmpty == true)
        #expect(model.reloadMessage?.contains("Reset 2 curve choice(s)") == true)
        #expect(!model.canUndo)
        #expect(!model.canRedo)
        #expect(model.updatePlan == nil)
    }

    @MainActor
    @Test func repeatedCurveWritesRefreshOnlySuccessfulSidecarBaselines() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0...8 {
            try Data("image-placeholder".utf8).write(to: directory.appendingPathComponent("frame-\(index).jpg"))
            try sidecar(index: index, isKeyframe: [0, 4, 8].contains(index))
                .write(to: directory.appendingPathComponent("frame-\(index).xmp"))
        }
        let model = AppModel()
        model.scanFolder(directory)
        try await waitUntil { model.project != nil && !model.isScanning }
        let segment = try #require(model.interpolationSegments.first)
        let keyframeBytes = try [0, 4, 8].map { try Data(contentsOf: directory.appendingPathComponent("frame-\($0).xmp")) }
        let frame = segment.intermediateFrames[0]
        let sidecarURL = directory.appendingPathComponent("frame-1.xmp")

        #expect(model.selectedInterpolatedParameters == [.exposure])
        model.selectFrame(frame.id)
        #expect(model.selectedInterpolatedParameters == [.exposure])
        await model.prepareSidecarUpdatePlan()
        model.executeSidecarUpdates()
        try await waitUntil { !model.isExecutingSidecarUpdates }
        #expect(model.sidecarUpdateReport?.isComplete == true)
        #expect(try Data(contentsOf: sidecarURL) == model.project?.metadataBaselines[frame.id]?.data)
        #expect(model.updatePlan == nil)
        #expect(model.selectedInterpolatedParameters == [.exposure])
        await model.prepareSidecarUpdatePlan()
        #expect(model.updatePlan?.updates.isEmpty == true)

        await model.setSegmentInterpolation(.hold, for: segment)
        #expect(model.selectedInterpolatedParameters == [.exposure])
        await model.prepareSidecarUpdatePlan()
        #expect(model.updatePlan?.updates.isEmpty == false)
        model.executeSidecarUpdates()
        try await waitUntil { !model.isExecutingSidecarUpdates }
        #expect(model.sidecarUpdateReport?.isComplete == true)
        #expect(model.sidecarUpdateReport?.updatedCount == 3)
        let lastCommitted = try #require(model.project?.metadataBaselines[frame.id])
        #expect(try Data(contentsOf: sidecarURL) == lastCommitted.data)

        var externalData = lastCommitted.data
        externalData.append(Data("\n".utf8))
        try externalData.write(to: sidecarURL)
        await model.setSegmentInterpolation(.smoothstep, for: segment)
        await model.prepareSidecarUpdatePlan()
        model.executeSidecarUpdates()
        try await waitUntil { !model.isExecutingSidecarUpdates }
        #expect(model.sidecarUpdateReport?.failedCount == 1)
        #expect(model.sidecarUpdateReport?.updatedCount == 2)
        #expect(model.project?.metadataBaselines[frame.id] == lastCommitted)
        #expect(try Data(contentsOf: sidecarURL) == externalData)
        await model.prepareSidecarUpdatePlan()
        #expect(model.updatePlan?.updates.map { $0.frame.id } == [frame.id])
        for (offset, index) in [0, 4, 8].enumerated() {
            #expect(try Data(contentsOf: directory.appendingPathComponent("frame-\(index).xmp")) == keyframeBytes[offset])
        }
    }

    @MainActor
    @Test func graphProjectionUsesActualSamplesAndSplitsMissingValues() throws {
        let fixture = makeCurveProject()
        let segment = InterpolationSegmentModel(
            startKeyframe: fixture.keyframes[0], endKeyframe: fixture.keyframes[1],
            startFrame: fixture.frames[0], endFrame: fixture.frames[4],
            intermediateFrames: Array(fixture.frames[1...3].reversed()), sharedParameters: [.exposure],
            interpolatedParameters: [.exposure], unavailableParameters: [], warnings: [])
        var settings = fixture.settings
        settings.segmentInterpolations = [SegmentInterpolation(
            startFrameID: segment.startFrame.id, endFrameID: segment.endFrame.id, mode: .smoothstep)]
        var result = try InterpolationEngine().calculate(frames: fixture.frames, keyframes: fixture.keyframes,
            overrides: [], settings: settings, parameterDefinitions: [])
        let graph = try #require(SegmentParameterGraphModel.makeGraphs(
            for: segment, result: result, settings: settings, definitions: []).first)
        #expect(graph.points.map(\.frameNumber) == [1, 2, 3, 4, 5])
        #expect(graph.points.map(\.value) == [0, 0.625, 2, 3.375, 4])
        #expect(graph.points.filter(\.isEndpoint).map(\.id) == [fixture.frames[0].id, fixture.frames[4].id])
        #expect(graph.mode == .smoothstep)
        #expect(graph.nearestPoint(to: 2.2)?.id == fixture.frames[1].id)
        #expect(graph.nearestPoint(to: -10)?.id == fixture.frames[0].id)
        #expect(graph.nearestPoint(to: 100)?.id == fixture.frames[4].id)
        #expect(graph.valueDomain.lowerBound < 0)
        #expect(graph.valueDomain.upperBound > 4)
        result.valuesByFrame[fixture.frames[2].id] = nil
        result.valuesByFrame[fixture.frames[3].id]?.values[.exposure]?.value = .nan
        let sparse = try #require(SegmentParameterGraphModel.makeGraphs(
            for: segment, result: result, settings: settings, definitions: []).first)
        #expect(sparse.points.map(\.frameNumber) == [1, 2, 5])
        #expect(sparse.points.map(\.run) == [0, 0, 2])
        for frame in fixture.frames {
            result.valuesByFrame[frame.id] = ParameterSet(values: [
                .exposure: ParameterSample(value: 0, origin: .interpolated, isLocked: false)
            ])
        }
        let flat = try #require(SegmentParameterGraphModel.makeGraphs(
            for: segment, result: result, settings: settings, definitions: []).first)
        #expect(flat.valueDomain.lowerBound < 0 && flat.valueDomain.upperBound > 0)
    }

    @MainActor
    @Test func graphsFilterUnchangedAsShotAndUnavailableParameters() async throws {
        var fixture = makeCurveProject()
        for index in fixture.keyframes.indices {
            fixture.keyframes[index].parameters.values[.contrast] = ParameterSample(value: 5, origin: .keyframe, isLocked: false)
            fixture.keyframes[index].parameters.values[.temperature] = ParameterSample(
                value: Double(3_000 + index * 1_000), origin: .asShot, isLocked: false)
            fixture.keyframes[index].parameters.values[.vibrance] = ParameterSample(
                value: Double(index) * 0.001, origin: .keyframe, isLocked: false)
        }
        fixture.keyframes[0].parameters.values[.tint] = ParameterSample(value: -5, origin: .keyframe, isLocked: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GraphFilter-\(UUID().uuidString).lapsecurve")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectDocumentCodec().encode(fixture).write(to: url)
        let model = AppModel()
        await model.openProject(from: url)
        #expect(model.errorMessage == nil)
        #expect(model.parameterGraphs.values.allSatisfy { $0.map(\.parameter) == [.exposure] })
        let first = try #require(model.interpolationSegments.first)
        #expect(first.unavailableParameters.contains(.tint))
        #expect(model.selectedInterpolatedParameters == [.exposure])
        model.selectFrame(first.intermediateFrames[0].id)
        #expect(model.selectedInterpolatedParameters == [.exposure])
        #expect(!model.selectedInterpolatedParameters.contains(.contrast))
        #expect(!model.selectedInterpolatedParameters.contains(.temperature))
        #expect(!model.selectedInterpolatedParameters.contains(.vibrance))
        #expect(!model.selectedInterpolatedParameters.contains(.tint))
        #expect(model.parameterGraphs[first.startFrame.id]?.map(\.parameter) == first.interpolatedParameters)

        let noIntermediate = InterpolationSegmentModel(startKeyframe: first.startKeyframe, endKeyframe: first.endKeyframe,
            startFrame: first.startFrame, endFrame: first.endFrame, intermediateFrames: [],
            sharedParameters: first.sharedParameters, interpolatedParameters: first.interpolatedParameters,
            unavailableParameters: first.unavailableParameters, warnings: [])
        #expect(SegmentParameterGraphModel.makeGraphs(for: noIntermediate,
            result: try #require(model.interpolationResult), settings: fixture.settings, definitions: []).isEmpty)
    }

    @MainActor
    @Test func graphProjectionHandlesLongSequencesWithoutDroppingSamples() throws {
        let parameters: [DevelopmentParameter] = [.exposure, .contrast, .highlights, .shadows, .temperature, .tint, .saturation, .vibrance]
        let frames = (0..<10_000).map { index in
            ImageFrame(id: FrameID(rawValue: UUID()), relativePath: "frame-\(index).jpg", sequenceIndex: index)
        }
        let start = Keyframe(id: UUID(), frameID: frames[0].id, parameters: ParameterSet(), isLocked: true)
        let end = Keyframe(id: UUID(), frameID: frames[9_999].id, parameters: ParameterSet(), isLocked: true)
        let segment = InterpolationSegmentModel(startKeyframe: start, endKeyframe: end,
            startFrame: frames[0], endFrame: frames[9_999], intermediateFrames: Array(frames[1..<9_999]),
            sharedParameters: Set(parameters), interpolatedParameters: parameters, unavailableParameters: [], warnings: [])
        let result = InterpolationResult(valuesByFrame: Dictionary(uniqueKeysWithValues: frames.map { frame in
            (frame.id, ParameterSet(values: Dictionary(uniqueKeysWithValues: parameters.map { parameter in
                (parameter, ParameterSample(value: Double(frame.sequenceIndex), origin: .interpolated, isLocked: false))
            })))
        }), warnings: [])
        let started = ContinuousClock.now
        let graphs = SegmentParameterGraphModel.makeGraphs(for: segment, result: result,
            settings: makeCurveProject().settings, definitions: [])
        print("Projected 10,000 frames across 8 parameters in \(started.duration(to: .now))")
        #expect(graphs.count == 8)
        #expect(graphs.allSatisfy { $0.points.count == 10_000 })
        #expect(graphs.allSatisfy { $0.nearestPoint(to: 5_000)?.id == frames[4_999].id })
    }

    @MainActor
    @Test func parameterGraphsRenderAtNarrowAndWideWidths() throws {
        var fixture = makeCurveProject()
        fixture.keyframes[0].parameters.values[.exposure]?.value = -2
        fixture.keyframes[1].parameters.values[.exposure]?.value = 2
        for index in fixture.keyframes.indices {
            fixture.keyframes[index].parameters.values[.temperature] = ParameterSample(
                value: Double(3_000 + index * 2_000), origin: .keyframe, isLocked: false)
        }
        let segment = InterpolationSegmentModel(startKeyframe: fixture.keyframes[0], endKeyframe: fixture.keyframes[1],
            startFrame: fixture.frames[0], endFrame: fixture.frames[4], intermediateFrames: Array(fixture.frames[1...3]),
            sharedParameters: [.exposure, .temperature], interpolatedParameters: [.exposure, .temperature],
            unavailableParameters: [], warnings: [])
        for mode in [ParameterInterpolation.linear, .smoothstep, .hold] {
            var settings = fixture.settings
            settings.segmentInterpolations = [SegmentInterpolation(
                startFrameID: segment.startFrame.id, endFrameID: segment.endFrame.id, mode: mode)]
            let result = try InterpolationEngine().calculate(frames: fixture.frames, keyframes: fixture.keyframes,
                overrides: [], settings: settings, parameterDefinitions: [])
            let graphs = SegmentParameterGraphModel.makeGraphs(for: segment, result: result,
                settings: settings, definitions: AppModel().parameterDefinitions)
            for width in [300, 700] {
                let renderer = ImageRenderer(content: IntervalParameterGraphsView(graphs: graphs)
                    .padding(16).frame(width: CGFloat(width)).background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                let image = try #require(renderer.nsImage)
                let tiff = try #require(image.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(bitmap.pixelsWide == width * 2)
                #expect(bitmap.pixelsHigh > 300)
                Attachment.record(png, named: "graphs-\(mode.rawValue)-\(width).png")
            }
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(condition(), "Timed out waiting for the metadata scan.")
    }

    private func sidecar(index: Int, isKeyframe: Bool) -> Data {
        Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              xmp:Rating="\(isKeyframe ? 1 : 0)" crs:Exposure2012="\(index == 4 ? 4 : 0)"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
    }

    @MainActor
    @Test func editsDuringSaveRemainDirty() async throws {
        let fixture = makeCurveProject()
        let store = SuspendedProjectStore(project: fixture)
        let model = AppModel(projectRepository: store)
        await model.openProject(from: URL(fileURLWithPath: "/fixture.lapsecurve"))
        let segment = try #require(model.interpolationSegments.first)
        await model.setSegmentInterpolation(.hold, for: segment)
        let destination = URL(fileURLWithPath: "/saved.lapsecurve")
        let saving = Task { await model.saveProject(to: destination) }
        await store.waitForSave()
        await model.setSegmentInterpolation(.smoothstep, for: segment)
        await store.finishSave()
        await saving.value
        #expect(model.isProjectDirty)
        #expect(model.projectURL == destination)
        #expect(model.segmentInterpolation(for: segment) == .smoothstep)
        #expect(await store.savedProject?.settings.segmentInterpolations.first?.mode == .hold)
    }

    @MainActor
    @Test func saveCompletionCannotChangeAReopenedProject() async throws {
        let store = SuspendedProjectStore(project: makeCurveProject())
        let model = AppModel(projectRepository: store)
        await model.openProject(from: URL(fileURLWithPath: "/first.lapsecurve"))
        let saving = Task { await model.saveProject(to: URL(fileURLWithPath: "/obsolete-save.lapsecurve")) }
        await store.waitForSave()
        let reopenedURL = URL(fileURLWithPath: "/reopened.lapsecurve")
        await model.openProject(from: reopenedURL)
        let openedStatus = model.statusMessage
        await store.finishSave()
        await saving.value
        #expect(model.projectURL == reopenedURL)
        #expect(model.statusMessage == openedStatus)
        #expect(!model.isProjectDirty)
    }

    @MainActor
    @Test func newestProjectOpenWinsOutOfOrderCompletions() async throws {
        let store = ControlledProjectLoads()
        let model = AppModel(projectRepository: store)
        let firstURL = URL(fileURLWithPath: "/first.lapsecurve")
        let secondURL = URL(fileURLWithPath: "/second.lapsecurve")
        let firstProject = makeCurveProject()
        let secondProject = makeCurveProject()
        let firstOpen = Task { await model.openProject(from: firstURL) }
        await store.waitForLoad(firstURL)
        let secondOpen = Task { await model.openProject(from: secondURL) }
        await store.waitForLoad(secondURL)
        await store.finishLoad(secondURL, project: secondProject)
        await secondOpen.value
        await store.finishLoad(firstURL, project: firstProject)
        await firstOpen.value
        #expect(model.project?.id == secondProject.id)
        #expect(model.projectURL == secondURL)
        #expect(!model.isScanning)
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test func snapshotIndexesSparseFramesAndAdjacentParameterChanges() throws {
        var fixture = makeCurveProject()
        let positions = [0, 2, 5, 9, 10, 15, 30, 40, 50]
        for index in fixture.frames.indices {
            fixture.frames[index].sequenceIndex = positions[index]
        }
        for index in fixture.keyframes.indices {
            fixture.keyframes[index].parameters.values[.contrast] = ParameterSample(
                value: index == 2 ? 10 : 0, origin: .keyframe, isLocked: false)
        }
        fixture.frames.reverse()
        let snapshot = try EditorSnapshot(project: fixture, definitions: AppModel().parameterDefinitions)
        #expect(snapshot.framesByID.count == 9)
        #expect(snapshot.eligibleFrameCount == 6)
        #expect(snapshot.segments.map { $0.intermediateFrames.map(\.sequenceIndex) } == [[2, 5, 9], [15, 30, 40]])
        #expect(snapshot.interpolatedParametersByFrameID[snapshot.segments[0].intermediateFrames[0].id] == [.exposure])
        #expect(snapshot.interpolatedParametersByFrameID[snapshot.orderedKeyframes[1].frameID] == [.exposure, .contrast])
        #expect(snapshot.graphs[snapshot.orderedKeyframes[0].frameID]?.map(\.parameter) == [.exposure])
        #expect(snapshot.graphs[snapshot.orderedKeyframes[1].frameID]?.map(\.parameter) == [.contrast, .exposure])
    }

    @MainActor
    @Test func latestCurveRequestPublishesOneConsistentSnapshot() async throws {
        let model = AppModel(projectRepository: SuspendedProjectStore(project: makeCurveProject()))
        await model.openProject(from: URL(fileURLWithPath: "/curves.lapsecurve"))
        let segment = try #require(model.interpolationSegments.first)
        let firstEdit = Task { await model.setSegmentInterpolation(.hold, for: segment) }
        try await waitUntil { model.segmentInterpolation(for: segment) == .hold }
        await model.setSegmentInterpolation(.smoothstep, for: segment)
        await firstEdit.value
        #expect(model.segmentInterpolation(for: segment) == .smoothstep)
        #expect(model.parameterGraphs[segment.startFrame.id]?.first?.mode == .smoothstep)
        #expect(model.interpolationResult?.valuesByFrame[segment.intermediateFrames[0].id]?.values[.exposure]?.value == 0.625)
        #expect(!model.isCalculating)
        #expect(model.updatePlan == nil)
    }

    private func makeCurveProject() -> TimeLapseProject {
        let keyframeIDs = [0: UUID(), 4: UUID(), 8: UUID()]
        let frames = (0...8).map { index in
            ImageFrame(id: FrameID(rawValue: UUID()), relativePath: "frame-\(index).dng",
                sequenceIndex: index, metadataStatus: .valid, rating: keyframeIDs[index] == nil ? 0 : 1,
                ratingSource: .xmpSidecar, keyframeID: keyframeIDs[index])
        }
        let keyframes = [0, 4, 8].map { index in
            Keyframe(id: keyframeIDs[index]!, frameID: frames[index].id,
                parameters: ParameterSet(values: [.exposure: ParameterSample(
                    value: index == 4 ? 4 : 0, origin: .keyframe, isLocked: true)]), isLocked: true)
        }
        return TimeLapseProject(schemaVersion: ProjectSchema.currentVersion,
            id: ProjectID(rawValue: UUID()), name: "Curve Test", frames: frames, keyframes: keyframes,
            overrides: [], settings: ProjectSettings(timeBasis: .frameIndex, defaultInterpolation: .linear,
                missingValuePolicy: .warn, exportMode: .updateExistingSidecars), createdAt: Date(), modifiedAt: Date())
    }
}

private actor SuspendedProjectStore: ProjectStoring {
    private let project: TimeLapseProject
    private var pendingSave: CheckedContinuation<Void, Never>?
    private var saveStarted: CheckedContinuation<Void, Never>?
    private(set) var savedProject: TimeLapseProject?

    init(project: TimeLapseProject) { self.project = project }

    func load(from url: URL) async throws -> TimeLapseProject { project }
    func loadRecoverySnapshot(for url: URL) async throws -> TimeLapseProject { project }

    func save(_ project: TimeLapseProject, to url: URL) async throws {
        savedProject = project
        await withCheckedContinuation { continuation in
            pendingSave = continuation
            saveStarted?.resume()
            saveStarted = nil
        }
    }

    func waitForSave() async {
        guard pendingSave == nil else { return }
        await withCheckedContinuation { saveStarted = $0 }
    }

    func finishSave() {
        pendingSave?.resume()
        pendingSave = nil
    }
}

private actor ControlledProjectLoads: ProjectStoring {
    private var pending: [URL: CheckedContinuation<TimeLapseProject, Never>] = [:]
    private var started: [URL: CheckedContinuation<Void, Never>] = [:]

    func load(from url: URL) async throws -> TimeLapseProject {
        await withCheckedContinuation { continuation in
            pending[url] = continuation
            started.removeValue(forKey: url)?.resume()
        }
    }

    func waitForLoad(_ url: URL) async {
        guard pending[url] == nil else { return }
        await withCheckedContinuation { started[url] = $0 }
    }

    func finishLoad(_ url: URL, project: TimeLapseProject) {
        pending.removeValue(forKey: url)?.resume(returning: project)
    }

    func save(_ project: TimeLapseProject, to url: URL) async throws { }

    func loadRecoverySnapshot(for url: URL) async throws -> TimeLapseProject {
        throw ProjectRepositoryError.recoverySnapshotMissing
    }
}
