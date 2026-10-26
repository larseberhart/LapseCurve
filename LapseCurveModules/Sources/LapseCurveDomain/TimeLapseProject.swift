import Foundation

/// Versioned, portable project state; source media remains external.
public struct TimeLapseProject: Codable, Equatable, Sendable {
    /// Schema version used to encode this project.
    public var schemaVersion: Int
    /// Stable project identity.
    public var id: ProjectID
    /// User-visible project name.
    public var name: String
    /// Security-scoped bookmark for the project source, when required.
    public var sourceBookmark: Data?
    /// Non-authoritative source-root path hint.
    public var sourceRootPathHint: String?
    /// Ordered image frames in the sequence.
    public var frames: [ImageFrame]
    /// Development keyframes associated with sequence frames.
    public var keyframes: [Keyframe]
    /// Original opaque metadata packets keyed by their source frame.
    public var metadataBaselines: [FrameID: RawMetadataDocument]
    /// Bookmark for the selected working directory, when required.
    public var workingDirectoryBookmark: Data?
    /// Summary of the most recent scan.
    public var lastScanSummary: SequenceScanSummary?
    /// Manual per-frame parameter overrides.
    public var overrides: [ManualOverride]
    /// Project-wide calculation and export settings.
    public var settings: ProjectSettings
    /// Project creation time.
    public var createdAt: Date
    /// Last project modification time.
    public var modifiedAt: Date

    /// Creates a project document value.
    public init(
        schemaVersion: Int,
        id: ProjectID,
        name: String,
        sourceBookmark: Data? = nil,
        sourceRootPathHint: String? = nil,
        frames: [ImageFrame],
        keyframes: [Keyframe],
        metadataBaselines: [FrameID: RawMetadataDocument] = [:],
        workingDirectoryBookmark: Data? = nil,
        lastScanSummary: SequenceScanSummary? = nil,
        overrides: [ManualOverride],
        settings: ProjectSettings,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.sourceBookmark = sourceBookmark
        self.sourceRootPathHint = sourceRootPathHint
        self.frames = frames
        self.keyframes = keyframes
        self.metadataBaselines = metadataBaselines
        self.workingDirectoryBookmark = workingDirectoryBookmark
        self.lastScanSummary = lastScanSummary
        self.overrides = overrides
        self.settings = settings
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}