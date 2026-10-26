import Foundation

/// One scalar property found in an XMP packet.
public struct XMPProperty: Hashable, Sendable {
    /// Namespace URI, independent of the packet's chosen XML prefix.
    public let namespaceURI: String
    /// Local property name.
    public let localName: String
    /// Unnormalized text value found in the packet.
    public let value: String

    /// Creates a parsed XMP property value.
    public init(namespaceURI: String, localName: String, value: String) {
        self.namespaceURI = namespaceURI
        self.localName = localName
        self.value = value
    }
}