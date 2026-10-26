import Foundation
import LapseCurveDomain

/// Read-only, cancellable scanner for supported image sequences.
public actor SequenceScanner: SequenceScanning {
    private let metadataReader: any SequenceMetadataReading

    /// Creates a scanner with an injected metadata reader.
    public init(metadataReader: any SequenceMetadataReading) {
        self.metadataReader = metadataReader
    }

    /// Discovers files, reads metadata and returns a deterministic scan result.
    ///
    /// Work is serialized and cancellation is checked between files, keeping resource usage
    /// bounded without blocking the main actor.
    public func scan(directory: URL, options: SequenceScanOptions) async throws -> SequenceScanResult {
        guard directory.isFileURL else {
            throw SequenceScanError.notDirectory
        }
        let standardizedDirectory = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SequenceScanError.notDirectory
        }

        let discoveredFiles = try discoverFiles(in: standardizedDirectory, options: options)
        let supportedFiles = discoveredFiles.filter {
            options.supportedExtensions.contains($0.pathExtension.lowercased())
        }
        let unsupportedFileCount = discoveredFiles.filter {
            let extensionName = $0.pathExtension.lowercased()
            return !options.supportedExtensions.contains(extensionName)
                && extensionName != "xmp"
                && extensionName != "acr"
        }.count
        let priorFramesByPath = Dictionary(
            options.previousFrames.map { ($0.relativePath, $0) },
            uniquingKeysWith: { firstFrame, _ in firstFrame }
        )

        let filesByBaseName = Dictionary(grouping: discoveredFiles) { url in
            url.deletingLastPathComponent().path + "/" + url.deletingPathExtension().lastPathComponent.lowercased()
        }
        let resolutions = supportedFiles.map { imageURL in
            let key = imageURL.deletingLastPathComponent().path + "/"
                + imageURL.deletingPathExtension().lastPathComponent.lowercased()
            return SidecarResolver.resolve(for: imageURL, among: filesByBaseName[key] ?? [])
        }
        let metadataByIndex = try await readAllMetadata(imageURLs: supportedFiles, sidecars: resolutions)

        var frames: [ImageFrame] = []
        var keyframes: [Keyframe] = []
        var sidecarURLsByFrameID: [FrameID: URL] = [:]
        var metadataBaselinesByFrameID: [FrameID: RawMetadataDocument] = [:]
        var warnings: [ValidationIssue] = []
        var unreadableRatingCount = 0
        for (fileIndex, imageURL) in supportedFiles.enumerated() {
            try Task.checkCancellation()
            let relativePath = relativePath(for: imageURL, under: standardizedDirectory)
            let frameID = priorFramesByPath[relativePath]?.id ?? stableFrameID(for: relativePath)
            let sidecars = resolutions[fileIndex]

            if sidecars.hasAmbiguousXMP {
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "xmpSidecarAmbiguous",
                        message: "Multiple same-basename XMP sidecars were found; none was selected.",
                        frameID: frameID
                    )
                )
            } else if sidecars.xmpURL == nil {
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "xmpSidecarMissing",
                        message: "No Lightroom-generated XMP sidecar exists; metadata updates will skip this frame.",
                        frameID: frameID
                    )
                )
            }
            if sidecars.hasACRSidecar {
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "acrSidecarUnsupported",
                        message: "An ACR sidecar is present and will not be read or modified.",
                        frameID: frameID
                    )
                )
            }

            let metadata = metadataByIndex[fileIndex]
            if let sidecarURL = sidecars.xmpURL {
                sidecarURLsByFrameID[frameID] = sidecarURL
            }
            if let rawMetadataDocument = metadata.rawMetadataDocument {
                metadataBaselinesByFrameID[frameID] = rawMetadataDocument
            }
            warnings.append(contentsOf: metadata.warnings.map { issue in
                var frameIssue = issue
                frameIssue.frameID = frameID
                return frameIssue
            })
            var rating = RatingMetadataRead(status: .missing)
            var ratingSource = RatingSource.unavailable
            var keyframeID: UUID?
            var metadataStatus = metadata.metadataStatus

            if options.detectKeyframesFromOneStarRating {
                let resolution = KeyframeRatingDetector.resolve(
                    embedded: metadata.embeddedRating,
                    sidecar: metadata.sidecarRating,
                    frameID: frameID
                )
                rating = RatingMetadataRead(
                    status: resolution.isUnreadable ? .malformed : .readable,
                    values: resolution.rating.map { [$0] } ?? []
                )
                ratingSource = resolution.source
                warnings.append(contentsOf: resolution.warnings)
                if resolution.warnings.contains(where: { $0.code == "ratingSourceConflict" }) {
                    metadataStatus = .conflict
                } else if resolution.warnings.contains(where: { $0.code == "ratingValueMalformed" }) {
                    metadataStatus = .malformed
                }
                if resolution.isUnreadable {
                    unreadableRatingCount += 1
                }
                if resolution.isKeyframe {
                    let resolvedKeyframeID = stableKeyframeID(for: relativePath)
                    keyframeID = resolvedKeyframeID
                    keyframes.append(
                        Keyframe(
                            id: resolvedKeyframeID,
                            frameID: frameID,
                            parameters: metadata.developmentParameters,
                            isLocked: false
                        )
                    )
                }
            }
            let fingerprint = fileFingerprint(for: imageURL)
            var captureTime = metadata.captureTime
            var captureTimeSource = metadata.captureTimeSource
            if captureTime == nil, let modificationDate = fingerprint.modificationDate {
                captureTime = modificationDate
                captureTimeSource = .filesystemFallback
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "captureTimeFilesystemFallback",
                        message: "Filesystem modification time is used as a capture-time fallback.",
                        frameID: frameID
                    )
                )
            }

            frames.append(
                ImageFrame(
                    id: frameID,
                    relativePath: relativePath,
                    sequenceIndex: 0,
                    captureTime: captureTime,
                    captureTimeSource: captureTimeSource,
                    captureMetadata: metadata.captureMetadata,
                    metadataStatus: metadataStatus,
                    rating: rating.values.first,
                    ratingSource: ratingSource,
                    keyframeID: keyframeID,
                    fileFingerprint: fingerprint
                )
            )
        }

        frames = SequenceOrdering.sort(frames, sortByCaptureTime: options.sortByCaptureTime)
        keyframes.sort { leftKeyframe, rightKeyframe in
            let leftIndex = frames.first(where: { $0.id == leftKeyframe.frameID })?.sequenceIndex ?? Int.max
            let rightIndex = frames.first(where: { $0.id == rightKeyframe.frameID })?.sequenceIndex ?? Int.max
            return leftIndex < rightIndex
        }
        warnings.append(contentsOf: SequenceOrdering.timestampWarnings(
            for: frames,
            sortByCaptureTime: options.sortByCaptureTime
        ))
        for index in frames.indices {
            frames[index].sequenceIndex = index
        }

        let summary = SequenceScanSummary(
            workingDirectoryPathHint: standardizedDirectory.path,
            photoCount: frames.count,
            keyframeCount: frames.filter { $0.keyframeID != nil }.count,
            unreadableRatingCount: unreadableRatingCount,
            unsupportedFileCount: unsupportedFileCount,
            scannedAt: Date()
        )
        return SequenceScanResult(
            frames: frames,
            keyframes: keyframes,
            sidecarURLsByFrameID: sidecarURLsByFrameID,
            metadataBaselinesByFrameID: metadataBaselinesByFrameID,
            warnings: warnings,
            summary: summary
        )
    }

    private func readAllMetadata(
        imageURLs: [URL],
        sidecars: [SidecarResolution]
    ) async throws -> [FrameMetadataSnapshot] {
        let reader = metadataReader
        let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount)
        var results = [FrameMetadataSnapshot?](repeating: nil, count: imageURLs.count)
        try await withThrowingTaskGroup(of: (Int, FrameMetadataSnapshot).self) { group in
            var next = 0
            func enqueue() {
                let index = next
                next += 1
                let imageURL = imageURLs[index]
                let sidecarURL = sidecars[index].xmpURL
                group.addTask {
                    (index, await reader.readMetadata(imageURL: imageURL, sidecarURL: sidecarURL))
                }
            }
            while next < min(maxConcurrent, imageURLs.count) { enqueue() }
            while let (index, snapshot) = try await group.next() {
                try Task.checkCancellation()
                results[index] = snapshot
                if next < imageURLs.count { enqueue() }
            }
        }
        return results.map { $0! }
    }

    private func discoverFiles(in directory: URL, options: SequenceScanOptions) throws -> [URL] {
        if options.recursive {
            var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !options.includeHiddenFiles {
                enumerationOptions.insert(.skipsHiddenFiles)
            }
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: enumerationOptions
            ) else {
                throw SequenceScanError.unreadableDirectory
            }

            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                try Task.checkCancellation()
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isRegularFile == true && values?.isSymbolicLink != true {
                    urls.append(fileURL.standardizedFileURL)
                }
            }
            return urls
        }

        return try contentsOfDirectory(directory, includeHiddenFiles: options.includeHiddenFiles)
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true
            }
    }

    private func contentsOfDirectory(_ directory: URL, includeHiddenFiles: Bool) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHiddenFiles ? [] : [.skipsHiddenFiles]
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: options
            ).map(\.standardizedFileURL)
        } catch {
            throw SequenceScanError.unreadableDirectory
        }
    }

    private func relativePath(for fileURL: URL, under directory: URL) -> String {
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return String(fileURL.path.dropFirst(prefix.count))
    }

    private func fileFingerprint(for fileURL: URL) -> FileFingerprint {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes?[.modificationDate] as? Date
        return FileFingerprint(byteCount: byteCount, modificationDate: modificationDate, digest: nil)
    }

    private func stableFrameID(for relativePath: String) -> FrameID {
        FrameID(rawValue: stableUUID(for: "frame:\(relativePath)"))
    }

    private func stableKeyframeID(for relativePath: String) -> UUID {
        stableUUID(for: "keyframe:\(relativePath)")
    }

    private func stableUUID(for value: String) -> UUID {
        let data = Array(value.utf8)
        var firstHash: UInt64 = 14_695_981_039_346_656_037
        var secondHash: UInt64 = 10_995_116_282_11
        for byte in data {
            firstHash = (firstHash ^ UInt64(byte)) &* 1_099_511_628_211
            secondHash = (secondHash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        var bytes = (0..<16).map { index -> UInt8 in
            let hash = index < 8 ? firstHash : secondHash
            let shift = UInt64((7 - (index % 8)) * 8)
            return UInt8((hash >> shift) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}