import Foundation

/// Downsampled preview bytes and pixel dimensions, with explicit source provenance.
public struct PreviewImage: Codable, Sendable, Equatable {
    /// JPEG-encoded preview pixels.
    public var data: Data
    /// Encoded preview width in pixels.
    public var pixelWidth: Int
    /// Encoded preview height in pixels.
    public var pixelHeight: Int
    /// Image source used to obtain the preview pixels.
    public var source: PreviewSource

    /// Creates a preview image value.
    public init(data: Data, pixelWidth: Int, pixelHeight: Int, source: PreviewSource) {
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.source = source
    }
}