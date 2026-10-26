import Foundation
import LapseCurveDomain

/// Actor-isolated repository for validated single-file project documents.
public actor CodableProjectRepository: ProjectStoring {
    private let codec: ProjectDocumentCodec
    private let fileWriter: any ProjectFileWriting
    private let recoveryStore = RecoverySnapshotStore()

    /// Creates a repository using optional verified parameter definitions.
    public init(parameterDefinitions: [ParameterDefinition] = []) {
        codec = ProjectDocumentCodec(parameterDefinitions: parameterDefinitions)
        fileWriter = AtomicProjectFileWriter()
    }

    init(parameterDefinitions: [ParameterDefinition] = [], fileWriter: any ProjectFileWriting) {
        codec = ProjectDocumentCodec(parameterDefinitions: parameterDefinitions)
        self.fileWriter = fileWriter
    }

    /// Loads, migrates and validates a project document.
    public func load(from url: URL) async throws -> TimeLapseProject {
        guard url.isFileURL else {
            throw ProjectRepositoryError.invalidFileURL
        }
        do {
            return try codec.decode(Data(contentsOf: url, options: [.mappedIfSafe]))
        } catch let error as ProjectRepositoryError {
            throw error
        } catch {
            throw ProjectRepositoryError.fileOperationFailed
        }
    }

    /// Saves a validated document atomically, preserving the prior valid bytes for recovery.
    public func save(_ project: TimeLapseProject, to url: URL) async throws {
        guard url.isFileURL else {
            throw ProjectRepositoryError.invalidFileURL
        }
        let newDocument = try codec.encode(project)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            let existingDocument: Data
            do {
                existingDocument = try Data(contentsOf: url, options: [.mappedIfSafe])
            } catch {
                throw ProjectRepositoryError.fileOperationFailed
            }
            _ = try codec.decode(existingDocument)
            try recoveryStore.preserve(existingDocument, for: url)
        }
        do {
            try fileWriter.write(newDocument, to: url)
        } catch let error as ProjectRepositoryError {
            throw error
        } catch {
            throw ProjectRepositoryError.fileOperationFailed
        }
    }

    /// Loads and validates the latest recovery snapshot for a project.
    public func loadRecoverySnapshot(for url: URL) async throws -> TimeLapseProject {
        guard url.isFileURL else {
            throw ProjectRepositoryError.invalidFileURL
        }
        let recoveryURL = recoveryStore.snapshotURL(for: url)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else {
            throw ProjectRepositoryError.recoverySnapshotMissing
        }
        do {
            return try codec.decode(Data(contentsOf: recoveryURL, options: [.mappedIfSafe]))
        } catch let error as ProjectRepositoryError {
            throw error
        } catch {
            throw ProjectRepositoryError.fileOperationFailed
        }
    }
}