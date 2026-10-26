import Foundation

/// Read-only parsed view retaining the exact original packet bytes.
public struct XMPPacket: Equatable, Sendable {
    /// Original bytes retained without serialization or normalization.
    public let originalData: Data
    /// Namespace-aware scalar properties; duplicates remain separate entries.
    public let properties: [XMPProperty]

    init(originalData: Data, properties: [XMPProperty]) {
        self.originalData = originalData
        self.properties = properties
    }
}