import Foundation
import LapseCurveDomain

/// One explicit source-frame preview request for display or bounded prefetch.
public struct PreviewRequest: Sendable {
    /// Frame identity and source metadata.
    public let frame: ImageFrame
    /// Local image URL.
    public let sourceURL: URL
    /// Explicitly associated JPEG, if supplied by the sequence layer.
    public let companionJPEGURL: URL?
    /// Maximum output pixel dimension.
    public let maximumPixelSize: Int

    /// Creates a preview request.
    public init(
        frame: ImageFrame,
        sourceURL: URL,
        companionJPEGURL: URL? = nil,
        maximumPixelSize: Int
    ) {
        self.frame = frame
        self.sourceURL = sourceURL
        self.companionJPEGURL = companionJPEGURL
        self.maximumPixelSize = maximumPixelSize
    }
}