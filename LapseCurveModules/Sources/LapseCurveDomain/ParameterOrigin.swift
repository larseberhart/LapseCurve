/// Provenance of one calculated or imported parameter sample.
public enum ParameterOrigin: String, Codable, CaseIterable, Sendable {
    /// Read from a sidecar or supported embedded metadata.
    case importedSidecar
    /// Read from an authoritative keyframe.
    case keyframe
    /// Neutral zero inferred because a valid sidecar omitted this adjustment field.
    case assumedNeutral
    /// Camera as-shot white balance, from an XMP `As Shot` mode or decoded from the RAW file.
    case asShot
    /// Calculated between keyframes.
    case interpolated
    /// Set by a user for a specific frame.
    case manualOverride
    /// Produced by the distinct capture-exposure compensation stage.
    case holyGrailCompensation
}