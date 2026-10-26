import Foundation

/// Associated Lightroom sidecars found beside one source image.
public struct SidecarResolution: Equatable, Sendable {
    /// Unique matching XMP sidecar, or `nil` when missing or ambiguous.
    public var xmpURL: URL?
    /// Whether more than one same-basename XMP candidate was found.
    public var hasAmbiguousXMP: Bool
    /// Whether a same-basename ACR sidecar exists; it is never opened or modified.
    public var hasACRSidecar: Bool

    /// Creates a sidecar resolution result.
    public init(xmpURL: URL?, hasAmbiguousXMP: Bool, hasACRSidecar: Bool) {
        self.xmpURL = xmpURL
        self.hasAmbiguousXMP = hasAmbiguousXMP
        self.hasACRSidecar = hasACRSidecar
    }
}