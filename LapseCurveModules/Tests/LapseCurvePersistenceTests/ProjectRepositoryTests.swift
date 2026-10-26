import Foundation
import LapseCurveDomain
import Testing
@testable import LapseCurvePersistence

struct ProjectRepositoryTests {
    @Test func codecRoundTripPreservesProjectStateAndBookmarks() throws {
        let project = makeProject()
        let codec = ProjectDocumentCodec()
        let encoded = try codec.encode(project)
        let decoded = try codec.decode(encoded)

        #expect(decoded == project)
        #expect(decoded.sourceBookmark == Data([1, 2, 3]))
        #expect(decoded.workingDirectoryBookmark == Data([4, 5, 6]))
    }

    @Test func segmentCurvesRoundTripAndRejectInvalidPairs() throws {
        var project = makeProject()
        var endFrame = project.frames[0]
        endFrame.id = FrameID(rawValue: UUID())
        endFrame.sequenceIndex = 4
        endFrame.relativePath = "frame-005.dng"
        endFrame.keyframeID = UUID()
        project.frames.append(endFrame)
        project.keyframes.append(Keyframe(id: endFrame.keyframeID!, frameID: endFrame.id,
            parameters: project.keyframes[0].parameters, isLocked: false))
        let segment = SegmentInterpolation(startFrameID: project.frames[0].id, endFrameID: endFrame.id, mode: .smoothstep)
        project.settings.segmentInterpolations = [segment]
        let codec = ProjectDocumentCodec()
        #expect(try codec.decode(codec.encode(project)) == project)

        project.settings.segmentInterpolations.append(segment)
        #expect(throws: ProjectValidationError.self) { try ProjectValidator.validate(project) }
        project.settings.segmentInterpolations = [SegmentInterpolation(
            startFrameID: endFrame.id, endFrameID: project.frames[0].id, mode: .hold)]
        #expect(throws: ProjectValidationError.self) { try ProjectValidator.validate(project) }
        project.settings.segmentInterpolations = [SegmentInterpolation(
            startFrameID: segment.startFrameID, endFrameID: segment.endFrameID, mode: .monotoneCubic)]
        #expect(throws: ProjectValidationError.self) { try ProjectValidator.validate(project) }
    }

    @Test func legacyProjectWithoutSegmentCurvesMigrates() throws {
        let codec = ProjectDocumentCodec()
        let project = makeProject()
        var document = try #require(JSONSerialization.jsonObject(with: codec.encode(project)) as? [String: Any])
        document["schemaVersion"] = 1
        var settings = try #require(document["settings"] as? [String: Any])
        settings.removeValue(forKey: "segmentInterpolations")
        document["settings"] = settings
        let migrated = try codec.decode(JSONSerialization.data(withJSONObject: document))
        #expect(migrated == project)
        #expect(migrated.settings.segmentInterpolations.isEmpty)
    }

    @Test func saveCreatesDocumentAndSecondSaveKeepsPriorRecoverySnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("sample.lapsecurve")
        let repository = CodableProjectRepository()
        let originalProject = makeProject(name: "Original")

        try await repository.save(originalProject, to: documentURL)
        #expect(try await repository.load(from: documentURL) == originalProject)
        await expectAsyncError(ProjectRepositoryError.recoverySnapshotMissing) {
            _ = try await repository.loadRecoverySnapshot(for: documentURL)
        }

        let updatedProject = makeProject(name: "Updated")
        try await repository.save(updatedProject, to: documentURL)

