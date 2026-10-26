import LapseCurveDomain

/// A capture-derived relative exposure sample and its inverse development correction.
public struct CaptureExposureSample: Equatable, Sendable {
    /// Capture exposure value using the configured reference ISO.
    public let captureEV: Double
    /// Capture EV centered on the median valid frame in the analyzed sequence.
    public let relativeEV: Double
    /// Inverse development exposure change; positive capture EV yields negative correction.
    public let correctionEV: Double

    public init(captureEV: Double, relativeEV: Double, correctionEV: Double) {
        self.captureEV = captureEV
        self.relativeEV = relativeEV
        self.correctionEV = correctionEV
    }
}

/// Read-only capture analysis keyed by stable frame identity.
public struct CaptureExposureCurve: Sendable {
    public let referenceISO: Double
    public let referenceEV: Double?
    public let samplesByFrameID: [FrameID: CaptureExposureSample]
    public let diagnostics: [ValidationIssue]

    public init(
        referenceISO: Double,
        referenceEV: Double?,
        samplesByFrameID: [FrameID: CaptureExposureSample],
        diagnostics: [ValidationIssue]
    ) {
        self.referenceISO = referenceISO
        self.referenceEV = referenceEV
        self.samplesByFrameID = samplesByFrameID
        self.diagnostics = diagnostics
    }
}
