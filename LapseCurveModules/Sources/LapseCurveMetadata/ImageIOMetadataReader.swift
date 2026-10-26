import CoreImage
import Foundation
import ImageIO
import LapseCurveDomain
import LapseCurveSequence
import UniformTypeIdentifiers

/// Reads image metadata with ImageIO and ratings from existing XMP sidecars.
public struct ImageIOMetadataReader: SequenceMetadataReading, Sendable {
    private let xmpPacketReader: XMPPacketReader

    /// Creates a reader with a bounded XMP packet parser.
    public init(maximumXMPPacketSizeBytes: Int = 16 * 1024 * 1024) {
        xmpPacketReader = XMPPacketReader(maximumPacketSizeBytes: maximumXMPPacketSizeBytes)
    }

    /// Reads available metadata without writing to the image or sidecar.
    public func readMetadata(imageURL: URL, sidecarURL: URL?) async -> FrameMetadataSnapshot {
        var warnings: [ValidationIssue] = []
        var embeddedRating = RatingMetadataRead(status: .unsupported)
        var captureTime: Date?
        var captureTimeSource: CaptureTimeSource = .unavailable
        var captureMetadata = CaptureMetadata()
        var rawMetadataDocument: RawMetadataDocument?
        var developmentParameters = ParameterSet()
        var hasReadableImageMetadata = false

        if let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
            let imageMetadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
            if let imageMetadata {
                embeddedRating = readEmbeddedRating(from: imageMetadata)
            }
            if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                hasReadableImageMetadata = true
                let exifProperties = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
                captureMetadata = readCaptureMetadata(from: exifProperties)
                if let timestamp = captureTimestamp(from: exifProperties) {
                    captureTime = timestamp
                    captureTimeSource = .exif
                }
            } else {
                embeddedRating = RatingMetadataRead(status: .missing)
            }
        } else {
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "imageMetadataUnsupported",
                    message: "ImageIO could not read embedded metadata from this image."
                )
            )
        }

        let sidecarRating: RatingMetadataRead
        var sidecarStatus: MetadataReadStatus = .missing
        if let sidecarURL {
            do {
                let packetData = try Data(contentsOf: sidecarURL)
                let packet = try xmpPacketReader.read(packetData)
                rawMetadataDocument = RawMetadataDocument(
                    data: packetData,
                    mediaType: "application/rdf+xml",
                    sourceFingerprint: fileFingerprint(for: sidecarURL)
                )
                let ratingProperties = packet.properties.filter {
                    $0.namespaceURI == "http://ns.adobe.com/xap/1.0/"
                        && $0.localName == "Rating"
                }
                let resolved = XMPFieldRegistry.developmentValues(in: packet)
                developmentParameters = resolved.parameters
                warnings.append(contentsOf: resolved.issues)
                if ratingProperties.isEmpty {
                    sidecarRating = RatingMetadataRead(status: .missing)
                    sidecarStatus = .missing
                } else {
                    let values = ratingProperties.compactMap { Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if values.count == ratingProperties.count {
                        sidecarRating = RatingMetadataRead(status: .readable, values: values)
                        sidecarStatus = .readable
                    } else {
                        sidecarRating = RatingMetadataRead(status: .malformed, values: values)
                        sidecarStatus = .malformed
                        warnings.append(
                            ValidationIssue(
                                severity: .warning,
                                code: "xmpRatingMalformed",
                                message: "The XMP sidecar contains a non-integer rating."
                            )
                        )
                    }
                }
            } catch {
                sidecarRating = RatingMetadataRead(status: .malformed)
                sidecarStatus = .malformed
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "xmpSidecarUnreadable",
                        message: "The existing XMP sidecar could not be read as supported XML."
                    )
                )
            }
        } else {
            sidecarRating = RatingMetadataRead(status: .missing)
        }

        // Decoding RAW is slow and only keyframes use the as-shot value.
        let isKeyframeCandidate = embeddedRating.values.contains(1) || sidecarRating.values.contains(1)
        if isKeyframeCandidate,
           developmentParameters.values[.temperature] == nil || developmentParameters.values[.tint] == nil,
           let asShot = rawAsShotWhiteBalance(imageURL: imageURL) {
            for (parameter, value) in [(DevelopmentParameter.temperature, asShot.temperature), (.tint, asShot.tint)]
            where developmentParameters.values[parameter] == nil {
                developmentParameters.values[parameter] = ParameterSample(value: value, origin: .asShot, isLocked: false)
            }
        }

        let metadataStatus: MetadataStatus
        if sidecarStatus == .malformed {
            metadataStatus = .malformed
        } else if hasReadableImageMetadata || sidecarStatus == .readable {
            metadataStatus = hasReadableImageMetadata && (sidecarURL == nil || sidecarStatus == .readable)
                ? .valid
                : .partial
        } else {
            metadataStatus = .unsupported
        }

        return FrameMetadataSnapshot(
            embeddedRating: embeddedRating,
            sidecarRating: sidecarRating,
            captureTime: captureTime,
            captureTimeSource: captureTimeSource,
            captureMetadata: captureMetadata,
            metadataStatus: metadataStatus,
            rawMetadataDocument: rawMetadataDocument,
            developmentParameters: developmentParameters,
            warnings: warnings
        )
    }

    /// EXIF only flags auto/manual WB, so the RAW decoder supplies Kelvin and tint; Apple's values can differ slightly from Lightroom's.
    private func rawAsShotWhiteBalance(imageURL: URL) -> (temperature: Double, tint: Double)? {
        guard UTType(filenameExtension: imageURL.pathExtension)?.conforms(to: .rawImage) == true,
              let filter = CIRAWFilter(imageURL: imageURL) else {
            return nil
        }
        let temperature = Double(filter.neutralTemperature)
        let tint = Double(filter.neutralTint)
        guard temperature.isFinite, temperature > 0, tint.isFinite else { return nil }
        return (temperature, tint)
    }

    private func readEmbeddedRating(from metadata: CGImageMetadata) -> RatingMetadataRead {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString),
              let value = CGImageMetadataTagCopyValue(tag) else {
            return RatingMetadataRead(status: .missing)
        }
        if let stringValue = value as? String,
           let rating = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return RatingMetadataRead(status: .readable, values: [rating])
        }
        if let numberValue = value as? NSNumber {
            return RatingMetadataRead(status: .readable, values: [numberValue.intValue])
        }
        return RatingMetadataRead(status: .malformed)
    }

    private func readCaptureMetadata(from properties: [String: Any]) -> CaptureMetadata {
        CaptureMetadata(
            shutterDurationSeconds: positiveDouble(properties[kCGImagePropertyExifExposureTime as String]),
            apertureFNumber: positiveDouble(properties[kCGImagePropertyExifFNumber as String]),
            iso: isoValue(properties[kCGImagePropertyExifISOSpeedRatings as String]),
            focalLengthMM: positiveDouble(properties[kCGImagePropertyExifFocalLength as String])
        )
    }

    private func captureTimestamp(from properties: [String: Any]) -> Date? {
        guard let dateString = properties[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
            return nil
        }
        let offset = properties[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false

        if let offset {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["yyyy:MM:dd HH:mm:ss.SSSXXXXX", "yyyy:MM:dd HH:mm:ssXXXXX"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: dateString + offset) {
                    return date
                }
            }
            return nil
        }

        return nil
    }

    private func positiveDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let doubleValue = number.doubleValue
        return doubleValue.isFinite && doubleValue > 0 ? doubleValue : nil
    }

    private func isoValue(_ value: Any?) -> Double? {
        if let values = value as? [NSNumber], let firstValue = values.first {
            return positiveDouble(firstValue)
        }
        return positiveDouble(value)
    }

    private func fileFingerprint(for fileURL: URL) -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return FileFingerprint(
            byteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            digest: nil
        )
    }
}