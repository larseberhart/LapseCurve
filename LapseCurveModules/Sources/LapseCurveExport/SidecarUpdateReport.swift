import Foundation
import LapseCurveDomain

/// Aggregate result for a sequential, bounded sidecar update run.
public struct SidecarUpdateReport: Sendable {
    /// Results in the same order as the input plan.
    public let frameResults: [SidecarUpdateFrameReport]
    /// True when the operation observed task cancellation.
    public let wasCancelled: Bool

    /// Creates an update report.
    public init(frameResults: [SidecarUpdateFrameReport], wasCancelled: Bool) {
        self.frameResults = frameResults
        self.wasCancelled = wasCancelled
    }

    /// True only when every planned update completed successfully.
    public var isComplete: Bool {
        !wasCancelled && frameResults.allSatisfy { $0.status == .updated }
    }

    /// Number of sidecars successfully updated.
    public var updatedCount: Int {
        frameResults.filter { $0.status == .updated }.count
    }

    /// Number of updates refused or failed.
    public var failedCount: Int {
        frameResults.filter { $0.status == .failed }.count
    }

    /// Number of updates not performed because approval was missing or cancellation occurred.
    public var notAttemptedCount: Int {
        frameResults.filter { $0.status == .notApproved || $0.status == .cancelled }.count
    }
}

public enum SidecarUpdateStatus: String, Codable, CaseIterable, Sendable {
    case updated
    case failed
    case notApproved
    case cancelled
}

public struct SidecarUpdateFrameReport: Sendable {
    public let frameID: FrameID
    public let sidecarURL: URL
    public let status: SidecarUpdateStatus
    public let message: String?
    public let updatedMetadata: RawMetadataDocument?

    public init(
        frameID: FrameID, sidecarURL: URL, status: SidecarUpdateStatus,
        message: String? = nil, updatedMetadata: RawMetadataDocument? = nil
    ) {
        self.frameID = frameID
        self.sidecarURL = sidecarURL
        self.status = status
        self.message = message
        self.updatedMetadata = updatedMetadata
    }
}

public struct SidecarUpdateProgress: Sendable {
    public let completedCount: Int
    public let totalCount: Int
    public let frameID: FrameID?

    public init(completedCount: Int, totalCount: Int, frameID: FrameID?) {
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.frameID = frameID
    }
}

public struct SidecarUpdateReceipt: Sendable {
    public let frameID: FrameID
    public let sidecarURL: URL
    public let updatedFingerprint: FileFingerprint
    public let updatedMetadata: RawMetadataDocument?

    public init(frameID: FrameID, sidecarURL: URL, updatedFingerprint: FileFingerprint, updatedMetadata: RawMetadataDocument? = nil) {
        self.frameID = frameID
        self.sidecarURL = sidecarURL
        self.updatedFingerprint = updatedFingerprint
        self.updatedMetadata = updatedMetadata
    }
}