import AppKit
import SwiftUI

enum EditorPalette {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let insetPanel = Color(nsColor: .underPageBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.39)
    static let preview = Color(red: 0.105, green: 0.135, blue: 0.14)
    static let previewGrid = Color.white.opacity(0.07)
}