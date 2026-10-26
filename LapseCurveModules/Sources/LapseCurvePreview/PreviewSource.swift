/// Provenance of encoded preview pixels.
public enum PreviewSource: String, Codable, CaseIterable, Sendable {
    /// Extracted from an embedded image thumbnail without rendering RAW image data.
    case embedded
    /// Decoded from a companion JPEG explicitly associated with the frame.
    case companionJPEG
    /// Generated from a JPEG source image, which is already a raster image.
    case sourceImage
}