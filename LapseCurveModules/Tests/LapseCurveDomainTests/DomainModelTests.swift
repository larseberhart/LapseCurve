import Foundation
import Testing
@testable import LapseCurveDomain

struct DomainModelTests {
    @Test func projectCodableRoundTrip() throws {
        let project = ValidProjectFixture.makeProject()
        let encodedProject = try JSONEncoder().encode(project)
        let decodedProject = try JSONDecoder().decode(TimeLapseProject.self, from: encodedProject)

        #expect(decodedProject == project)
    }

    @Test func validProjectPassesValidation() throws {
        try ProjectValidator.validate(
            ValidProjectFixture.makeProject(),
            parameterDefinitions: [exposureDefinition]
        )
    }

    @Test func duplicateSequencePositionsAreRejected() throws {
        var project = ValidProjectFixture.makeProject()
        let secondFrame = ImageFrame(
            id: FrameID(rawValue: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!),
            relativePath: "frame-002.dng",
            sequenceIndex: 0
        )
        project.frames.append(secondFrame)

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func negativeSequencePositionsAreRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.frames[0].sequenceIndex = -1

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func duplicateKeyframesForOneFrameAreRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.keyframes.append(
            Keyframe(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                frameID: ValidProjectFixture.frameID,
                parameters: ParameterSet(),
                isLocked: false
            )
        )

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func missingKeyframeFramesAreRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.keyframes[0].frameID = FrameID(
            rawValue: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        )

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func metadataBaselinesMustReferenceExistingFrames() throws {
        var project = ValidProjectFixture.makeProject()
        project.metadataBaselines[FrameID(rawValue: UUID())] = RawMetadataDocument(
            data: Data("<packet/>".utf8),
            mediaType: "application/rdf+xml",
            sourceFingerprint: nil
        )

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func frameAndKeyframeIdentityMustAgree() throws {
        var project = ValidProjectFixture.makeProject()
        project.frames[0].keyframeID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func invalidCaptureMetadataIsRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.frames[0].captureMetadata.iso = .infinity

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func unsupportedSchemaIsRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.schemaVersion = ProjectSchema.currentVersion + 1

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project)
        }
    }

    @Test func nonFiniteAndOutOfRangeParameterValuesAreRejected() throws {
        var project = ValidProjectFixture.makeProject()
        project.keyframes[0].parameters.values[.exposure]?.value = .infinity

        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project, parameterDefinitions: [exposureDefinition])
        }

        project.keyframes[0].parameters.values[.exposure]?.value = 8
        #expect(throws: ProjectValidationError.self) {
            try ProjectValidator.validate(project, parameterDefinitions: [exposureDefinition])
        }
    }

    private var exposureDefinition: ParameterDefinition {
        ParameterDefinition(
            parameter: .exposure,
            namespaceURI: "http://ns.adobe.com/camera-raw-settings/1.0/",
            xmpTag: "Exposure2012",
            unit: .exposureEV,
            interpolation: .linear,
            validRange: -5...5,
            writable: false,
            compatibilityNotes: "Candidate only; WP-02 fixture verification required."
        )
    }
}