import Foundation

/// Keeps one atomic recovery snapshot beside a project document.
struct RecoverySnapshotStore: Sendable {
    private let writer = AtomicProjectFileWriter()

    func snapshotURL(for projectURL: URL) -> URL {
        projectURL.appendingPathExtension("recovery")
    }

    func preserve(_ previousDocument: Data, for projectURL: URL) throws {
        try writer.write(previousDocument, to: snapshotURL(for: projectURL))
    }
}