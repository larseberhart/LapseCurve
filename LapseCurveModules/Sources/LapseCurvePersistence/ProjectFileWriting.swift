import Foundation

/// Injectable boundary for atomic project-document writes.
protocol ProjectFileWriting: Sendable {
    func write(_ data: Data, to destinationURL: URL) throws
}
