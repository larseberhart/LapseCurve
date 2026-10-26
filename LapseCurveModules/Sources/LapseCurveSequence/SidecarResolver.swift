import Foundation

/// Resolves same-basename metadata sidecars without reading or changing them.
public enum SidecarResolver {
    /// Finds a unique `.xmp` sidecar and detects a `.acr` companion.
    /// Matching is case-insensitive and scoped to the image's parent directory.
    public static func resolve(for imageURL: URL, among directoryContents: [URL]) -> SidecarResolution {
        let imageBaseName = imageURL.deletingPathExtension().lastPathComponent.lowercased()
        let matchingURLs = directoryContents.filter {
            $0.deletingPathExtension().lastPathComponent.lowercased() == imageBaseName
        }
        let xmpCandidates = matchingURLs
            .filter { $0.pathExtension.lowercased() == "xmp" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let hasACRSidecar = matchingURLs.contains { $0.pathExtension.lowercased() == "acr" }

        return SidecarResolution(
            xmpURL: xmpCandidates.count == 1 ? xmpCandidates[0] : nil,
            hasAmbiguousXMP: xmpCandidates.count > 1,
            hasACRSidecar: hasACRSidecar
        )
    }
}