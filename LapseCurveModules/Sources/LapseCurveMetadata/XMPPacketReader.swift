import Foundation

/// Reads bounded XMP packets without modifying or normalizing their source bytes.
public struct XMPPacketReader: Sendable {
    /// Maximum accepted packet size in bytes.
    public let maximumPacketSizeBytes: Int

    /// Creates a reader with an explicit packet-size limit.
    /// - Parameter maximumPacketSizeBytes: Positive maximum input size; defaults to 16 MiB.
    public init(maximumPacketSizeBytes: Int = 16 * 1024 * 1024) {
        self.maximumPacketSizeBytes = maximumPacketSizeBytes
    }

    /// Parses an XMP packet while retaining the exact input data.
    /// - Parameter data: Original XMP packet bytes.
    /// - Returns: Namespace-aware properties and the unchanged packet bytes.
    /// - Throws: `XMPReadError` for malformed, unsupported or resource-excessive input.
    public func read(_ data: Data) throws -> XMPPacket {
        guard maximumPacketSizeBytes > 0 else {
            throw XMPReadError.invalidPacketSizeLimit
        }
        guard data.count <= maximumPacketSizeBytes else {
            throw XMPReadError.packetTooLarge(maximumBytes: maximumPacketSizeBytes)
        }
        guard !containsDocumentTypeDeclaration(data) else {
            throw XMPReadError.documentTypeNotAllowed
        }

        let document: XMLDocument
        do {
            document = try XMLDocument(
                data: data,
                options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw XMPReadError.malformedXML
        }

        guard let root = document.rootElement(), isSupportedRoot(root) else {
            throw XMPReadError.unsupportedRoot
        }

        let properties = try scalarProperties(in: root)
        return XMPPacket(originalData: data, properties: properties)
    }

    private func isSupportedRoot(_ element: XMLElement) -> Bool {
        let xmpMetadataNamespace = "adobe:ns:meta/"
        let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        return (element.localName == "xmpmeta" && element.uri == xmpMetadataNamespace)
            || (element.localName == "RDF" && element.uri == rdfNamespace)
    }

    private func scalarProperties(in root: XMLElement) throws -> [XMPProperty] {
        let maximumElementDepth = 128
        let maximumPropertyCount = 100_000
        let xmlnsNamespace = "http://www.w3.org/2000/xmlns/"
        var properties: [XMPProperty] = []
        var pendingNodes: [(node: XMLNode, depth: Int)] = [(root, 0)]

        while let current = pendingNodes.popLast() {
            guard current.depth <= maximumElementDepth else {
                throw XMPReadError.maximumDepthExceeded
            }
            guard let element = current.node as? XMLElement else {
                continue
            }

            for attribute in element.attributes ?? [] {
                guard let namespaceURI = attribute.uri,
                      namespaceURI != xmlnsNamespace,
                      let localName = attribute.localName,
                      let value = attribute.stringValue else {
                    continue
                }
                properties.append(
                    XMPProperty(namespaceURI: namespaceURI, localName: localName, value: value)
                )
                guard properties.count <= maximumPropertyCount else {
                    throw XMPReadError.maximumPropertyCountExceeded
                }
            }

            let children = element.children ?? []
            let hasElementChildren = children.contains { $0.kind == .element }
            if !hasElementChildren,
               let namespaceURI = element.uri,
               let localName = element.localName,
               let value = element.stringValue,
               !value.isEmpty {
                properties.append(
                    XMPProperty(namespaceURI: namespaceURI, localName: localName, value: value)
                )
                guard properties.count <= maximumPropertyCount else {
                    throw XMPReadError.maximumPropertyCountExceeded
                }
            }

            for child in children {
                pendingNodes.append((child, current.depth + 1))
            }
        }

        return properties
    }

    private func containsDocumentTypeDeclaration(_ data: Data) -> Bool {
        let declaration = "<!DOCTYPE"
        let utf8 = Data(declaration.utf8)
        let utf16LittleEndian = Data(declaration.utf16.flatMap { [UInt8($0 & 0x00FF), UInt8($0 >> 8)] })
        let utf16BigEndian = Data(declaration.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0x00FF)] })
        return data.range(of: utf8) != nil
            || data.range(of: utf16LittleEndian) != nil
            || data.range(of: utf16BigEndian) != nil
    }
}