import Foundation
@testable import LapseCurveDomain

enum ValidProjectFixture {
    static let projectID = ProjectID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    static let frameID = FrameID(rawValue: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    static let keyframeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeProject() -> TimeLapseProject {
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
        return TimeLapseProject(
            schemaVersion: ProjectSchema.currentVersion,
            id: projectID,
            name: "Sample Sequence",
            sourceRootPathHint: "/tmp/sample-sequence",
            frames: [frame],
            keyframes: [keyframe],
            metadataBaselines: [
                frameID: RawMetadataDocument(
                    data: Data("<packet/>".utf8),
                    mediaType: "application/rdf+xml",
                    sourceFingerprint: frame.fileFingerprint
                )
            ],
            overrides: [],
            settings: ProjectSettings(
                timeBasis: .frameIndex,
                defaultInterpolation: .linear,
                missingValuePolicy: .warn,
                exportMode: .updateExistingSidecars
            ),
            createdAt: timestamp,
            modifiedAt: timestamp
        )
    }
}