/// Behavior used when updating existing Lightroom-generated sidecars.
public enum ExportMode: String, Codable, CaseIterable, Sendable {
    /// Update existing eligible sidecars only after explicit approval and safety checks.
    case updateExistingSidecars
}