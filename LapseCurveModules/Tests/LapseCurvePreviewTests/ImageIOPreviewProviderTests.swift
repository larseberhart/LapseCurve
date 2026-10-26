import CoreGraphics
import Foundation
import ImageIO
import LapseCurveDomain
import Testing
import UniformTypeIdentifiers
@testable import LapseCurvePreview

struct ImageIOPreviewProviderTests {
    @Test func rasterJPEGIsDownsampledAndLabeledAsSourceImage() async throws {
        let (previewProvider, cacheDirectory) = try makePreviewProvider()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let sourceData = try makeJPEG(width: 160, height: 80)
        let sourceURL = try writeTemporaryFile(sourceData, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let image = try await previewProvider.preview(
            for: makeFrame("raster.jpg"),
            sourceURL: sourceURL,
            companionJPEGURL: nil,
            maximumPixelSize: 40
        )

        #expect(image.source == .sourceImage)
        #expect(max(image.pixelWidth, image.pixelHeight) <= 40)
        #expect(image.pixelWidth > image.pixelHeight)
    }

    @Test func changedSourceFingerprintInvalidatesCachedPreview() async throws {
        let (previewProvider, cacheDirectory) = try makePreviewProvider()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let sourceURL = try writeTemporaryFile(try makeJPEG(width: 400, height: 100), extension: "jpg")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let frame = makeFrame("changing.jpg")

        let firstPreview = try await previewProvider.preview(
            for: frame,
            sourceURL: sourceURL,
            companionJPEGURL: nil,
            maximumPixelSize: 200
        )
        try makeJPEG(width: 100, height: 400).write(to: sourceURL, options: .atomic)
        let replacementPreview = try await previewProvider.preview(
            for: frame,
            sourceURL: sourceURL,
            companionJPEGURL: nil,
            maximumPixelSize: 200
        )

        #expect(firstPreview.pixelWidth > firstPreview.pixelHeight)
        #expect(replacementPreview.pixelHeight > replacementPreview.pixelWidth)
    }

    @Test func rawSourceDoesNotFallBackToDecodingSourceImage() async throws {
        let rasterBytes = try makeJPEG(width: 120, height: 80)
        let rawNamedFileURL = try writeTemporaryFile(rasterBytes, extension: "nef")
        defer { try? FileManager.default.removeItem(at: rawNamedFileURL) }

        await expectAsyncError(PreviewError.previewUnavailable) {
            _ = try await ImageIOPreviewProvider().preview(
                for: makeFrame("capture.nef"),
                sourceURL: rawNamedFileURL,
                companionJPEGURL: nil,
                maximumPixelSize: 32
            )
        }
    }

    @Test func companionJPEGIsUsedOnlyWhenExplicitlyProvided() async throws {
        let (previewProvider, cacheDirectory) = try makePreviewProvider()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let sourceURL = try writeTemporaryFile(Data("not a raw decoder input".utf8), extension: "dng")
        let companionURL = try writeTemporaryFile(try makeJPEG(width: 100, height: 50), extension: "jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: companionURL)
        }

        let image = try await previewProvider.preview(
            for: makeFrame("capture.dng"),
            sourceURL: sourceURL,
            companionJPEGURL: companionURL,
            maximumPixelSize: 48
        )

        #expect(image.source == .companionJPEG)
        #expect(max(image.pixelWidth, image.pixelHeight) <= 48)
    }

    @Test func memoryCacheEnforcesCostBoundAndEvictsLeastRecentlyUsed() async {
        let cache = PreviewCache(
            maximumEntryCount: 3,
            maximumMemoryCostBytes: 8,
            maximumDiskCostBytes: 0
        )
        let firstKey = cacheKey("first")
        let secondKey = cacheKey("second")
        let thirdKey = cacheKey("third")

        await cache.insert(makePreview(byteCount: 4), for: firstKey)
        await cache.insert(makePreview(byteCount: 4), for: secondKey)
        _ = await cache.image(for: firstKey)
        await cache.insert(makePreview(byteCount: 4), for: thirdKey)

        #expect(await cache.count == 2)
        #expect(await cache.memoryCostBytes == 8)
        #expect(await cache.image(for: firstKey) != nil)
        #expect(await cache.image(for: secondKey) == nil)
        #expect(await cache.image(for: thirdKey) != nil)
    }

    @Test func oversizedPreviewIsNotRetained() async {
        let cache = PreviewCache(
            maximumEntryCount: 3,
            maximumMemoryCostBytes: 3,
            maximumDiskCostBytes: 0
        )
        await cache.insert(makePreview(byteCount: 4), for: cacheKey("oversized"))

        #expect(await cache.count == 0)
        #expect(await cache.memoryCostBytes == 0)
    }

    @Test func diskCacheRoundTripsPreviewProvenanceAndRespectsByteLimit() async throws {
        let cacheDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cache = PreviewCache(
            maximumEntryCount: 0,
            maximumMemoryCostBytes: 0,
            diskCacheDirectory: cacheDirectory,
            maximumDiskCostBytes: 3_000
        )
        let firstKey = cacheKey("disk-first")
        let secondKey = cacheKey("disk-second")
        let firstImage = makePreview(byteCount: 1_500, source: .companionJPEG)
        let secondImage = makePreview(byteCount: 1_500, source: .embedded)

        await cache.insert(firstImage, for: firstKey)
        #expect(await cache.image(for: firstKey) == firstImage)
        await cache.insert(secondImage, for: secondKey)

        #expect(await cache.diskCostBytes <= 3_000)
        #expect(await cache.count == 0)
        #expect(await cache.diskEntryCount <= 1)
    }

    @Test func cancelledPreviewRequestStopsBeforeReading() async {
        let provider = ImageIOPreviewProvider()
        let sourceURL = URL(fileURLWithPath: "/tmp/missing-preview-source.nef")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.preview(
                for: makeFrame("missing-preview-source.nef"),
                sourceURL: sourceURL,
                companionJPEGURL: nil,
                maximumPixelSize: 64
            )
        }

        do {
            _ = try await task.value
            Issue.record("Expected a pre-cancelled preview request to stop.")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Preview request threw an unexpected error: \(error).")
        }
    }

