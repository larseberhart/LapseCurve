import Foundation

/// Failure while validating or reading an XMP packet.
public enum XMPReadError: Error, Equatable, LocalizedError, Sendable {
    /// The packet exceeds the configured byte limit.
    case packetTooLarge(maximumBytes: Int)
    /// A nonpositive resource limit was configured.
    case invalidPacketSizeLimit
    /// A document type declaration is not accepted in XMP input.
    case documentTypeNotAllowed
    /// XML parsing failed.
    case malformedXML
    /// The root element is not an XMP metadata root.
    case unsupportedRoot
    /// Nested XML exceeds the supported depth.
    case maximumDepthExceeded
    /// The packet contains too many scalar properties.
    case maximumPropertyCountExceeded

    /// Human-readable explanation of the packet-read failure.
    public var errorDescription: String? {
        switch self {
        case .packetTooLarge(let maximumBytes):
            "XMP packet exceeds the \(maximumBytes)-byte limit."
        case .invalidPacketSizeLimit:
            "Maximum XMP packet size must be positive."
        case .documentTypeNotAllowed:
            "XMP packets containing a document type declaration are not accepted."
        case .malformedXML:
            "XMP packet is not well-formed XML."
        case .unsupportedRoot:
            "XML document does not have an XMP metadata root."
        case .maximumDepthExceeded:
            "XMP packet exceeds the supported XML nesting depth."
        case .maximumPropertyCountExceeded:
            "XMP packet exceeds the supported property count."
        }
    }
}