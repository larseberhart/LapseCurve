/// Rating values observed in one metadata source.
public struct RatingMetadataRead: Equatable, Sendable {
    /// Read status for the rating field.
    public var status: MetadataReadStatus
    /// Parsed integer ratings; multiple distinct values are treated as ambiguous.
    public var values: [Int]

    /// Creates a rating read result.
    public init(status: MetadataReadStatus, values: [Int] = []) {
        self.status = status
        self.values = values
    }
}