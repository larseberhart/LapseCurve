import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import LapseCurveDomain
import LapseCurveSequence
@testable import LapseCurveMetadata

struct ImageIOMetadataReaderTests {
    @Test func readsEmbeddedOneStarRating() async throws {
        let imageData = try makeJPEGWithEmbeddedRating(1)
        let imageURL = try writeTemporaryImage(imageData)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: imageURL, sidecarURL: nil)

        #expect(snapshot.embeddedRating.status == .readable)
        #expect(snapshot.embeddedRating.values == [1])
        #expect(snapshot.sidecarRating.status == .missing)
        #expect(snapshot.captureMetadata.shutterDurationSeconds == 1.0 / 60.0)
        #expect(snapshot.captureMetadata.apertureFNumber == 4.0)
        #expect(snapshot.captureMetadata.iso == 400.0)
        #expect(snapshot.captureMetadata.focalLengthMM == 50.0)
        #expect(snapshot.captureTime != nil)
        #expect(snapshot.captureTimeSource == .exif)
    }

    @Test func readsDevelopmentValuesAndOpaqueBaselineFromExistingSidecar() async throws {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "Lightroom15_6Sample", withExtension: "xmp")
        )
        let imageURL = URL(fileURLWithPath: "/tmp/no-image-data-expected.NEF")

        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: imageURL, sidecarURL: fixtureURL)

        #expect(snapshot.developmentParameters.values[.exposure]?.value == 1.05)
        #expect(snapshot.developmentParameters.values[.contrast]?.value == 100)
        #expect(snapshot.developmentParameters.values[.exposure]?.origin == .importedSidecar)
        #expect(snapshot.rawMetadataDocument?.data == (try Data(contentsOf: fixtureURL)))
    }

    @Test func doesNotAssumeTimezoneForExifCaptureTime() async throws {
        let imageData = try makeJPEGWithEmbeddedRating(0, includeTimezoneOffset: false)
        let imageURL = try writeTemporaryImage(imageData)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: imageURL, sidecarURL: nil)

        #expect(snapshot.captureTime == nil)
        #expect(snapshot.captureTimeSource == .unavailable)
    }

    @Test func missingSidecarIsReportedWithoutCreatingOne() async throws {
        let imageData = try makeJPEGWithEmbeddedRating(0)
        let imageURL = try writeTemporaryImage(imageData)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")

        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: imageURL, sidecarURL: nil)

        #expect(snapshot.sidecarRating.status == .missing)
        #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    @Test func malformedExistingSidecarIsReportedAsMalformed() async throws {
        let imageData = try makeJPEGWithEmbeddedRating(0)
        let imageURL = try writeTemporaryImage(imageData)
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("xmp")
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }
        try Data("<broken".utf8).write(to: sidecarURL)

        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: imageURL, sidecarURL: sidecarURL)

        #expect(snapshot.sidecarRating.status == .malformed)
        #expect(snapshot.warnings.contains { $0.code == "xmpSidecarUnreadable" })
    }

    @Test func oneStarSidecarRatingIdentifiesKeyframeWhenEmbeddedRatingDiffers() async throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveRatingConflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let imageURL = workingDirectory.appendingPathComponent("frame.jpg")
        let sidecarURL = workingDirectory.appendingPathComponent("frame.xmp")
        try makeJPEGWithEmbeddedRating(0).write(to: imageURL)
        try Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="1"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8).write(to: sidecarURL)

        let result = try await SequenceScanner(metadataReader: ImageIOMetadataReader()).scan(
            directory: workingDirectory,
            options: SequenceScanOptions(supportedExtensions: ["jpg"], sortByCaptureTime: false)
        )

        #expect(result.frames.count == 1)
        #expect(result.frames[0].rating == 1)
        #expect(result.frames[0].keyframeID != nil)
        #expect(result.frames[0].ratingSource == .xmpSidecar)
        #expect(result.frames[0].metadataStatus == .conflict)
        #expect(result.warnings.contains { $0.code == "ratingSourceConflict" })
    }

    @Test func keyframeWithoutCameraRawSettingsGetsNeutralAdjustments() async throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveNeutralKeyframe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let imageURL = workingDirectory.appendingPathComponent("frame.jpg")
        let sidecarURL = workingDirectory.appendingPathComponent("frame.xmp")
        try makeJPEGWithEmbeddedRating(0).write(to: imageURL)
        try Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="1"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8).write(to: sidecarURL)

        let result = try await SequenceScanner(metadataReader: ImageIOMetadataReader()).scan(
            directory: workingDirectory,
            options: SequenceScanOptions(supportedExtensions: ["jpg"], sortByCaptureTime: false)
        )

        let keyframe = try #require(result.keyframes.first)
        #expect(result.frames.first?.keyframeID != nil)
        for parameter in [DevelopmentParameter.exposure, .contrast, .highlights, .shadows, .whites, .blacks, .vibrance, .saturation, .texture, .clarity, .dehaze] {
            #expect(keyframe.parameters.values[parameter]?.value == 0)
        }
        #expect(keyframe.parameters.values[.exposure]?.origin == .assumedNeutral)
        #expect(keyframe.parameters.values[.temperature] == nil)
        #expect(keyframe.parameters.values[.tint] == nil)
        #expect(keyframe.parameters.values[.perspectiveScale] == nil)
        #expect(keyframe.parameters.values[.sharpness]?.value == 40)
    }

    @Test func allListedCameraRawFieldsRoundTripThroughReaderAndWriter() async throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveAllCRSFields-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let sourceURL = workingDirectory.appendingPathComponent("intermediate.NEF")
        let sidecarURL = workingDirectory.appendingPathComponent("intermediate.xmp")
        let sourceBytes = Data("raw-source-placeholder".utf8)
        try sourceBytes.write(to: sourceURL)

        let definitions = XMPFieldRegistry.candidateDevelopmentParameters
        var values = Dictionary(uniqueKeysWithValues: definitions.map { ($0.parameter, 0.0) })
        values[.temperature] = 5933
        values[.tint] = 22
        values[.exposure] = 0.85
        values[.contrast] = 5
        values[.highlights] = -64
        values[.shadows] = 44
        values[.whites] = 11
        values[.blacks] = -10
        values[.texture] = 8
        values[.clarity] = 4
        values[.vibrance] = 20
        values[.saturation] = 5
        values[.sharpness] = 56
        values[.sharpenRadius] = 2
        values[.luminanceSmoothing] = 51
        values[.colorGradeMidtoneHue] = 28

        let sourcePacket = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmp:Rating="0" crs:WhiteBalance="As Shot"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        let frame = ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: "intermediate.NEF",
            sequenceIndex: 1,
            metadataStatus: .valid,
            rating: 0,
            ratingSource: .xmpSidecar
        )

        let output = try XMPPacketWriter().updating(
            sourceData: sourcePacket,
            values: values,
            for: frame,
            using: definitions
        )
        try output.write(to: sidecarURL)
        let packet = try XMPPacketReader().read(output)
        let cameraRawProperties = packet.properties.filter {
            $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace
        }
        let actualTagNames = Set(cameraRawProperties.map(\.localName))
        let missingTagNames = definitions.map(\.xmpTag).filter { !actualTagNames.contains($0) }
        let snapshot = await ImageIOMetadataReader().readMetadata(imageURL: sourceURL, sidecarURL: sidecarURL)

        #expect(definitions.count == 83)
        #expect(cameraRawProperties.count == definitions.count + 1)
        #expect(missingTagNames.isEmpty)
        #expect(packet.properties.first { $0.localName == "WhiteBalance" }?.value == "Custom")
        #expect(snapshot.developmentParameters.values.count == definitions.count)
        #expect(snapshot.developmentParameters.values[.exposure]?.value == 0.85)
        #expect(snapshot.developmentParameters.values[.temperature]?.value == 5933)
        #expect(snapshot.developmentParameters.values[.tint]?.value == 22)
        #expect(snapshot.developmentParameters.values[.sharpness]?.value == 56)
        #expect(snapshot.developmentParameters.values[.colorGradeMidtoneHue]?.value == 28)
        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
    }

    private func makeJPEGWithEmbeddedRating(_ rating: Int, includeTimezoneOffset: Bool = true) throws -> Data {
        let pixelBytes = Data([0, 0, 0, 255])
        let provider = try #require(CGDataProvider(data: pixelBytes as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(
            CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let imageMetadata = CGImageMetadataCreateMutable()
        let ratingTag = try #require(
            CGImageMetadataTagCreate(
                "http://ns.adobe.com/xap/1.0/" as CFString,
                "xmp" as CFString,
                "Rating" as CFString,
                .string,
                String(rating) as NSString
            )
        )
        #expect(CGImageMetadataSetTagWithPath(imageMetadata, nil, "xmp:Rating" as CFString, ratingTag))

        let outputData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(outputData, UTType.jpeg.identifier as CFString, 1, nil)
        )
        var exifProperties: [CFString: Any] = [
            kCGImagePropertyExifExposureTime: 1.0 / 60.0,
            kCGImagePropertyExifFNumber: 4.0,
            kCGImagePropertyExifISOSpeedRatings: [400],
            kCGImagePropertyExifFocalLength: 50.0,
            kCGImagePropertyExifDateTimeOriginal: "2026:10:02 14:22:12"
        ]
        if includeTimezoneOffset {
            exifProperties[kCGImagePropertyExifOffsetTimeOriginal] = "+02:00"
        }
        let destinationOptions: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exifProperties
        ]
        CGImageDestinationAddImageAndMetadata(
            destination,
            image,
            imageMetadata,
            destinationOptions as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return outputData as Data
    }

    private func writeTemporaryImage(_ data: Data) throws -> URL {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurveMetadata-\(UUID().uuidString).jpg")
        try data.write(to: imageURL)
        return imageURL
    }
}