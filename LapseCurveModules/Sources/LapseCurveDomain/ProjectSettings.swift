/// Project-wide interpolation and export behavior.
public struct ProjectSettings: Codable, Equatable, Sendable {
    /// Coordinate system used for interpolation.
    public var timeBasis: TimeBasis
    /// Default interpolation strategy.
    public var defaultInterpolation: ParameterInterpolation
    /// Policy for missing keyframe parameter values.
    public var missingValuePolicy: MissingValuePolicy
    /// Explicit canonical values required by the `useDefault` missing-value policy.
    public var parameterDefaults: [DevelopmentParameter: Double]
    /// Export destination policy.
    public var exportMode: ExportMode
    public var segmentInterpolations: [SegmentInterpolation]

    /// Creates project settings.
    public init(
        timeBasis: TimeBasis,
        defaultInterpolation: ParameterInterpolation,
        missingValuePolicy: MissingValuePolicy,
        parameterDefaults: [DevelopmentParameter: Double] = [:],
        exportMode: ExportMode,
        segmentInterpolations: [SegmentInterpolation] = []
    ) {
        self.timeBasis = timeBasis
        self.defaultInterpolation = defaultInterpolation
        self.missingValuePolicy = missingValuePolicy
        self.parameterDefaults = parameterDefaults
        self.exportMode = exportMode
        self.segmentInterpolations = segmentInterpolations
    }

    private enum CodingKeys: String, CodingKey {
        case timeBasis, defaultInterpolation, missingValuePolicy, parameterDefaults, exportMode, segmentInterpolations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeBasis = try container.decode(TimeBasis.self, forKey: .timeBasis)
        defaultInterpolation = try container.decode(ParameterInterpolation.self, forKey: .defaultInterpolation)
        missingValuePolicy = try container.decode(MissingValuePolicy.self, forKey: .missingValuePolicy)
        parameterDefaults = try container.decode([DevelopmentParameter: Double].self, forKey: .parameterDefaults)
        exportMode = try container.decode(ExportMode.self, forKey: .exportMode)
        segmentInterpolations = try container.decodeIfPresent([SegmentInterpolation].self, forKey: .segmentInterpolations) ?? []
    }
}

public struct SegmentInterpolation: Codable, Equatable, Sendable {
    public let startFrameID: FrameID
    public let endFrameID: FrameID
    public var mode: ParameterInterpolation

    public init(startFrameID: FrameID, endFrameID: FrameID, mode: ParameterInterpolation) {
        self.startFrameID = startFrameID
        self.endFrameID = endFrameID
        self.mode = mode
    }
}