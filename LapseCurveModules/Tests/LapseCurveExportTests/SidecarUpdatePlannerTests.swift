import Foundation
import LapseCurveDomain
import LapseCurveEngine
import LapseCurveMetadata
import Testing
@testable import LapseCurveExport

struct SidecarUpdatePlannerTests {
    @Test func planContainsOnlyIntermediateFramesWithExistingSidecars() {
        let sequence = makeSequence()
        let sidecar = makeSidecar(frameID: sequence.frames[1].id)

        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            interpolation: makeInterpolation(sequence),
            existingSidecars: [sidecar.frameID: sidecar],
            parameterDefinitions: [exposureDefinition(writable: true)]
        )

        #expect(plan.updates.count == 1)
        #expect(plan.updates[0].frame.id == sequence.frames[1].id)
        #expect(plan.updates[0].sidecar.url.pathExtension == "xmp")
        #expect(plan.updates[0].values[.exposure] == 1)
        #expect(!plan.updates.contains { $0.frame.keyframeID != nil || $0.frame.rating == 1 })
    }

    @Test func lightroomSequenceWithOnlyExposureChangedWritesOnlyExposure() throws {
        let sequence = makeSequence()
        let definitions = XMPFieldRegistry.candidateDevelopmentParameters
        func packet(_ attributes: String) -> Data {
            Data("""
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmlns:crd="http://ns.adobe.com/camera-raw-defaults/1.0/" crd:Exposure2012="0.00" crd:Sharpness="56" crd:Clarity2012="4" \(attributes)/></rdf:RDF></x:xmpmeta>
            """.utf8)
        }
        let startData = packet(#"xmp:Rating="1" crs:CropTop="0""#)
        let endData = packet(#"xmp:Rating="1" crs:Version="18.7" crs:ProcessVersion="15.4" crs:HasSettings="True" crs:WhiteBalance="As Shot" crs:Temperature="5300" crs:Tint="+22" crs:Exposure2012="+2.00" crs:Sharpness="56" crs:Clarity2012="+4" crs:PerspectiveScale="100" crs:ParametricMidtoneSplit="50""#)
        let intermediateData = packet(#"xmp:Rating="0" crs:CropTop="0""#)
        let reader = XMPPacketReader()
        var keyframes = sequence.keyframes
        keyframes[0].parameters = XMPFieldRegistry.developmentValues(in: try reader.read(startData)).parameters
        keyframes[1].parameters = XMPFieldRegistry.developmentValues(in: try reader.read(endData)).parameters
        let interpolation = try InterpolationEngine().calculate(
            frames: sequence.frames,
            keyframes: keyframes,
            overrides: [],
            settings: ProjectSettings(
                timeBasis: .frameIndex,
                defaultInterpolation: .linear,
                missingValuePolicy: .warn,
                exportMode: .updateExistingSidecars
            ),
            parameterDefinitions: definitions
        )
        func snapshot(_ index: Int, _ data: Data) -> ExistingSidecarSnapshot {
            ExistingSidecarSnapshot(
                frameID: sequence.frames[index].id,
                url: URL(fileURLWithPath: "/sequence/frame\(index).xmp"),
                data: data,
                fingerprint: FileFingerprint(byteCount: Int64(data.count), modificationDate: nil, digest: nil)
            )
        }
        let sidecars = [snapshot(0, startData), snapshot(1, intermediateData), snapshot(2, endData)]

        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: keyframes,
            interpolation: interpolation,
            existingSidecars: Dictionary(uniqueKeysWithValues: sidecars.map { ($0.frameID, $0) }),
            parameterDefinitions: definitions
        )

        let update = try #require(plan.updates.first)
        #expect(plan.updates.count == 1)
        #expect(update.values == [.exposure: 1])
        let output = try XMPPacketWriter().updating(
            sourceData: intermediateData,
            values: update.values,
            for: update.frame,
            using: definitions
        )
        let written = try reader.read(output).properties.filter {
            $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace
        }
        #expect(written.first { $0.localName == "Exposure2012" }?.value == "+1.00")
        #expect(!written.contains { ["ProcessVersion", "Version", "HasSettings", "CameraProfileDigest"].contains($0.localName) })
        #expect(!written.contains { ["PerspectiveScale", "Sharpness", "Clarity2012", "Tint", "Temperature", "WhiteBalance"].contains($0.localName) })
    }

    @Test func writerPinsCameraDefaultProfileButNeverChangesAnExistingProfile() throws {
        let sequence = makeSequence()
        let definitions = XMPFieldRegistry.candidateDevelopmentParameters
        func profile(after attributes: String) throws -> String? {
            let source = Data("""
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmlns:crd="http://ns.adobe.com/camera-raw-defaults/1.0/" xmp:Rating="0" crd:CameraProfile="Camera Vivid" \(attributes)/></rdf:RDF></x:xmpmeta>
            """.utf8)
            let output = try XMPPacketWriter().updating(
                sourceData: source,
                values: [.exposure: 1],
                for: sequence.frames[1],
                using: definitions
            )
            return try XMPPacketReader().read(output).properties.first {
                $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace && $0.localName == "CameraProfile"
            }?.value
        }

        #expect(try profile(after: "") == "Camera Vivid")
        #expect(try profile(after: #"crs:CameraProfile="Adobe Standard""#) == "Adobe Standard")
    }

    @Test func whiteBalanceIsInterpolatedUnlessBothKeyPhotosAreAsShot() throws {
        let sequence = makeSequence()
        let sidecar = makeSidecar(frameID: sequence.frames[1].id)
        let definitions = XMPFieldRegistry.candidateDevelopmentParameters
        func plan(endOrigin: ParameterOrigin) throws -> SidecarUpdatePlan {
            var keyframes = sequence.keyframes
            keyframes[0].parameters.values[.temperature] = ParameterSample(value: 5230, origin: .asShot, isLocked: false)
            keyframes[0].parameters.values[.tint] = ParameterSample(value: 16, origin: .asShot, isLocked: false)
            keyframes[1].parameters.values[.temperature] = ParameterSample(value: 7430, origin: endOrigin, isLocked: false)
            keyframes[1].parameters.values[.tint] = ParameterSample(value: -10, origin: endOrigin, isLocked: false)
            let interpolation = try InterpolationEngine().calculate(
                frames: sequence.frames,
                keyframes: keyframes,
                overrides: [],
                settings: ProjectSettings(
                    timeBasis: .frameIndex,
                    defaultInterpolation: .linear,
                    missingValuePolicy: .warn,
                    exportMode: .updateExistingSidecars
                ),
                parameterDefinitions: definitions
            )
            return SidecarUpdatePlanner().makePlan(
                frames: sequence.frames,
                keyframes: keyframes,
                interpolation: interpolation,
                existingSidecars: [sidecar.frameID: sidecar],
                parameterDefinitions: definitions
            )
        }

        let custom = try #require(try plan(endOrigin: .importedSidecar).updates.first)
        #expect(custom.values[.temperature] == 6330)
        #expect(custom.values[.tint] == 3)

        let asShot = try #require(try plan(endOrigin: .asShot).updates.first)
        #expect(asShot.values[.temperature] == nil)
        #expect(asShot.values[.tint] == nil)
    }

    @Test func asShotWhiteBalanceModeIsReadAsAsShotOrigin() throws {
        let packet = try XMPPacketReader().read(Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:WhiteBalance="As Shot" crs:Temperature="5300" crs:Tint="+22"/></rdf:RDF></x:xmpmeta>
        """.utf8))

        let values = XMPFieldRegistry.developmentValues(in: packet).parameters.values

        #expect(values[.temperature] == ParameterSample(value: 5300, origin: .asShot, isLocked: false))
        #expect(values[.tint] == ParameterSample(value: 22, origin: .asShot, isLocked: false))
    }

    @Test func missingSidecarWarnsAndDoesNotCreateAFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sequence = makeSequence()
        let expectedSidecarURL = directory.appendingPathComponent("frame1.xmp")
        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            interpolation: makeInterpolation(sequence),
            existingSidecars: [:],
            parameterDefinitions: [exposureDefinition(writable: true)]
        )

        #expect(plan.updates.isEmpty)
        #expect(plan.warnings.contains {
            $0.code == "xmpSidecarMissing" && $0.frameID == sequence.frames[1].id
        })
        #expect(!FileManager.default.fileExists(atPath: expectedSidecarURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func experimentalCandidateFieldsProduceAnUpdatePlan() {
        let sequence = makeSequence()
        let sidecar = makeSidecar(frameID: sequence.frames[1].id)

        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            interpolation: makeInterpolation(sequence),
            existingSidecars: [sidecar.frameID: sidecar],
            parameterDefinitions: XMPFieldRegistry.candidateDevelopmentParameters
        )

        #expect(plan.updates.count == 1)
        #expect(plan.updates[0].values[.exposure] == 1)
        #expect(!plan.warnings.contains { $0.code == "parameterWriteNotApproved" })
    }

    @Test func keyframeMetadataIsNeverPlannedForWrite() {
        let sequence = makeSequence()
        let keyframeSidecar = makeSidecar(frameID: sequence.frames[0].id, rating: 1)

        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            interpolation: makeInterpolation(sequence),
            existingSidecars: [keyframeSidecar.frameID: keyframeSidecar],
            parameterDefinitions: [exposureDefinition(writable: true)]
        )

        #expect(plan.updates.isEmpty)
        #expect(!plan.warnings.contains { $0.frameID == sequence.frames[0].id })
    }

    @Test func packetRatedKeyframeIsExcludedEvenIfFrameRecordIsStale() {
        let sequence = makeSequence()
        let packetRatedKeyframe = makeSidecar(frameID: sequence.frames[1].id, rating: 1)

        let plan = SidecarUpdatePlanner().makePlan(
            frames: sequence.frames,
            keyframes: sequence.keyframes,
            interpolation: makeInterpolation(sequence),
            existingSidecars: [packetRatedKeyframe.frameID: packetRatedKeyframe],
            parameterDefinitions: [exposureDefinition(writable: true)]
        )

        #expect(plan.updates.isEmpty)
        #expect(plan.warnings.contains {
            $0.code == "keyframeSidecarImmutable" && $0.frameID == sequence.frames[1].id
        })
    }

    @Test func coordinatorRequiresApprovalAndRefusesMissingSidecar() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let missingSidecarURL = directory.appendingPathComponent("missing.xmp")
        let missingSnapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: missingSidecarURL)
        let missingUpdate = makeUpdate(frame: sequence.frames[1], sidecar: missingSnapshot)
        let coordinator = SidecarUpdateCoordinator()

        do {
            _ = try await coordinator.update(missingUpdate, using: [exposureDefinition(writable: true)], explicitlyApproved: true)
            Issue.record("Expected missing sidecar to be rejected")
        } catch let error as SidecarUpdateError {
            #expect(error == .sidecarMissing(missingSidecarURL))
        }
        #expect(!FileManager.default.fileExists(atPath: missingSidecarURL.path))

        let existingSidecarURL = directory.appendingPathComponent("frame1.xmp")
        let existingSnapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: existingSidecarURL)
        try existingSnapshot.data.write(to: existingSidecarURL)
        let existingUpdate = makeUpdate(frame: sequence.frames[1], sidecar: existingSnapshot)
        do {
            _ = try await coordinator.update(existingUpdate, using: [exposureDefinition(writable: true)], explicitlyApproved: false)
            Issue.record("Expected missing user approval to be rejected")
        } catch let error as SidecarUpdateError {
            #expect(error == .explicitApprovalRequired)
        }
        #expect(try Data(contentsOf: existingSidecarURL) == existingSnapshot.data)
    }

    @Test func coordinatorAddsMissingCRSFieldToExistingSidecar() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let originalData = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                        <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crd="http://ns.adobe.com/camera-raw-defaults/1.0/" xmlns:custom="urn:custom" xmp:Rating="0" crd:Exposure2012="0.00" custom:Keep="yes"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        try originalData.write(to: sidecarURL)
        let snapshot = ExistingSidecarSnapshot(
            frameID: sequence.frames[1].id,
            url: sidecarURL,
            data: originalData,
            fingerprint: FileFingerprint(byteCount: Int64(originalData.count), modificationDate: nil, digest: nil)
        )
        let update = makeUpdate(frame: sequence.frames[1], sidecar: snapshot)

        _ = try await SidecarUpdateCoordinator().update(
            update,
            using: [exposureDefinition(writable: true)],
            explicitlyApproved: true
        )
        let updatedData = try Data(contentsOf: sidecarURL)
        let packet = try XMPPacketReader().read(updatedData)
        let exposure = packet.properties.first {
            $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace && $0.localName == "Exposure2012"
        }

        #expect(exposure?.value == "+1.00")
        #expect(packet.properties.contains {
            $0.namespaceURI == "http://ns.adobe.com/camera-raw-defaults/1.0/"
                && $0.localName == "Exposure2012"
                && $0.value == "0.00"
        })
        #expect(packet.properties.contains { $0.namespaceURI == "urn:custom" && $0.localName == "Keep" && $0.value == "yes" })
        #expect(packet.properties.contains { $0.namespaceURI == "http://ns.adobe.com/xap/1.0/" && $0.localName == "Rating" && $0.value == "0" })
        #expect(updatedData != originalData)
    }

    @Test func coordinatorUpdatesOnlyExistingIntermediateSidecarWithoutBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let update = makeUpdate(frame: sequence.frames[1], sidecar: snapshot)

        let receipt = try await SidecarUpdateCoordinator().update(
            update,
            using: [exposureDefinition(writable: true)],
            explicitlyApproved: true
        )

        let updatedData = try Data(contentsOf: sidecarURL)
        let updatedPacket = try XMPPacketReader().read(updatedData)
        #expect(receipt.frameID == sequence.frames[1].id)
        #expect(receipt.sidecarURL == sidecarURL)
        #expect(updatedPacket.properties.contains {
            $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace
                && $0.localName == "Exposure2012"
                && $0.value == "+1.00"
        })
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["frame1.xmp"])
    }

    @Test func coordinatorReportsCompletionAndProgress() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let plan = SidecarUpdatePlan(
            updates: [makeUpdate(frame: sequence.frames[1], sidecar: snapshot)],
            warnings: []
        )
        let progressEvents = ProgressEvents()

        let report = await SidecarUpdateCoordinator().update(
            plan,
            using: [exposureDefinition(writable: true)],
            explicitlyApproved: true,
            progress: { event in await progressEvents.append(event) }
        )

        #expect(report.isComplete)
        #expect(report.updatedCount == 1)
        #expect(report.failedCount == 0)
        let committedMetadata = try #require(report.frameResults.first?.updatedMetadata)
        #expect(try Data(contentsOf: sidecarURL) == committedMetadata.data)
        #expect(committedMetadata.sourceFingerprint?.byteCount == Int64(committedMetadata.data.count))
        #expect(await progressEvents.values.map(\.completedCount) == [1])
    }

    @Test func coordinatorReportsMissingApprovalWithoutWriting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let plan = SidecarUpdatePlan(
            updates: [makeUpdate(frame: sequence.frames[1], sidecar: snapshot)],
            warnings: []
        )

        let report = await SidecarUpdateCoordinator().update(
            plan,
            using: [exposureDefinition(writable: true)],
            explicitlyApproved: false
        )

        #expect(!report.isComplete)
        #expect(report.notAttemptedCount == 1)
        #expect(report.frameResults[0].status == .notApproved)
        #expect(try Data(contentsOf: sidecarURL) == snapshot.data)
    }

    @Test func cancelledRunIsNotReportedAsComplete() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let plan = SidecarUpdatePlan(
            updates: [makeUpdate(frame: sequence.frames[1], sidecar: snapshot)],
            warnings: []
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await SidecarUpdateCoordinator().update(
                plan,
                using: [exposureDefinition(writable: true)],
                explicitlyApproved: true
            )
        }
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(!report.isComplete)
        #expect(report.frameResults[0].status == .cancelled)
        #expect(try Data(contentsOf: sidecarURL) == snapshot.data)
    }

    @Test func coordinatorRejectsStaleSource() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let update = makeUpdate(frame: sequence.frames[1], sidecar: snapshot)
        let coordinator = SidecarUpdateCoordinator()

        try Data("external edit".utf8).write(to: sidecarURL)
        do {
            _ = try await coordinator.update(update, using: [exposureDefinition(writable: true)], explicitlyApproved: true)
            Issue.record("Expected changed source to be rejected")
        } catch let error as SidecarUpdateError {
            #expect(error == .sourceChanged(sequence.frames[1].id))
        }
        #expect(try Data(contentsOf: sidecarURL) == Data("external edit".utf8))
    }

    @Test func concurrentCoordinatorsCannotBothCommitTheSameSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = makeSequence()
        let sidecarURL = directory.appendingPathComponent("frame1.xmp")
        let snapshot = makeExistingSidecar(frameID: sequence.frames[1].id, url: sidecarURL)
        try snapshot.data.write(to: sidecarURL)
        let update = makeUpdate(frame: sequence.frames[1], sidecar: snapshot)
        let coordinators = [SidecarUpdateCoordinator(), SidecarUpdateCoordinator()]

        let successes = await withTaskGroup(of: Bool.self) { group in
            for coordinator in coordinators {
                group.addTask {
                    do {
                        _ = try await coordinator.update(
                            update,
                            using: [exposureDefinition(writable: true)],
                            explicitlyApproved: true
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let updatedData = try Data(contentsOf: sidecarURL)
        #expect(successes.filter { $0 }.count == 1)
        #expect(updatedData != snapshot.data)
        #expect(try XMPPacketReader().read(updatedData).originalData == updatedData)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makeUpdate(frame: ImageFrame, sidecar: ExistingSidecarSnapshot) -> PlannedSidecarUpdate {
        PlannedSidecarUpdate(frame: frame, sidecar: sidecar, values: [.exposure: 1])
    }

    private func makeExistingSidecar(frameID: FrameID, url: URL) -> ExistingSidecarSnapshot {
        let data = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                             xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
                             xmp:Rating="0" crs:Exposure2012="0.0"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        return ExistingSidecarSnapshot(
            frameID: frameID,
            url: url,
            data: data,
            fingerprint: FileFingerprint(byteCount: Int64(data.count), modificationDate: nil, digest: nil)
        )
    }

    private func makeSequence() -> (frames: [ImageFrame], keyframes: [Keyframe]) {
        let startFrameID = FrameID(rawValue: UUID())
        let intermediateFrameID = FrameID(rawValue: UUID())
        let endFrameID = FrameID(rawValue: UUID())
        let startKeyframeID = UUID()
        let endKeyframeID = UUID()
        let frames = [
            ImageFrame(
                id: startFrameID,
                relativePath: "frame0.dng",
                sequenceIndex: 0,
                metadataStatus: .valid,
                rating: 1,
                ratingSource: .xmpSidecar,
                keyframeID: startKeyframeID
            ),
            ImageFrame(
                id: intermediateFrameID,
                relativePath: "frame1.dng",
                sequenceIndex: 1,
                metadataStatus: .valid,
                rating: 0,
                ratingSource: .xmpSidecar
            ),
            ImageFrame(
                id: endFrameID,
                relativePath: "frame2.dng",
                sequenceIndex: 2,
                metadataStatus: .valid,
                rating: 1,
                ratingSource: .xmpSidecar,
                keyframeID: endKeyframeID
            )
        ]
        let keyframes = [
            Keyframe(
                id: startKeyframeID,
                frameID: startFrameID,
                parameters: ParameterSet(values: [
                    .exposure: ParameterSample(value: 0, origin: .keyframe, isLocked: false)
                ]),
                isLocked: false
            ),
            Keyframe(
                id: endKeyframeID,
                frameID: endFrameID,
                parameters: ParameterSet(values: [
                    .exposure: ParameterSample(value: 2, origin: .keyframe, isLocked: false)
                ]),
                isLocked: false
            )
        ]
        return (frames, keyframes)
    }

    private func makeInterpolation(
        _ sequence: (frames: [ImageFrame], keyframes: [Keyframe])
    ) -> InterpolationResult {
        let intermediateFrame = sequence.frames[1]
        return InterpolationResult(
            valuesByFrame: [
                sequence.frames[0].id: sequence.keyframes[0].parameters,
                intermediateFrame.id: ParameterSet(values: [
                    .exposure: ParameterSample(value: 1, origin: .interpolated, isLocked: false)
                ]),
                sequence.frames[2].id: sequence.keyframes[1].parameters
            ],
            warnings: []
        )
    }

    private func makeSidecar(frameID: FrameID, rating: Int = 0) -> ExistingSidecarSnapshot {
        let packet = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                             xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
                             xmp:Rating="\(rating)" crs:Exposure2012="0.0"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        return ExistingSidecarSnapshot(
            frameID: frameID,
            url: URL(fileURLWithPath: "/sequence/frame1.xmp"),
            data: packet,
            fingerprint: FileFingerprint(byteCount: Int64(packet.count), modificationDate: nil, digest: nil)
        )
    }

    private func exposureDefinition(writable: Bool) -> ParameterDefinition {
        ParameterDefinition(
            parameter: .exposure,
            namespaceURI: XMPFieldRegistry.cameraRawSettingsNamespace,
            xmpTag: "Exposure2012",
            unit: .exposureEV,
            interpolation: .linear,
            validRange: -5...5,
            writable: writable,
            compatibilityNotes: "Test definition only."
        )
    }
}

private actor ProgressEvents {
    private(set) var values: [SidecarUpdateProgress] = []

    func append(_ progress: SidecarUpdateProgress) {
        values.append(progress)
    }
}