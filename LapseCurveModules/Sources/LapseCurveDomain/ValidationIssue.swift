/// Structured diagnostic associated with a frame or parameter when applicable.
public struct ValidationIssue: Codable, Equatable, Sendable {
    /// Diagnostic severity.
    public var severity: IssueSeverity
    /// Stable machine-readable issue identifier.
    public var code: String
    /// Human-readable diagnostic text.
    public var message: String
    /// Related frame, if any.
    public var frameID: FrameID?
    /// Related parameter, if any.
    public var parameter: DevelopmentParameter?

    /// Creates a structured validation issue.
    public init(
        severity: IssueSeverity,
        code: String,
        message: String,
        frameID: FrameID? = nil,
        parameter: DevelopmentParameter? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.frameID = frameID
        self.parameter = parameter
    }
}