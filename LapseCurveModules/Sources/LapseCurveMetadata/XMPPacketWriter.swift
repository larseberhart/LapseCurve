import Foundation
import LapseCurveDomain

/// Updates mapped scalar Camera Raw properties while retaining other XMP content.
public struct XMPPacketWriter: Sendable {
    private let reader: XMPPacketReader
    private let cameraRawNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"

    /// Creates a writer using the bounded packet reader.
    public init(maximumPacketSizeBytes: Int = 16 * 1024 * 1024) {
        reader = XMPPacketReader(maximumPacketSizeBytes: maximumPacketSizeBytes)
    }

    /// Produces updated XMP bytes for one intermediate, non-keyframe image.
    ///
    /// The method updates or adds scalar properties whose definitions are explicitly marked
    /// writable. It never creates a sidecar file. Keyframe ratings or identities always block
    /// the operation, even if the requested values are unchanged.
    /// - Parameters:
    ///   - sourceData: Original XMP packet bytes.
    ///   - values: Calculated values keyed by domain parameter.
    ///   - frame: Destination frame; keyframe frames are rejected.
    ///   - definitions: Explicitly enabled property mappings and configured ranges.
    /// - Returns: Serialized XMP with untouched tree content retained.
    /// - Throws: `XMPReadError` or `XMPWriteError` when the source or update is unsafe.
    public func updating(
        sourceData: Data,
        values: [DevelopmentParameter: Double],
        for frame: ImageFrame,
        using definitions: [ParameterDefinition]
    ) throws -> Data {
        guard frame.rating != 1, frame.keyframeID == nil else {
            throw XMPWriteError.keyframeMetadataIsImmutable
        }
        guard frame.metadataStatus != .conflict else {
            throw XMPWriteError.conflictingFrameMetadata
        }

        let sourcePacket = try reader.read(sourceData)
        let ratingNamespace = "http://ns.adobe.com/xap/1.0/"
        let packetRatings = sourcePacket.properties.filter {
            $0.namespaceURI == ratingNamespace && $0.localName == "Rating"
        }.map(\.value)
        guard !packetRatings.contains(where: { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) == 1 }) else {
            throw XMPWriteError.keyframeMetadataIsImmutable
        }
        guard Set(packetRatings).count <= 1 else {
            throw XMPWriteError.conflictingFrameMetadata
        }

        let document: XMLDocument
        do {
            document = try XMLDocument(
                data: sourceData,
                options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw XMPReadError.malformedXML
        }
        guard let root = document.rootElement() else {
            throw XMPReadError.unsupportedRoot
        }
        let targetDescription = rdfDescriptions(in: root).first

        var definitionsByParameter: [DevelopmentParameter: ParameterDefinition] = [:]
        for definition in definitions {
            guard definitionsByParameter[definition.parameter] == nil else {
                throw XMPWriteError.parameterNotApproved(definition.parameter)
            }
            definitionsByParameter[definition.parameter] = definition
        }

        for (parameter, value) in values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let definition = definitionsByParameter[parameter], definition.writable else {
                throw XMPWriteError.parameterNotApproved(parameter)
            }
            guard definition.namespaceURI == cameraRawNamespace else {
                throw XMPWriteError.unsupportedNamespace(parameter)
            }
            guard value.isFinite,
                  definition.validRange?.contains(value) ?? true else {
                throw XMPWriteError.invalidValue(parameter)
            }
            let formattedValue = XMPFieldRegistry.formattedValue(value, for: parameter)
            let matchingNodes = propertyNodes(
                in: root,
                namespaceURI: definition.namespaceURI,
                localName: definition.xmpTag
            )
            guard matchingNodes.count <= 1 else {
                throw XMPWriteError.duplicateProperty(parameter)
            }
            guard let propertyNode = matchingNodes.first else {
                guard let targetDescription else {
                    throw XMPWriteError.propertyMissing(parameter)
                }
                let prefix = ensureNamespacePrefix(
                    for: definition.namespaceURI,
                    on: targetDescription
                )
                let attribute = XMLNode.attribute(
                    withName: "\(prefix):\(definition.xmpTag)",
                    uri: definition.namespaceURI,
                    stringValue: formattedValue
                ) as! XMLNode
                addAttributePreservingSuffixNames(attribute, to: targetDescription)
                continue
            }

            if propertyNode.kind == .attribute {
                propertyNode.stringValue = formattedValue
                continue
            }

            guard let element = propertyNode as? XMLElement,
                  !(element.children ?? []).contains(where: { $0.kind == .element }),
                  !(element.attributes ?? []).contains(where: {
                      $0.uri != "http://www.w3.org/2000/xmlns/"
                  }),
                  let description = element.parent as? XMLElement,
                  description.localName == "Description",
                  description.uri == "http://www.w3.org/1999/02/22-rdf-syntax-ns#" else {
                throw XMPWriteError.structuredProperty(parameter)
            }
            let prefix = ensureNamespacePrefix(
                for: definition.namespaceURI,
                on: description
            )
            let attribute = XMLNode.attribute(
                withName: "\(prefix):\(definition.xmpTag)",
                uri: definition.namespaceURI,
                stringValue: formattedValue
            ) as! XMLNode
            addAttributePreservingSuffixNames(attribute, to: description)
            element.detach()
        }