    @Test func prefetchReturnsNeighboringPreviewsAndPerFrameFailures() async throws {
        let (previewProvider, cacheDirectory) = try makePreviewProvider()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let firstURL = try writeTemporaryFile(try makeJPEG(width: 80, height: 40), extension: "jpg")
        let secondURL = try writeTemporaryFile(try makeJPEG(width: 40, height: 80), extension: "jpg")
        let missingURL = URL(fileURLWithPath: "/tmp/missing-lapsecurve-preview.jpg")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let firstFrame = makeFrame("frame1.jpg")
        let secondFrame = makeFrame("frame2.jpg")
        let missingFrame = makeFrame("missing.jpg")

        let result = await previewProvider.prefetch([
            PreviewRequest(frame: firstFrame, sourceURL: firstURL, maximumPixelSize: 40),
            PreviewRequest(frame: secondFrame, sourceURL: secondURL, maximumPixelSize: 40),
            PreviewRequest(frame: missingFrame, sourceURL: missingURL, maximumPixelSize: 40)
        ])

        #expect(result.previews[firstFrame.id]?.source == .sourceImage)
        #expect(result.previews[secondFrame.id]?.source == .sourceImage)
        #expect(result.failures[missingFrame.id] != nil)
        #expect(!result.wasCancelled)
    }

    private func makeJPEG(width: Int, height: Int) throws -> Data {
        let bytes = Data(repeating: 127, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func writeTemporaryFile(_ data: Data, extension fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurvePreview-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: url)
        return url
    }

    private func makeFrame(_ relativePath: String) -> ImageFrame {
        ImageFrame(
            id: FrameID(rawValue: UUID()),
            relativePath: relativePath,
            sequenceIndex: 0
        )
    }

    private func makePreview(byteCount: Int, source: PreviewSource = .embedded) -> PreviewImage {
        PreviewImage(data: Data(repeating: 1, count: byteCount), pixelWidth: 2, pixelHeight: 2, source: source)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapseCurvePreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makePreviewProvider() throws -> (ImageIOPreviewProvider, URL) {
        let cacheDirectory = try makeTemporaryDirectory()
        let cache = PreviewCache(diskCacheDirectory: cacheDirectory)
        return (ImageIOPreviewProvider(cache: cache), cacheDirectory)
    }

    private func cacheKey(_ value: String) -> PreviewCacheKey {
        PreviewCacheKey(
            frameID: FrameID(rawValue: UUID()),
            sourcePath: value,
            sourceFingerprint: nil,
            companionPath: nil,
            companionFingerprint: nil,
            maximumPixelSize: 100
        )
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