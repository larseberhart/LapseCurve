import AppKit
import UniformTypeIdentifiers

@MainActor
enum ProjectFilePanels {
    private static let projectType = UTType(filenameExtension: "lapsecurve", conformingTo: .data) ?? .data

    static func saveURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [projectType]
        panel.nameFieldStringValue = suggestedName.hasSuffix(".lapsecurve")
            ? suggestedName
            : "\(suggestedName).lapsecurve"
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return nil
        }
        guard selectedURL.pathExtension.lowercased() != "lapsecurve" else { return selectedURL }
        return selectedURL.deletingPathExtension().appendingPathExtension("lapsecurve")
    }

    static func openURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [projectType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }
}