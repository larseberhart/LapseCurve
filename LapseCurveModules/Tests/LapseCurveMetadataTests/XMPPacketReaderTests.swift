import Foundation
import Testing
import LapseCurveDomain
@testable import LapseCurveMetadata

struct XMPPacketReaderTests {
    @Test func readsNamespaceAwarePropertiesAndRetainsExactBytes() throws {
        let originalData = try sampleFixtureData()
        let packet = try XMPPacketReader().read(originalData)

        #expect(packet.originalData == originalData)
        #expect(packet.properties.contains {
            $0.namespaceURI == "http://ns.adobe.com/camera-raw-settings/1.0/"
                && $0.localName == "Exposure2012"
                && $0.value == "+1.05"
        })
        #expect(packet.properties.contains {
            $0.namespaceURI == "http://ns.adobe.com/camera-raw-settings/1.0/"
                && $0.localName == "Contrast2012"
                && $0.value == "+100"
        })
        #expect(property("Version", namespace: cameraRawNamespace, in: packet)?.value == "18.7")
        #expect(property("ProcessVersion", namespace: cameraRawNamespace, in: packet)?.value == "15.4")
        #expect(property("Rating", namespace: xmpNamespace, in: packet)?.value == "1")
        #expect(packet.properties.contains {
            $0.namespaceURI == "https://example.invalid/opaque/"
                && $0.localName == "PrivateAttribute"
                && $0.value == "keep-me"
        })
        #expect(packet.properties.contains {
            $0.namespaceURI == "https://example.invalid/opaque/"
                && $0.localName == "Nested"
                && $0.value.contains("opaque <payload> & text")
        })
    }

    @Test func experimentalRegistryCoversTheExpandedCameraRawParameterSet() throws {
        let packet = try XMPPacketReader().read(sampleFixtureData())
        let definitions = XMPFieldRegistry.candidateDevelopmentParameters

        let allowedTags: Set<String> = [
            "Temperature", "Tint", "Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012",
            "Whites2012", "Blacks2012", "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation",
            "ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights",
            "ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit",
            "Sharpness", "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking",
            "LuminanceSmoothing", "LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast",
            "ColorNoiseReduction", "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness",
            "HueAdjustmentRed", "HueAdjustmentOrange", "HueAdjustmentYellow", "HueAdjustmentGreen",
            "HueAdjustmentAqua", "HueAdjustmentBlue", "HueAdjustmentPurple", "HueAdjustmentMagenta",
            "SaturationAdjustmentRed", "SaturationAdjustmentOrange", "SaturationAdjustmentYellow",
            "SaturationAdjustmentGreen", "SaturationAdjustmentAqua", "SaturationAdjustmentBlue",
            "SaturationAdjustmentPurple", "SaturationAdjustmentMagenta",
            "LuminanceAdjustmentRed", "LuminanceAdjustmentOrange", "LuminanceAdjustmentYellow",
            "LuminanceAdjustmentGreen", "LuminanceAdjustmentAqua", "LuminanceAdjustmentBlue",
            "LuminanceAdjustmentPurple", "LuminanceAdjustmentMagenta",
            "SplitToningShadowHue", "SplitToningShadowSaturation", "SplitToningHighlightHue",
            "SplitToningHighlightSaturation", "SplitToningBalance",
            "ColorGradeMidtoneHue", "ColorGradeMidtoneSat", "ColorGradeShadowLum", "ColorGradeMidtoneLum",
            "ColorGradeHighlightLum", "ColorGradeBlending", "ColorGradeGlobalHue", "ColorGradeGlobalSat",
            "ColorGradeGlobalLum", "AutoLateralCA",
            "DefringePurpleAmount", "DefringePurpleHueLo", "DefringePurpleHueHi",
            "DefringeGreenAmount", "DefringeGreenHueLo", "DefringeGreenHueHi",
            "GrainAmount", "Glow", "RedHue", "RedSaturation", "GreenHue", "GreenSaturation",
            "BlueHue", "BlueSaturation"
        ]
        #expect(definitions.count == allowedTags.count)
        #expect(Set(definitions.map(\.xmpTag)) == allowedTags)
        #expect(definitions.allSatisfy { $0.writable && $0.validRange == nil })
        #expect(definitions.allSatisfy { $0.namespaceURI == XMPFieldRegistry.cameraRawSettingsNamespace })
        let sampleDefinitions = definitions.filter {
            [.exposure, .contrast, .highlights, .shadows, .temperature, .tint].contains($0.parameter)
        }
        #expect(sampleDefinitions.allSatisfy { definition in
            packet.properties.contains {
                $0.namespaceURI == definition.namespaceURI && $0.localName == definition.xmpTag
            }
        })
    }

    @Test func duplicatePropertiesRemainDistinct() throws {
        let data = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">
          <rdf:Description crs:Exposure2012="0.5">
            <crs:Exposure2012>1.0</crs:Exposure2012>
          </rdf:Description>
        </rdf:RDF>
        """.utf8)

        let packet = try XMPPacketReader().read(data)
        let exposureProperties = packet.properties.filter {
            $0.namespaceURI == "http://ns.adobe.com/camera-raw-settings/1.0/"
                && $0.localName == "Exposure2012"
        }

        #expect(exposureProperties.count == 2)
    }

    @Test func serializationRetainsUnknownSemanticContent() throws {
        let originalData = try sampleFixtureData()
        let originalPacket = try XMPPacketReader().read(originalData)
        let document = try XMLDocument(
            data: originalData,
            options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
        )
        let serializedData = document.xmlData(options: .nodePreserveAll)
        let serializedPacket = try XMPPacketReader().read(serializedData)
        let preservedNamespaces: Set<String> = [
            "https://example.invalid/opaque/",
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        ]
        let originalUnknownProperties = Set(originalPacket.properties.filter {
            preservedNamespaces.contains($0.namespaceURI)
        })
        let serializedUnknownProperties = Set(serializedPacket.properties.filter {
            preservedNamespaces.contains($0.namespaceURI)
        })

        #expect(serializedUnknownProperties == originalUnknownProperties)
        #expect(String(decoding: serializedData, as: UTF8.self).contains("Preserve this packet comment"))
        #expect(String(decoding: serializedData, as: UTF8.self).contains("opaque <payload> & text"))
    }

    @Test func rejectsMalformedOrUnsupportedDocuments() {
        #expect(throws: XMPReadError.self) {
            try XMPPacketReader().read(Data("<x:xmpmeta>".utf8))
        }
        #expect(throws: XMPReadError.self) {
            try XMPPacketReader().read(Data("<root/>".utf8))
        }
    }

    @Test func rejectsOversizedPacketsAndDocumentTypes() throws {
        let limitedReader = XMPPacketReader(maximumPacketSizeBytes: 8)
        #expect(throws: XMPReadError.self) {
            try limitedReader.read(Data("<rdf:RDF/>".utf8))
        }

        let documentTypePacket = Data("""
        <!DOCTYPE rdf:RDF [<!ENTITY payload SYSTEM "file:///etc/passwd">]>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description>&payload;</rdf:Description>
        </rdf:RDF>
        """.utf8)
        #expect(throws: XMPReadError.self) {
            try XMPPacketReader().read(documentTypePacket)
        }

        let utf16DocumentType = "<!DOCTYPE rdf:RDF><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"/>"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let encodedPacket = try #require(utf16DocumentType.data(using: encoding))
            #expect(throws: XMPReadError.documentTypeNotAllowed) {
                try XMPPacketReader().read(encodedPacket)
            }
        }
    }

    @Test func rejectsExcessiveXMLNesting() {
        var nestedElement = "<rdf:Description/>"
        for _ in 0..<130 {
            nestedElement = "<node>\(nestedElement)</node>"
        }
        let packet = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\(nestedElement)</rdf:RDF>
        """.utf8)

        #expect(throws: XMPReadError.maximumDepthExceeded) {
            try XMPPacketReader().read(packet)
        }
    }

    @Test func rejectsExcessiveScalarPropertyCount() {
        var attributes = ""
        for index in 0...100_000 {
            attributes += String(format: "p:value%06d=\"x\" ", index)
        }
        let packet = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:p="urn:test"><rdf:Description \(attributes)/></rdf:RDF>
        """.utf8)

        #expect(throws: XMPReadError.maximumPropertyCountExceeded) {
            try XMPPacketReader().read(packet)
        }
    }

    @Test func writerUpdatesMappedCRSValuesAndPreservesOtherMetadata() throws {
        let sourceData = try intermediateSampleData()
        let frame = ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: "A0062.NEF",
            sequenceIndex: 1,
            metadataStatus: .valid,
            rating: 0,
            ratingSource: .xmpSidecar
        )
        let output = try XMPPacketWriter().updating(
            sourceData: sourceData,
            values: [.exposure: 0.25, .contrast: -12],
            for: frame,
            using: [exposureDefinition(writable: true), contrastDefinition(writable: true)]
        )
        let packet = try XMPPacketReader().read(output)

        #expect(property("Exposure2012", namespace: cameraRawNamespace, in: packet)?.value == "+0.25")
        #expect(property("Contrast2012", namespace: cameraRawNamespace, in: packet)?.value == "-12")
        #expect(property("Exposure2012", namespace: cameraRawDefaultsNamespace, in: packet)?.value == "0.00")
        #expect(property("CreatorTool", namespace: xmpNamespace, in: packet)?.value == "Adobe Photoshop Lightroom Classic 15.6")
        #expect(property("Rating", namespace: xmpNamespace, in: packet)?.value == "0")
        #expect(property("PrivateAttribute", namespace: opaqueNamespace, in: packet)?.value == "keep-me")
        #expect(String(decoding: output, as: UTF8.self).contains("Preserve this packet comment"))
        #expect(String(decoding: output, as: UTF8.self).contains("opaque <payload> & text"))
    }

    @Test func writerAddsMissingCRSPropertiesToExistingDescription() throws {
        let sourceData = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:custom="urn:custom" xmp:Rating="0" custom:Keep="yes"/>
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
            sourceData: sourceData,
            values: [.exposure: 1.05],
            for: frame,
            using: [exposureDefinition(writable: true)]
        )
        let packet = try XMPPacketReader().read(output)
        let document = try XMLDocument(data: output, options: [.nodeLoadExternalEntitiesNever])
        let descriptions = try document.nodes(forXPath: "//*[local-name()='Description']")
        let description = try #require(descriptions.first as? XMLElement)

        #expect(packet.originalData == output)
        #expect(property("Exposure2012", namespace: cameraRawNamespace, in: packet)?.value == "+1.05")
        #expect(description.attributes?.contains {
            $0.localName == "Exposure2012" && $0.uri == cameraRawNamespace
        } == true)
        #expect(property("Rating", namespace: xmpNamespace, in: packet)?.value == "0")
        #expect(property("Keep", namespace: opaqueNamespace, in: packet) == nil)
        #expect(packet.properties.contains { $0.namespaceURI == "urn:custom" && $0.localName == "Keep" && $0.value == "yes" })
        #expect(try XMPPacketReader().read(sourceData).properties.allSatisfy { $0.localName != "Exposure2012" })
    }

    @Test func writerSerializesCRSScalarsAsFormattedDescriptionAttributes() throws {
        let sourceData = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="0"><crs:Exposure2012 xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/">0</crs:Exposure2012><crs:ToneCurvePV2012 xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012></rdf:Description></rdf:RDF></x:xmpmeta>
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
            sourceData: sourceData,
            values: [.exposure: 0.25],
            for: frame,
            using: [exposureDefinition(writable: true)]
        )
        let outputText = String(decoding: output, as: UTF8.self)
        let outputLines = outputText.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let document = try XMLDocument(data: output, options: [.nodeLoadExternalEntitiesNever])
        let descriptions = try document.nodes(forXPath: "//*[local-name()='Description']")
        let description = try #require(descriptions.first as? XMLElement)
        let exposureAttribute = description.attributes?.first {
            $0.uri == cameraRawNamespace && $0.localName == "Exposure2012"
        }
        let exposureElements = try document.nodes(forXPath: "//*[local-name()='Exposure2012']")

        #expect(exposureAttribute?.stringValue == "+0.25")
        #expect(exposureElements.isEmpty)
        #expect(outputText.hasPrefix("<x:xmpmeta"))
        #expect(outputText.contains("\n <rdf:RDF"))
        #expect(outputText.contains("\n  <rdf:Description"))
        #expect(outputText.contains("\n   <crs:ToneCurvePV2012"))
        #expect(outputLines.contains { $0.hasPrefix("xmlns:crs=") })
        #expect(outputLines.filter { $0.hasPrefix("xmlns:") }.allSatisfy { !$0.contains(" ") })
        #expect(outputText.contains("\n    xmlns:crs="))
        #expect(!outputText.contains("<?xml"))
        #expect(try XMPPacketReader().read(output).properties.contains {
            $0.namespaceURI == cameraRawNamespace && $0.localName == "Exposure2012" && $0.value == "+0.25"
        })
    }

    @Test func writerAlwaysRejectsKeyframeMetadata() throws {
        let sourceData = try sampleFixtureData()
        var frame = ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: "A0061.NEF",
            sequenceIndex: 0,
            metadataStatus: .valid,
            rating: 1,
            ratingSource: .xmpSidecar
        )
        let writer = XMPPacketWriter()
        let definitions = [exposureDefinition(writable: true)]

        #expect(throws: XMPWriteError.keyframeMetadataIsImmutable) {
            try writer.updating(sourceData: sourceData, values: [.exposure: 1.0], for: frame, using: definitions)
        }

        frame.rating = 0
        #expect(throws: XMPWriteError.keyframeMetadataIsImmutable) {
            try writer.updating(sourceData: sourceData, values: [.exposure: 1.0], for: frame, using: definitions)
        }

        frame.keyframeID = UUID()
        #expect(throws: XMPWriteError.keyframeMetadataIsImmutable) {
            try writer.updating(sourceData: sourceData, values: [.exposure: 1.0], for: frame, using: definitions)
        }
    }

    @Test func writerRejectsUnverifiedAndNonFiniteValues() throws {
        let sourceData = try intermediateSampleData()
        let frame = ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: "A0062.NEF",
            sequenceIndex: 1,
            metadataStatus: .valid,
            rating: 0,
            ratingSource: .xmpSidecar
        )
        let writer = XMPPacketWriter()

        #expect(throws: XMPWriteError.parameterNotApproved(.exposure)) {
            try writer.updating(
                sourceData: sourceData,
                values: [.exposure: 1.0],
                for: frame,
                using: [exposureDefinition(writable: false)]
            )
        }
        #expect(throws: XMPWriteError.invalidValue(.exposure)) {
            try writer.updating(
                sourceData: sourceData,
                values: [.exposure: .infinity],
                for: frame,
                using: [exposureDefinition(writable: true)]
            )
        }
    }

    @Test func imageIOMetadataReaderReadsRatingFromExistingSidecar() async throws {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "Lightroom15_6Sample", withExtension: "xmp")
        )
        let imageURL = URL(fileURLWithPath: "/tmp/no-image-data-expected.NEF")
        let snapshot = await ImageIOMetadataReader().readMetadata(
            imageURL: imageURL,
            sidecarURL: fixtureURL
        )

        #expect(snapshot.sidecarRating.status == .readable)
        #expect(snapshot.sidecarRating.values == [1])
        #expect(snapshot.metadataStatus == .partial)
    }

    private var cameraRawNamespace: String {
        "http://ns.adobe.com/camera-raw-settings/1.0/"
    }

    private var cameraRawDefaultsNamespace: String {
        "http://ns.adobe.com/camera-raw-defaults/1.0/"
    }

    private var xmpNamespace: String {
        "http://ns.adobe.com/xap/1.0/"
    }

    private var opaqueNamespace: String {
        "https://example.invalid/opaque/"
    }

    private func sampleFixtureData() throws -> Data {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "Lightroom15_6Sample", withExtension: "xmp")
        )
        return try Data(contentsOf: fixtureURL)
    }

    private func intermediateSampleData() throws -> Data {
        let document = try XMLDocument(
            data: sampleFixtureData(),
            options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
        )
        let descriptionNodes = try document.nodes(forXPath: "//*[local-name()='Description']")
        guard let description = descriptionNodes.first as? XMLElement,
              let rating = description.attributes?.first(where: {
                  $0.uri == xmpNamespace && $0.localName == "Rating"
              }) else {
            throw XMPReadError.unsupportedRoot
        }
        rating.stringValue = "0"
        return document.xmlData(options: .nodePreserveAll)
    }

    private func property(_ localName: String, namespace: String, in packet: XMPPacket) -> XMPProperty? {
        packet.properties.first {
            $0.localName == localName && $0.namespaceURI == namespace
        }
    }

    private func exposureDefinition(writable: Bool) -> ParameterDefinition {
        ParameterDefinition(
            parameter: .exposure,
            namespaceURI: cameraRawNamespace,
            xmpTag: "Exposure2012",
            unit: .exposureEV,
            interpolation: .linear,
            validRange: nil,
            writable: writable,
            compatibilityNotes: "Test-only mapping; range and Lightroom output recognition remain unverified."
        )
    }

    private func contrastDefinition(writable: Bool) -> ParameterDefinition {
        ParameterDefinition(
            parameter: .contrast,
            namespaceURI: cameraRawNamespace,
            xmpTag: "Contrast2012",
            unit: .percent,
            interpolation: .linear,
            validRange: nil,
            writable: writable,
            compatibilityNotes: "Test-only mapping; range and Lightroom output recognition remain unverified."
        )
    }
}