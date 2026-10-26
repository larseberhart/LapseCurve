/// Coordinate basis used to calculate interpolation progress.
public enum TimeBasis: String, Codable, CaseIterable, Sendable {
    /// Use each frame's deterministic sequence index.
    case frameIndex
    /// Use capture timestamps when valid and distinct.
    case captureTime
}