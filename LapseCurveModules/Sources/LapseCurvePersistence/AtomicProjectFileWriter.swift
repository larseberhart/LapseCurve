import Foundation

/// Writes a document through a same-directory temporary file and atomic replacement.
struct AtomicProjectFileWriter: ProjectFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        guard destinationURL.isFileURL else {
            throw ProjectRepositoryError.invalidFileURL
        }
        let parentURL = destinationURL.deletingLastPathComponent()
        var isParentDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isParentDirectory),
              isParentDirectory.boolValue else {
            throw ProjectRepositoryError.parentDirectoryMissing
        }

        let fileManager = FileManager.default
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists {
            let values = try destinationURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ProjectRepositoryError.destinationNotRegularFile
            }
        }

        let temporaryURL = parentURL.appendingPathComponent(".lapsecurve-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try data.write(to: temporaryURL, options: [.withoutOverwriting])
            let fileHandle = try FileHandle(forWritingTo: temporaryURL)
            try fileHandle.synchronize()
            try fileHandle.close()

            if destinationExists {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch let error as ProjectRepositoryError {
            throw error
        } catch {
            throw ProjectRepositoryError.fileOperationFailed
        }
    }
}