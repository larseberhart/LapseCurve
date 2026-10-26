import LapseCurveDomain

/// Conservative result of reconciling embedded and sidecar ratings.
public struct KeyframeRatingResolution: Sendable {
    /// Resolved rating; `nil` when absent or ambiguous.
    public var rating: Int?
    /// Metadata source selected by the precedence rule.
    public var source: RatingSource
    /// True only for an unambiguous rating exactly equal to one.
    public var isKeyframe: Bool
    /// True when no unambiguous rating could be read.
    public var isUnreadable: Bool
    /// Conflict or unreadable-value diagnostics.
    public var warnings: [ValidationIssue]

    /// Creates a rating resolution.
    public init(
        rating: Int?,
        source: RatingSource,
        isKeyframe: Bool,
        isUnreadable: Bool,
        warnings: [ValidationIssue]
    ) {
        self.rating = rating
        self.source = source
        self.isKeyframe = isKeyframe
        self.isUnreadable = isUnreadable
        self.warnings = warnings
    }
}