        if values[.temperature] != nil || values[.tint] != nil {
            try setCustomWhiteBalanceMode(in: root, targetDescription: targetDescription)
        }

        // Without crs:CameraProfile Lightroom falls back to Adobe Standard instead of the crd: default it was showing.
        if !values.isEmpty,
           let targetDescription,
           propertyNodes(in: root, namespaceURI: cameraRawNamespace, localName: "CameraProfile").isEmpty {
            let defaultProfiles = sourcePacket.properties.filter {
                $0.namespaceURI == XMPFieldRegistry.cameraRawDefaultsNamespace && $0.localName == "CameraProfile"
            }
            if defaultProfiles.count == 1 {
                let prefix = ensureNamespacePrefix(for: cameraRawNamespace, on: targetDescription)
                let attribute = XMLNode.attribute(
                    withName: "\(prefix):CameraProfile",
                    uri: cameraRawNamespace,
                    stringValue: defaultProfiles[0].value
                ) as! XMLNode
                addAttributePreservingSuffixNames(attribute, to: targetDescription)
            }
        }

        removeFormattingWhitespace(from: root)
        let serializedData = document.xmlData(options: [.nodePreserveAll, .nodePrettyPrint])
        let outputData = formattedXMPData(serializedData)
        _ = try reader.read(outputData)
        return outputData
    }

    private func removeFormattingWhitespace(from node: XMLNode) {
        guard let element = node as? XMLElement else { return }
        let children = element.children ?? []
        if children.contains(where: { $0.kind == .element }) {
            for child in children where child.kind == .text {
                if child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    child.detach()
                }
            }
        }
        for child in element.children ?? [] {
            removeFormattingWhitespace(from: child)
        }
    }

    private func addAttributePreservingSuffixNames(_ attribute: XMLNode, to description: XMLElement) {
        let localName = attribute.localName ?? ""
        let namespaceURI = attribute.uri
        let displacedAttributes = (description.attributes ?? []).filter { existing in
            guard let existingLocalName = existing.localName,
                  existingLocalName != localName,
                  existing.uri == namespaceURI else {
                return false
            }
            return existingLocalName.hasSuffix(localName)
        }

        displacedAttributes.forEach { $0.detach() }
        description.addAttribute(attribute)
        for displacedAttribute in displacedAttributes.sorted(by: {
            ($0.localName?.count ?? 0) < ($1.localName?.count ?? 0)
        }) {
            description.addAttribute(displacedAttribute)
        }
    }

    private func setCustomWhiteBalanceMode(in root: XMLNode, targetDescription: XMLElement?) throws {
        let matchingNodes = propertyNodes(
            in: root,
            namespaceURI: cameraRawNamespace,
            localName: XMPFieldRegistry.whiteBalanceModeTag
        )
        guard matchingNodes.count <= 1 else {
            throw XMPWriteError.duplicateProperty(.temperature)
        }
        if let modeNode = matchingNodes.first {
            if let element = modeNode as? XMLElement,
               (element.children ?? []).contains(where: { $0.kind == .element }) {
                throw XMPWriteError.structuredProperty(.temperature)
            }
            modeNode.stringValue = "Custom"
            return
        }
        guard let targetDescription else {
            throw XMPWriteError.propertyMissing(.temperature)
        }
        let prefix = ensureNamespacePrefix(
            for: cameraRawNamespace,
            on: targetDescription
        )
        let attribute = XMLNode.attribute(
            withName: "\(prefix):\(XMPFieldRegistry.whiteBalanceModeTag)",
            uri: cameraRawNamespace,
            stringValue: "Custom"
        ) as! XMLNode
        targetDescription.addAttribute(attribute)
    }

    private func rdfDescriptions(in root: XMLNode) -> [XMLElement] {
        let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        var descriptions: [XMLElement] = []
        var pendingNodes = [root]
        while let node = pendingNodes.popLast() {
            if let element = node as? XMLElement,
               element.localName == "Description",
               element.uri == rdfNamespace {
                descriptions.append(element)
            }
            pendingNodes.append(contentsOf: node.children ?? [])
        }
        return descriptions
    }

    private func ensureNamespacePrefix(
        for namespaceURI: String,
        on description: XMLElement
    ) -> String {
        var inScopeNamespaces: [String: String] = [:]
        var current: XMLNode? = description
        while let element = current as? XMLElement {
            for namespace in element.namespaces ?? [] {
                guard let name = namespace.name,
                      let uri = namespace.stringValue else { continue }
                let prefix = name.hasPrefix("xmlns:") ? String(name.dropFirst(6)) : name
                if !prefix.isEmpty, inScopeNamespaces[prefix] == nil {
                    inScopeNamespaces[prefix] = uri
                }
            }
            current = element.parent
        }
        if let existing = inScopeNamespaces.first(where: { $0.value == namespaceURI })?.key {
            return existing
        }

        var prefix = "crs"
        var suffix = 1
        while inScopeNamespaces[prefix] != nil {
            prefix = "crs\(suffix)"
            suffix += 1
        }
        let namespace = XMLNode.namespace(withName: prefix, stringValue: namespaceURI) as! XMLNode
        description.addNamespace(namespace)
        return prefix
    }

    private func formattedXMPData(_ data: Data) -> Data {
        var source = String(decoding: data, as: UTF8.self)
        if source.hasPrefix("<?xml"), let declarationEnd = source.range(of: "?>") {
            source.removeSubrange(source.startIndex..<declarationEnd.upperBound)
            while source.first?.isNewline == true {
                source.removeFirst()
            }
        }

        let characters = Array(source)
        var formatted = ""
        var inTag = false
        var inQuote: Character?
        var tagIndent = 0
        var attributeName = ""
        var currentAttributeIsNamespace = false
        var afterNamespaceAttribute = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "<", index + 1 < characters.count,
               characters[index + 1] != "!", characters[index + 1] != "?" {
                inTag = true
                tagIndent = formatted.reversed().prefix(while: { $0 == " " }).count
                attributeName = ""
            } else if inTag, inQuote == nil, character == " ",
                      afterNamespaceAttribute || isNamespaceDeclarationStart(in: characters, at: index + 1) {
                formatted.append("\n")
                formatted.append(String(repeating: " ", count: tagIndent + 4))
                attributeName = ""
                currentAttributeIsNamespace = false
                afterNamespaceAttribute = false
                while index + 1 < characters.count, characters[index + 1] == " " {
                    index += 1
                }
                index += 1
                continue
            }

            formatted.append(character)
            if inTag {
                if let quote = inQuote {
                    if character == quote {
                        inQuote = nil
                        afterNamespaceAttribute = currentAttributeIsNamespace
                        currentAttributeIsNamespace = false
                    }
                } else if character == "\"" || character == "'" {
                    inQuote = character
                } else if character == "=" {
                    currentAttributeIsNamespace = attributeName.hasPrefix("xmlns")
                    attributeName = ""
                } else if character == ">" {
                    inTag = false
                    afterNamespaceAttribute = false
                } else if character.isWhitespace {
                    attributeName = ""
                } else {
                    attributeName.append(character)
                }
            }
            index += 1
        }
        let normalizedLines = formatted.components(separatedBy: .newlines).map { line in
            let indentationCount = line.prefix(while: { $0 == " " }).count
            return String(repeating: " ", count: indentationCount / 4)
                + line.dropFirst(indentationCount)
        }
        return Data(normalizedLines.joined(separator: "\n").utf8)
    }

    private func isNamespaceDeclarationStart(in characters: [Character], at index: Int) -> Bool {
        guard index + 5 <= characters.count,
              String(characters[index..<index + 5]) == "xmlns" else {
            return false
        }
        return index + 5 == characters.count
            || characters[index + 5] == ":"
            || characters[index + 5] == "="
    }

    private func propertyNodes(
        in root: XMLNode,
        namespaceURI: String,
        localName: String
    ) -> [XMLNode] {
        var matches: [XMLNode] = []
        var pendingNodes = [root]

        while let node = pendingNodes.popLast() {
            if let element = node as? XMLElement {
                matches.append(contentsOf: (element.attributes ?? []).filter {
                    $0.uri == namespaceURI && $0.localName == localName
                })
            }
            if node.kind == .element,
               node.uri == namespaceURI,
               node.localName == localName {
                matches.append(node)
            }
            pendingNodes.append(contentsOf: node.children ?? [])
        }

        return matches
    }
}