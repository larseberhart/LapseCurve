import Foundation

/// Snapshot used to identify and detect changes to a source file.
public struct FileFingerprint: Codable, Equatable, Hashable, Sendable {
    /// File length in bytes when the fingerprint was recorded.
    public var byteCount: Int64
    /// File modification time when available.
    public var modificationDate: Date?
    /// Optional digest encoded as lowercase hexadecimal.
    public var digest: String?

    /// Creates a source-file fingerprint.
    public init(byteCount: Int64, modificationDate: Date?, digest: String?) {
        self.byteCount = byteCount
        self.modificationDate = modificationDate
        self.digest = digest
    }
}