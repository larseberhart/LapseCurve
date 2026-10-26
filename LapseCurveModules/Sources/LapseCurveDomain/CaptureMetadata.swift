/// Camera settings used to estimate relative capture exposure.
public struct CaptureMetadata: Codable, Equatable, Sendable {
    /// Shutter duration in seconds, if known.
    public var shutterDurationSeconds: Double?
    /// Aperture f-number, if known.
    public var apertureFNumber: Double?
    /// ISO sensitivity, if known.
    public var iso: Double?
    /// Focal length in millimeters, if known.
    public var focalLengthMM: Double?

    /// Creates capture metadata without assuming missing camera values.
    public init(
        shutterDurationSeconds: Double? = nil,
        apertureFNumber: Double? = nil,
        iso: Double? = nil,
        focalLengthMM: Double? = nil
    ) {
        self.shutterDurationSeconds = shutterDurationSeconds
        self.apertureFNumber = apertureFNumber
        self.iso = iso
        self.focalLengthMM = focalLengthMM
    }
}