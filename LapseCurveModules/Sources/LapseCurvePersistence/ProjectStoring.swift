import Foundation
import LapseCurveDomain

/// File-based persistence boundary for portable project documents.
public protocol ProjectStoring: Sendable {
    /// Loads and validates a project document.
    func load(from url: URL) async throws -> TimeLapseProject

    /// Atomically saves a validated project and preserves the prior valid file for recovery.
    func save(_ project: TimeLapseProject, to url: URL) async throws

    /// Loads the most recent valid snapshot saved before the last replacement.
    func loadRecoverySnapshot(for url: URL) async throws -> TimeLapseProject
}