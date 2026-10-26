enum InspectorSection: String, CaseIterable, Identifiable {
    case frame = "Frame"
    case development = "Development"

    var id: String { rawValue }
}