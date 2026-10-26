import CoreGraphics
import Foundation
import ImageIO
import LapseCurveDomain
import UniformTypeIdentifiers

/// ImageIO implementation that never renders RAW source pixels as a fallback.
public actor ImageIOPreviewProvider: FramePreviewProviding {
    private let cache: PreviewCache
    private let rawExtensions: Set<String> = [
        "dng", "nef", "nrw", "cr2", "cr3", "arw", "srf", "sr2", "raf", "rw2", "orf", "pef", "srw"
    ]
    private let rasterExtensions: Set<String> = ["jpg", "jpeg", "tif", "tiff", "png", "heic"]

    /// Creates a provider with a bounded in-memory cache.
    public init(cache: PreviewCache = PreviewCache()) {
        self.cache = cache
    }

    /// Returns an embedded preview, explicitly associated JPEG preview, or JPEG source preview.
    ///
    /// RAW sources are requested with image-source fallback disabled. If no embedded thumbnail
    /// exists, the provider tries only the explicitly supplied companion JPEG, then throws.
    public func preview(
        for frame: ImageFrame,
        sourceURL: URL,
        companionJPEGURL: URL? = nil,
        maximumPixelSize: Int
    ) async throws -> PreviewImage {
        guard maximumPixelSize > 0 else {
            throw PreviewError.invalidMaximumPixelSize
        }
        guard sourceURL.isFileURL else {
            throw PreviewError.invalidSourceURL
        }
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PreviewError.invalidSourceURL
        }

        let cacheKey = makeCacheKey(
            frame: frame,
            sourceURL: sourceURL,
            companionJPEGURL: companionJPEGURL,
            maximumPixelSize: maximumPixelSize
        )
        if let cachedImage = await cache.image(for: cacheKey) {
            try Task.checkCancellation()
            try verifySourcesUnchanged(
                expectedCacheKey: cacheKey,
                frame: frame,
                sourceURL: sourceURL,
                companionJPEGURL: companionJPEGURL,
                maximumPixelSize: maximumPixelSize
            )
            return cachedImage
        }

        let sourceExtension = sourceURL.pathExtension.lowercased()
        if rasterExtensions.contains(sourceExtension),
           ["jpg", "jpeg"].contains(sourceExtension),
           let rasterImage = try rasterPreview(
               from: sourceURL,
               maximumPixelSize: maximumPixelSize,
               source: .sourceImage
           ) {
            try Task.checkCancellation()
            try verifySourcesUnchanged(
                expectedCacheKey: cacheKey,
                frame: frame,
                sourceURL: sourceURL,
                companionJPEGURL: companionJPEGURL,
                maximumPixelSize: maximumPixelSize
            )
            await cache.insert(rasterImage, for: cacheKey)
            try Task.checkCancellation()
            return rasterImage
        }

        if let embeddedImage = try embeddedPreview(
            from: sourceURL,
            maximumPixelSize: maximumPixelSize,
            requiresRawSource: rawExtensions.contains(sourceExtension)
        ) {
            try Task.checkCancellation()
            try verifySourcesUnchanged(
                expectedCacheKey: cacheKey,
                frame: frame,
                sourceURL: sourceURL,
                companionJPEGURL: companionJPEGURL,
                maximumPixelSize: maximumPixelSize
            )
            await cache.insert(embeddedImage, for: cacheKey)
            try Task.checkCancellation()
            return embeddedImage
        }

        if rasterExtensions.contains(sourceExtension),
           let rasterImage = try rasterPreview(
               from: sourceURL,
               maximumPixelSize: maximumPixelSize,
               source: .sourceImage
           ) {
            try Task.checkCancellation()
            try verifySourcesUnchanged(
                expectedCacheKey: cacheKey,
                frame: frame,
                sourceURL: sourceURL,
                companionJPEGURL: companionJPEGURL,
                maximumPixelSize: maximumPixelSize
            )
            await cache.insert(rasterImage, for: cacheKey)
            try Task.checkCancellation()
            return rasterImage
        }

        if let companionJPEGURL {
            guard companionJPEGURL.isFileURL,
                ["jpg", "jpeg"].contains(companionJPEGURL.pathExtension.lowercased()),
                FileManager.default.fileExists(atPath: companionJPEGURL.path) else {
                throw PreviewError.invalidSourceURL
            }
            if let companionImage = try rasterPreview(
                from: companionJPEGURL,
                maximumPixelSize: maximumPixelSize,
                source: .companionJPEG
            ) {
                try Task.checkCancellation()
                try verifySourcesUnchanged(
                    expectedCacheKey: cacheKey,
                    frame: frame,
                    sourceURL: sourceURL,
                    companionJPEGURL: companionJPEGURL,
                    maximumPixelSize: maximumPixelSize
                )
                await cache.insert(companionImage, for: cacheKey)
                try Task.checkCancellation()
                return companionImage
            }
        }

        throw PreviewError.previewUnavailable
    }

    private func embeddedPreview(
        from sourceURL: URL,
        maximumPixelSize: Int,
        requiresRawSource: Bool
    ) throws -> PreviewImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }
        if requiresRawSource {
            guard let sourceTypeIdentifier = CGImageSourceGetType(source) as String?,
                  let sourceType = UTType(sourceTypeIdentifier),
                  sourceType.conforms(to: .rawImage) else {
                return nil
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return try encode(image, source: .embedded)
    }

    private func rasterPreview(
        from imageURL: URL,
        maximumPixelSize: Int,
        source previewSource: PreviewSource
    ) throws -> PreviewImage? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return try encode(image, source: previewSource)
    }

    private func encode(_ image: CGImage, source: PreviewSource) throws -> PreviewImage {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PreviewError.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PreviewError.encodingFailed
        }
        return PreviewImage(
            data: outputData as Data,
            pixelWidth: image.width,
            pixelHeight: image.height,
            source: source
        )
    }

    private func makeCacheKey(
        frame: ImageFrame,
        sourceURL: URL,
        companionJPEGURL: URL?,
        maximumPixelSize: Int
    ) -> PreviewCacheKey {
        let currentSourceFingerprint = fileFingerprint(for: sourceURL) ?? frame.fileFingerprint
        return PreviewCacheKey(
            frameID: frame.id,
            sourcePath: sourceURL.standardizedFileURL.path,
            sourceFingerprint: currentSourceFingerprint,
            companionPath: companionJPEGURL?.standardizedFileURL.path,
            companionFingerprint: companionJPEGURL.flatMap(fileFingerprint(for:)),
            maximumPixelSize: maximumPixelSize
        )
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

    private func verifySourcesUnchanged(
        expectedCacheKey: PreviewCacheKey,
        frame: ImageFrame,
        sourceURL: URL,
        companionJPEGURL: URL?,
        maximumPixelSize: Int
    ) throws {
        guard makeCacheKey(
            frame: frame,
            sourceURL: sourceURL,
            companionJPEGURL: companionJPEGURL,
            maximumPixelSize: maximumPixelSize
        ) == expectedCacheKey else {
            throw PreviewError.sourceChangedDuringRead
        }
    }
}