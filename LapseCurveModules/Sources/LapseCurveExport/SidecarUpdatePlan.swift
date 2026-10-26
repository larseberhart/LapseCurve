import Foundation
import LapseCurveDomain

/// Read-only preflight result; it contains no generated sidecar bytes or output paths.
public struct SidecarUpdatePlan: Sendable {
    /// Existing intermediate sidecars eligible for explicitly approved updates.
    public var updates: [PlannedSidecarUpdate]
    /// Warnings and skips produced during preflight.
    public var warnings: [ValidationIssue]

    /// Creates a preflight plan.
    public init(updates: [PlannedSidecarUpdate], warnings: [ValidationIssue]) {
        self.updates = updates
        self.warnings = warnings
    }
}

public struct PlannedSidecarUpdate: Sendable {
    public let frame: ImageFrame
    public let sidecar: ExistingSidecarSnapshot
    public let values: [DevelopmentParameter: Double]

    public init(frame: ImageFrame, sidecar: ExistingSidecarSnapshot, values: [DevelopmentParameter: Double]) {
        self.frame = frame
        self.sidecar = sidecar
        self.values = values
    }
}

public struct ExistingSidecarSnapshot: Equatable, Sendable {
    public let frameID: FrameID
    public let url: URL
    public let data: Data
    public let fingerprint: FileFingerprint

    public init(frameID: FrameID, url: URL, data: Data, fingerprint: FileFingerprint) {
        self.frameID = frameID
        self.url = url
        self.data = data
        self.fingerprint = fingerprint
    }
}