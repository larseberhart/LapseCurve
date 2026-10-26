import LapseCurveDomain

/// Applies explicit document-schema migrations before project validation.
public enum ProjectMigrator {
    /// Returns a current-schema document or rejects versions without a defined migration.
    /// - Parameter project: Decoded document value.
    /// - Throws: `ProjectRepositoryError.unsupportedSchemaVersion` if no migration is defined.
    public static func migrate(_ project: TimeLapseProject) throws -> TimeLapseProject {
        if project.schemaVersion == 1 {
            var migratedProject = project
            migratedProject.schemaVersion = ProjectSchema.currentVersion
            migratedProject.settings.segmentInterpolations = []
            return migratedProject
        }
        guard project.schemaVersion == ProjectSchema.currentVersion else {
            throw ProjectRepositoryError.unsupportedSchemaVersion(project.schemaVersion)
        }
        return project
    }
}