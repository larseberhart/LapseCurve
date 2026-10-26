import Foundation
import LapseCurveDomain

/// Asynchronous provider of source previews; it never renders Lightroom development.
public protocol FramePreviewProviding: Sendable {
    /// Obtains a preview from an embedded thumbnail or an explicitly associated JPEG.
    func preview(
        for frame: ImageFrame,
        sourceURL: URL,
        companionJPEGURL: URL?,
        maximumPixelSize: Int
    ) async throws -> PreviewImage

    /// Prefetches neighboring frames sequentially, bounding in-flight ImageIO work.
    func prefetch(_ requests: [PreviewRequest]) async -> PreviewPrefetchResult
}

public extension FramePreviewProviding {
    /// Loads a bounded sequence of preview requests and records per-frame failures.
    func prefetch(_ requests: [PreviewRequest]) async -> PreviewPrefetchResult {
        var previews: [FrameID: PreviewImage] = [:]
        var failures: [FrameID: String] = [:]
        var wasCancelled = false

        for request in requests {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            do {
                previews[request.frame.id] = try await preview(
                    for: request.frame,
                    sourceURL: request.sourceURL,
                    companionJPEGURL: request.companionJPEGURL,
                    maximumPixelSize: request.maximumPixelSize
                )
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                failures[request.frame.id] = error.localizedDescription
            }
        }
        return PreviewPrefetchResult(previews: previews, failures: failures, wasCancelled: wasCancelled)
    }
}