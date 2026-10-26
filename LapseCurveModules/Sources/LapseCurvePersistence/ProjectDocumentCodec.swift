import Foundation
import LapseCurveDomain

/// Encodes and validates the single-file Codable project document.
public struct ProjectDocumentCodec: Sendable {
    private let parameterDefinitions: [ParameterDefinition]

    /// Creates a codec with optional verified definitions for parameter-range validation.
    public init(parameterDefinitions: [ParameterDefinition] = []) {
        self.parameterDefinitions = parameterDefinitions
    }

    /// Encodes a validated project as sorted-key JSON.
    public func encode(_ project: TimeLapseProject) throws -> Data {
        try ProjectValidator.validate(project, parameterDefinitions: parameterDefinitions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(project)
        } catch {
            throw ProjectRepositoryError.encodingFailed
        }
    }

    /// Decodes a document, applies the explicit schema migration policy, then validates it.
    public func decode(_ data: Data) throws -> TimeLapseProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decodedProject: TimeLapseProject
        do {
            decodedProject = try decoder.decode(TimeLapseProject.self, from: data)
        } catch {
            throw ProjectRepositoryError.decodingFailed
        }

        let migratedProject = try ProjectMigrator.migrate(decodedProject)
        try ProjectValidator.validate(migratedProject, parameterDefinitions: parameterDefinitions)
        return migratedProject
    }
}