        #expect(try await repository.load(from: documentURL) == updatedProject)
        #expect(try await repository.loadRecoverySnapshot(for: documentURL) == originalProject)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == [
            "sample.lapsecurve",
            "sample.lapsecurve.recovery"
        ])
    }

    @Test func invalidNewProjectIsRejectedWithoutCreatingFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("invalid.lapsecurve")
        let repository = CodableProjectRepository()

        await expectAsyncError(ProjectValidationError.emptyProjectName) {
            try await repository.save(makeProject(name: "  "), to: documentURL)
        }
        #expect(!FileManager.default.fileExists(atPath: documentURL.path))
    }

    @Test func corruptExistingDocumentCannotBeOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("corrupt.lapsecurve")
        let corruptBytes = Data("not a project".utf8)
        try corruptBytes.write(to: documentURL)
        let repository = CodableProjectRepository()

        await expectAsyncError(ProjectRepositoryError.decodingFailed) {
            try await repository.save(makeProject(name: "Replacement"), to: documentURL)
        }
        #expect(try Data(contentsOf: documentURL) == corruptBytes)
        #expect(!FileManager.default.fileExists(atPath: documentURL.appendingPathExtension("recovery").path))
    }

    @Test func unsupportedFutureSchemaCannotBeLoadedOrOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("future.lapsecurve")
        var futureProject = makeProject(name: "Future")
        futureProject.schemaVersion = ProjectSchema.currentVersion + 1
        let futureBytes = try JSONEncoder().encode(futureProject)
        try futureBytes.write(to: documentURL)
        let repository = CodableProjectRepository()

        await expectAsyncError(ProjectRepositoryError.unsupportedSchemaVersion(futureProject.schemaVersion)) {
            _ = try await repository.load(from: documentURL)
        }
        await expectAsyncError(ProjectRepositoryError.unsupportedSchemaVersion(futureProject.schemaVersion)) {
            try await repository.save(makeProject(name: "Downgrade"), to: documentURL)
        }
        #expect(try Data(contentsOf: documentURL) == futureBytes)
        #expect(!FileManager.default.fileExists(atPath: documentURL.appendingPathExtension("recovery").path))
    }

    @Test func failedSaveDoesNotReplaceLastValidDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("valid.lapsecurve")
        let repository = CodableProjectRepository()
        let validProject = makeProject(name: "Valid")
        try await repository.save(validProject, to: documentURL)
        let originalBytes = try Data(contentsOf: documentURL)

        await expectAsyncError(ProjectValidationError.emptyProjectName) {
            try await repository.save(makeProject(name: ""), to: documentURL)
        }
        #expect(try Data(contentsOf: documentURL) == originalBytes)
        #expect(try await repository.load(from: documentURL) == validProject)
    }

    @Test func saveToMissingParentFailsWithoutCreatingArtifacts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingParent = directory.appendingPathComponent("missing", isDirectory: true)
        let destinationURL = missingParent.appendingPathComponent("project.lapsecurve")
        let repository = CodableProjectRepository()

        await expectAsyncError(ProjectRepositoryError.parentDirectoryMissing) {
            try await repository.save(makeProject(), to: destinationURL)
        }
        #expect(!FileManager.default.fileExists(atPath: missingParent.path))
    }

    @Test func saveToDirectoryFailsWithoutChangingItsContents() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("occupied.lapsecurve", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: false)
        let markerURL = destinationURL.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: markerURL)
        let repository = CodableProjectRepository()

        do {
            try await repository.save(makeProject(), to: destinationURL)
            Issue.record("Expected a directory destination to be rejected.")
        } catch let error as ProjectRepositoryError {
            #expect(error == .fileOperationFailed || error == .decodingFailed)
        } catch {
            Issue.record("Unexpected error for directory destination: \(error)")
        }
        #expect(try Data(contentsOf: markerURL) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationURL.path) == ["keep.txt"])
    }

    @Test func simulatedDiskFullKeepsLastValidDocumentAndRecovery() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("project.lapsecurve")
        let originalProject = makeProject(name: "Original")
        let regularRepository = CodableProjectRepository()
        try await regularRepository.save(originalProject, to: documentURL)
        let originalBytes = try Data(contentsOf: documentURL)
        let failingRepository = CodableProjectRepository(fileWriter: SimulatedDiskFullWriter())

        await expectAsyncError(ProjectRepositoryError.fileOperationFailed) {
            try await failingRepository.save(makeProject(name: "Updated"), to: documentURL)
        }

        #expect(try Data(contentsOf: documentURL) == originalBytes)
        #expect(try await failingRepository.load(from: documentURL) == originalProject)
        #expect(try await failingRepository.loadRecoverySnapshot(for: documentURL) == originalProject)
    }

    private func makeProject(name: String = "Sample Project") -> TimeLapseProject {
        let projectID = ProjectID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        let frameID = FrameID(rawValue: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
        let keyframeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.125)
        let frame = ImageFrame(
            id: frameID,
            relativePath: "frame-001.dng",
            sequenceIndex: 0,
            captureTime: timestamp,
            captureTimeSource: .exif,
            captureMetadata: CaptureMetadata(
                shutterDurationSeconds: 1.0 / 125,
                apertureFNumber: 5.6,
                iso: 100
            ),
            metadataStatus: .valid,
            rating: 1,
            ratingSource: .xmpSidecar,
            keyframeID: keyframeID,
            fileFingerprint: FileFingerprint(byteCount: 1024, modificationDate: timestamp, digest: "abc123")
        )
        let keyframe = Keyframe(
            id: keyframeID,
            frameID: frameID,
            parameters: ParameterSet(values: [
                .exposure: ParameterSample(value: 0.25, origin: .keyframe, isLocked: false)
            ]),
            isLocked: false
        )
        let scanSummary = SequenceScanSummary(
            workingDirectoryPathHint: "/Volumes/TestSequence",
            photoCount: 1,
            keyframeCount: 1,
            unreadableRatingCount: 0,
            unsupportedFileCount: 0,
            scannedAt: timestamp
        )
        return TimeLapseProject(
            schemaVersion: ProjectSchema.currentVersion,
            id: projectID,
            name: name,
            sourceBookmark: Data([1, 2, 3]),
            sourceRootPathHint: "/Volumes/TestSequence",
            frames: [frame],
            keyframes: [keyframe],
            metadataBaselines: [
                frameID: RawMetadataDocument(
                    data: Data("<opaque-original-xmp/>".utf8),
                    mediaType: "application/rdf+xml",
                    sourceFingerprint: frame.fileFingerprint
                )
            ],
            workingDirectoryBookmark: Data([4, 5, 6]),
            lastScanSummary: scanSummary,
            overrides: [],
            settings: ProjectSettings(
                timeBasis: .frameIndex,
                defaultInterpolation: .linear,
                missingValuePolicy: .useDefault,
                parameterDefaults: [.exposure: 0],
                exportMode: .updateExistingSidecars
            ),
            createdAt: timestamp,
            modifiedAt: timestamp
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurvePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func expectAsyncError<ExpectedError: Error & Equatable>(
        _ expectedError: ExpectedError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected operation to throw \(expectedError).")
        } catch let actualError as ExpectedError {
            #expect(actualError == expectedError)
        } catch {
            Issue.record("Operation threw an unexpected error: \(error).")
        }
    }
}

private struct SimulatedDiskFullWriter: ProjectFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw POSIXError(.ENOSPC)
    }
}