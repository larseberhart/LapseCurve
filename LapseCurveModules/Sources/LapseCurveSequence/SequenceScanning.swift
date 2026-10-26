import Foundation

/// Capability for cancellable, read-only source-directory scans.
public protocol SequenceScanning: Sendable {
    /// Scans a directory and returns typed frames, warnings and counts.
    func scan(directory: URL, options: SequenceScanOptions) async throws -> SequenceScanResult
}