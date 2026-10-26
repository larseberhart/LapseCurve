import LapseCurveDomain

/// Results of a bounded adjacent-frame preview prefetch operation.
public struct PreviewPrefetchResult: Sendable {
    /// Successfully loaded preview values keyed by frame identity.
    public let previews: [FrameID: PreviewImage]
    /// User-readable failure messages keyed by frame identity.
    public let failures: [FrameID: String]
    /// Whether cancellation stopped remaining requests.
    public let wasCancelled: Bool

    /// Creates a prefetch result.
    public init(
        previews: [FrameID: PreviewImage],
        failures: [FrameID: String],
        wasCancelled: Bool
    ) {
        self.previews = previews
        self.failures = failures
        self.wasCancelled = wasCancelled
    }
}