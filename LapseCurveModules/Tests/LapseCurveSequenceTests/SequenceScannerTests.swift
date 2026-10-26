import Foundation
import LapseCurveDomain
import Testing
@testable import LapseCurveSequence

struct SequenceScannerTests {
    @Test func onlyExactOneStarIsAKeyframe() {
        for rating in [-1, 0, 2, 5] {
            let resolution = KeyframeRatingDetector.resolve(
                embedded: RatingMetadataRead(status: .missing),
                sidecar: RatingMetadataRead(status: .readable, values: [rating]),
                frameID: testFrameID
            )
            #expect(!resolution.isKeyframe)
            #expect(resolution.rating == rating)
        }

        let oneStar = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .missing),
            sidecar: RatingMetadataRead(status: .readable, values: [1]),
            frameID: testFrameID
        )
        #expect(oneStar.isKeyframe)
    }

    @Test func missingUnreadableAndConflictingRatingsAreNotKeyframes() {
        let missing = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .missing),
            sidecar: RatingMetadataRead(status: .missing),
            frameID: testFrameID
        )
        #expect(missing.isUnreadable)
        #expect(!missing.isKeyframe)

        let malformed = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .malformed),
            sidecar: RatingMetadataRead(status: .missing),
            frameID: testFrameID
        )
        #expect(malformed.isUnreadable)
        #expect(!malformed.isKeyframe)

        let conflict = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .readable, values: [1]),
            sidecar: RatingMetadataRead(status: .readable, values: [0]),
            frameID: testFrameID
        )
        #expect(conflict.rating == 0)
        #expect(!conflict.isKeyframe)
        #expect(!conflict.isUnreadable)
        #expect(conflict.source == .xmpSidecar)
        #expect(conflict.warnings.contains { $0.code == "ratingSourceConflict" })

        let malformedWithValue = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .missing),
            sidecar: RatingMetadataRead(status: .malformed, values: [1]),
            frameID: testFrameID
        )
        #expect(malformedWithValue.rating == nil)
        #expect(!malformedWithValue.isKeyframe)

        let malformedWithoutValue = KeyframeRatingDetector.resolve(
            embedded: RatingMetadataRead(status: .malformed),
            sidecar: RatingMetadataRead(status: .missing),
            frameID: testFrameID
        )
        #expect(malformedWithoutValue.rating == nil)
        #expect(!malformedWithoutValue.isKeyframe)
    }

    @Test func sidecarResolutionIsCaseInsensitiveAndDetectsACR() {
        let imageURL = URL(fileURLWithPath: "/sequence/Frame2.NEF")
        let sidecarURLs = [
            URL(fileURLWithPath: "/sequence/frame2.XMP"),
            URL(fileURLWithPath: "/sequence/FRAME2.ACR")
        ]

        let resolution = SidecarResolver.resolve(for: imageURL, among: sidecarURLs)
        #expect(resolution.xmpURL?.lastPathComponent == "frame2.XMP")
        #expect(resolution.hasACRSidecar)
        #expect(!resolution.hasAmbiguousXMP)
    }

    @Test func sidecarResolutionRejectsAmbiguousXMPMatches() {
        let imageURL = URL(fileURLWithPath: "/sequence/frame2.NEF")
        let sidecarURLs = [
            URL(fileURLWithPath: "/sequence/frame2.xmp"),
            URL(fileURLWithPath: "/sequence/FRAME2.XMP")
        ]

        let resolution = SidecarResolver.resolve(for: imageURL, among: sidecarURLs)

        #expect(resolution.xmpURL == nil)
        #expect(resolution.hasAmbiguousXMP)
    }

    @Test func orderingUsesCaptureTimeThenNaturalFilename() {
        let earlierFrame = makeFrame("frame10.dng", index: 0, captureTime: Date(timeIntervalSince1970: 10))
        let laterFrame2 = makeFrame("frame2.dng", index: 1, captureTime: Date(timeIntervalSince1970: 20))
        let sameTimeFrame10 = makeFrame("frame10.dng", index: 2, captureTime: Date(timeIntervalSince1970: 30))
        let sameTimeFrame2 = makeFrame("frame2.dng", index: 3, captureTime: Date(timeIntervalSince1970: 30))

        let timeSorted = SequenceOrdering.sort([laterFrame2, earlierFrame], sortByCaptureTime: true)
        #expect(timeSorted.map(\.relativePath) == ["frame10.dng", "frame2.dng"])

        let filenameSorted = SequenceOrdering.sort(
            [sameTimeFrame10, sameTimeFrame2],
            sortByCaptureTime: true
        )
        #expect(filenameSorted.map(\.relativePath) == ["frame2.dng", "frame10.dng"])
    }

    @Test func timestampOrderingWarnsForMissingAndDuplicateTimes() {
        let repeatedTimestamp = Date(timeIntervalSince1970: 30)
        let frames = [
            makeFrame("frame1.dng", index: 0, captureTime: nil),
            makeFrame("frame2.dng", index: 1, captureTime: repeatedTimestamp),
            makeFrame("frame3.dng", index: 2, captureTime: repeatedTimestamp)
        ]

        let warnings = SequenceOrdering.timestampWarnings(for: frames, sortByCaptureTime: true)

        #expect(warnings.filter { $0.code == "captureTimeMissing" }.count == 1)
        #expect(warnings.filter { $0.code == "captureTimeDuplicate" }.count == 2)
    }

    @Test func scanWarnsForMissingSidecarAndNeverChangesSource() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let imageURL = workingDirectory.appendingPathComponent("frame1.dng")
        let sourceBytes = Data("raw-placeholder".utf8)
        try sourceBytes.write(to: imageURL)
        let scanner = SequenceScanner(metadataReader: StubMetadataReader(defaultSnapshot: FrameMetadataSnapshot()))

        let result = try await scanner.scan(
            directory: workingDirectory,
            options: SequenceScanOptions(supportedExtensions: ["dng"])
        )

        #expect(result.summary.photoCount == 1)
        #expect(result.summary.keyframeCount == 0)
        #expect(result.summary.unreadableRatingCount == 1)
        #expect(result.warnings.contains { $0.code == "xmpSidecarMissing" })
        #expect(try Data(contentsOf: imageURL) == sourceBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: workingDirectory.path) == ["frame1.dng"])
    }

    @Test func recursiveScanResolvesSidecarBesideNestedImage() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let nestedDirectory = workingDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: false)
        let imageURL = nestedDirectory.appendingPathComponent("frame.dng")
        let sidecarURL = nestedDirectory.appendingPathComponent("frame.xmp")
        try Data("raw".utf8).write(to: imageURL)
        try Data("xmp".utf8).write(to: sidecarURL)

        let scanner = SequenceScanner(metadataReader: StubMetadataReader(
            snapshotsByImageName: [
                "frame.dng": FrameMetadataSnapshot(
                    sidecarRating: RatingMetadataRead(status: .readable, values: [1]),
                    metadataStatus: .valid
                )
            ]
        ))
        let result = try await scanner.scan(
            directory: workingDirectory,
            options: SequenceScanOptions(recursive: true, supportedExtensions: ["dng"])
        )

        #expect(result.frames.count == 1)
        #expect(result.frames[0].keyframeID != nil)
        #expect(!result.warnings.contains { $0.code == "xmpSidecarMissing" })
    }

    @Test func scansCountsOrdersAndRetainsFrameIdentityOnRescan() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let frame2URL = workingDirectory.appendingPathComponent("frame2.dng")
        let frame10URL = workingDirectory.appendingPathComponent("frame10.dng")
        let sourceBytes = Data("raw-placeholder".utf8)
        try sourceBytes.write(to: frame2URL)
        try sourceBytes.write(to: frame10URL)
        try Data("xmp".utf8).write(to: workingDirectory.appendingPathComponent("frame2.xmp"))
        try Data("acr".utf8).write(to: workingDirectory.appendingPathComponent("frame2.acr"))
        try Data("xmp".utf8).write(to: workingDirectory.appendingPathComponent("frame10.xmp"))
        try Data("not an image".utf8).write(to: workingDirectory.appendingPathComponent("notes.txt"))

        let reader = StubMetadataReader(snapshotsByImageName: [
            "frame2.dng": FrameMetadataSnapshot(
                sidecarRating: RatingMetadataRead(status: .readable, values: [1]),
                metadataStatus: .valid,
                developmentParameters: ParameterSet(values: [
                    .exposure: ParameterSample(value: 1.25, origin: .importedSidecar, isLocked: false)
                ])
            ),
            "frame10.dng": FrameMetadataSnapshot(
                sidecarRating: RatingMetadataRead(status: .readable, values: [2]),
                metadataStatus: .valid
            )
        ])
        let scanner = SequenceScanner(metadataReader: reader)
        let firstResult = try await scanner.scan(
            directory: workingDirectory,
            options: SequenceScanOptions(supportedExtensions: ["dng"])
        )

        #expect(firstResult.frames.map(\.relativePath) == ["frame2.dng", "frame10.dng"])
        #expect(firstResult.summary.photoCount == 2)
        #expect(firstResult.summary.keyframeCount == 1)
        #expect(firstResult.summary.unreadableRatingCount == 0)
        #expect(firstResult.summary.unsupportedFileCount == 1)
        #expect(firstResult.warnings.contains { $0.code == "acrSidecarUnsupported" })
        #expect(firstResult.frames[0].keyframeID != nil)
        #expect(firstResult.frames[1].keyframeID == nil)
        #expect(firstResult.keyframes.count == 1)
        #expect(firstResult.keyframes[0].parameters.values[.exposure]?.value == 1.25)

        let secondResult = try await scanner.scan(
            directory: workingDirectory,
            options: SequenceScanOptions(
                supportedExtensions: ["dng"],
                previousFrames: firstResult.frames
            )
        )

        #expect(secondResult.frames.map(\.id) == firstResult.frames.map(\.id))
        #expect(try Data(contentsOf: frame2URL) == sourceBytes)
        #expect(try Data(contentsOf: frame10URL) == sourceBytes)
    }

    @Test func largeSequenceScanPreservesOrderingAndSourceBytes() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let frameCount = 512
        for index in 0..<frameCount {
            let fileName = String(format: "frame-%04d.dng", index)
            try Data([UInt8(index % 256)]).write(to: workingDirectory.appendingPathComponent(fileName))
        }

        let scanner = SequenceScanner(metadataReader: StubMetadataReader())
        let result = try await scanner.scan(
            directory: workingDirectory,
            options: SequenceScanOptions(supportedExtensions: ["dng"], sortByCaptureTime: false)
        )

        #expect(result.frames.count == frameCount)
        #expect(result.frames.first?.relativePath == "frame-0000.dng")
        #expect(result.frames.last?.relativePath == "frame-0511.dng")
        #expect(result.frames.map(\.sequenceIndex) == Array(0..<frameCount))
        #expect(try Data(contentsOf: workingDirectory.appendingPathComponent("frame-0000.dng")) == Data([0]))
        #expect(try Data(contentsOf: workingDirectory.appendingPathComponent("frame-0511.dng")) == Data([UInt8(511 % 256)]))
    }

    @Test func preCancelledScanStopsBeforeReadingMetadata() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        try Data("source".utf8).write(to: workingDirectory.appendingPathComponent("frame.dng"))
        let scanner = SequenceScanner(metadataReader: StubMetadataReader())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan(
                directory: workingDirectory,
                options: SequenceScanOptions(supportedExtensions: ["dng"])
            )
        }

        do {
            _ = try await task.value
            Issue.record("Expected a cancelled scan to stop before processing files.")
        } catch is CancellationError {
            #expect(try Data(contentsOf: workingDirectory.appendingPathComponent("frame.dng")) == Data("source".utf8))
        }
    }

    @Test func cancellationDuringMetadataReadDoesNotReturnACompletedScan() async throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let imageURL = workingDirectory.appendingPathComponent("frame.dng")
        let sourceBytes = Data("source".utf8)
        try sourceBytes.write(to: imageURL)
        let gate = MetadataReadGate()
        let scanner = SequenceScanner(metadataReader: GatedMetadataReader(gate: gate))
        let task = Task {
            try await scanner.scan(
                directory: workingDirectory,
                options: SequenceScanOptions(supportedExtensions: ["dng"])
            )
        }

        await gate.waitUntilReadStarts()
        task.cancel()
        await gate.releaseRead()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation during metadata reading to stop the scan.")
        } catch is CancellationError {
            #expect(try Data(contentsOf: imageURL) == sourceBytes)
        }
    }

    @Test func unreadableDirectoryReturnsRecoverableScanError() async throws {
        let parentDirectory = try makeTemporaryDirectory()
        let inaccessibleDirectory = parentDirectory.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: inaccessibleDirectory, withIntermediateDirectories: false)
        try Data("source".utf8).write(to: inaccessibleDirectory.appendingPathComponent("frame.dng"))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessibleDirectory.path)
            try? FileManager.default.removeItem(at: parentDirectory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inaccessibleDirectory.path)

        let scanner = SequenceScanner(metadataReader: StubMetadataReader())
        do {
            _ = try await scanner.scan(
                directory: inaccessibleDirectory,
                options: SequenceScanOptions(supportedExtensions: ["dng"])
            )
            Issue.record("Expected an unreadable directory to fail scanning.")
        } catch let error as SequenceScanError {
            #expect(error == .unreadableDirectory)
        }
    }

    private var testFrameID: FrameID {
        FrameID(rawValue: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)
    }

    private func makeFrame(_ relativePath: String, index: Int, captureTime: Date?) -> ImageFrame {
        ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: relativePath,
            sequenceIndex: index,
            captureTime: captureTime,
            captureTimeSource: captureTime == nil ? .unavailable : .exif
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveSequenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private struct StubMetadataReader: SequenceMetadataReading {
    var snapshotsByImageName: [String: FrameMetadataSnapshot] = [:]
    var defaultSnapshot = FrameMetadataSnapshot(metadataStatus: .partial)

    func readMetadata(imageURL: URL, sidecarURL: URL?) async -> FrameMetadataSnapshot {
        snapshotsByImageName[imageURL.lastPathComponent] ?? defaultSnapshot
    }
}

private struct GatedMetadataReader: SequenceMetadataReading {
    let gate: MetadataReadGate

    func readMetadata(imageURL: URL, sidecarURL: URL?) async -> FrameMetadataSnapshot {
        await gate.pauseRead()
        return FrameMetadataSnapshot()
    }
}

private actor MetadataReadGate {
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var hasStartedRead = false

    func pauseRead() async {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            hasStartedRead = true
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func waitUntilReadStarts() async {
        guard !hasStartedRead else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseRead() {
        readContinuation?.resume()
        readContinuation = nil
    }
}