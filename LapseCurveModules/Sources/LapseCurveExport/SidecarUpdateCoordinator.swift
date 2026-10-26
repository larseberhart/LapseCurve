import Foundation
import LapseCurveDomain
import LapseCurveMetadata

/// Serializes user-approved updates to existing intermediate-frame sidecars.
public actor SidecarUpdateCoordinator {
    private let packetReader: XMPPacketReader
    private let packetWriter: XMPPacketWriter
    private let fileManager: FileManager

    /// Creates a coordinator with bounded metadata parsing and in-memory updates.
    public init(
        maximumPacketSizeBytes: Int = 16 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        packetReader = XMPPacketReader(maximumPacketSizeBytes: maximumPacketSizeBytes)
        packetWriter = XMPPacketWriter(maximumPacketSizeBytes: maximumPacketSizeBytes)
        self.fileManager = fileManager
    }

    /// Applies an immutable plan sequentially and reports every frame outcome.
    ///
    /// A sequential actor implementation bounds concurrency to one file. Progress is delivered
    /// after each attempted or skipped entry; cancellation leaves completed updates reported and
    /// marks remaining entries cancelled. The operation never creates a sidecar path.
    public func update(
        _ plan: SidecarUpdatePlan,
        using definitions: [ParameterDefinition],
        explicitlyApproved: Bool,
        progress: (@Sendable (SidecarUpdateProgress) async -> Void)? = nil
    ) async -> SidecarUpdateReport {
        var frameResults: [SidecarUpdateFrameReport] = []
        var wasCancelled = false

        for (index, plannedUpdate) in plan.updates.enumerated() {
            let frameID = plannedUpdate.frame.id
            let sidecarURL = plannedUpdate.sidecar.url
            let result: SidecarUpdateFrameReport

            if Task.isCancelled {
                wasCancelled = true
                result = SidecarUpdateFrameReport(
                    frameID: frameID,
                    sidecarURL: sidecarURL,
                    status: .cancelled,
                    message: "Update was cancelled before this frame was processed."
                )
            } else if !explicitlyApproved {
                result = SidecarUpdateFrameReport(
                    frameID: frameID,
                    sidecarURL: sidecarURL,
                    status: .notApproved,
                    message: "Explicit user approval was not provided."
                )
            } else {
                do {
                    let receipt = try update(
                        plannedUpdate,
                        using: definitions,
                        explicitlyApproved: true
                    )
                    result = SidecarUpdateFrameReport(
                        frameID: frameID,
                        sidecarURL: sidecarURL,
                        status: .updated,
                        updatedMetadata: receipt.updatedMetadata
                    )
                } catch is CancellationError {
                    wasCancelled = true
                    result = SidecarUpdateFrameReport(
                        frameID: frameID,
                        sidecarURL: sidecarURL,
                        status: .cancelled,
                        message: "Update was cancelled before commit."
                    )
                } catch {
                    result = SidecarUpdateFrameReport(
                        frameID: frameID,
                        sidecarURL: sidecarURL,
                        status: .failed,
                        message: error.localizedDescription
                    )
                }
            }

            frameResults.append(result)
            await progress?(SidecarUpdateProgress(
                completedCount: index + 1,
                totalCount: plan.updates.count,
                frameID: frameID
            ))

            if wasCancelled {
                for pendingUpdate in plan.updates.dropFirst(index + 1) {
                    frameResults.append(
                        SidecarUpdateFrameReport(
                            frameID: pendingUpdate.frame.id,
                            sidecarURL: pendingUpdate.sidecar.url,
                            status: .cancelled,
                            message: "Update was not attempted because the run was cancelled."
                        )
                    )
                }
                break
            }
        }

        return SidecarUpdateReport(frameResults: frameResults, wasCancelled: wasCancelled)
    }

    /// Applies one approved plan entry to its existing sidecar.
    ///
    /// No URL is created: the source must exist, be a regular XMP file and match its
    /// preflight bytes. No backup is written; the sidecar is replaced atomically.
    public func update(
        _ update: PlannedSidecarUpdate,
        using definitions: [ParameterDefinition],
        explicitlyApproved: Bool
    ) throws -> SidecarUpdateReceipt {
        try Task.checkCancellation()
        guard explicitlyApproved else {
            throw SidecarUpdateError.explicitApprovalRequired
        }
        guard update.frame.rating != 1, update.frame.keyframeID == nil else {
            throw SidecarUpdateError.keyframeIsImmutable(update.frame.id)
        }

        let sidecarURL = update.sidecar.url
        guard sidecarURL.isFileURL, sidecarURL.pathExtension.lowercased() == "xmp" else {
            throw SidecarUpdateError.invalidSidecarURL(sidecarURL)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sidecarURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw SidecarUpdateError.sidecarMissing(sidecarURL)
        }

        do {
            let currentData = try Data(contentsOf: sidecarURL, options: [.mappedIfSafe])
            guard currentData == update.sidecar.data else {
                throw SidecarUpdateError.sourceChanged(update.frame.id)
            }

            let updatedData = try packetWriter.updating(
                sourceData: currentData,
                values: update.values,
                for: update.frame,
                using: definitions
            )
            try verify(update.values, in: updatedData, using: definitions)
            try Task.checkCancellation()

            let lockURL = sidecarURL.appendingPathExtension("lapsecurve-lock")
            do {
                try Data().write(to: lockURL, options: [.withoutOverwriting])
            } catch {
                throw SidecarUpdateError.sourceChanged(update.frame.id)
            }
            defer { try? fileManager.removeItem(at: lockURL) }

            let latestData = try Data(contentsOf: sidecarURL, options: [.mappedIfSafe])
            guard latestData == update.sidecar.data else {
                throw SidecarUpdateError.sourceChanged(update.frame.id)
            }

            let stagingURL = sidecarURL.deletingLastPathComponent()
                .appendingPathComponent(".lapsecurve-\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: stagingURL) }
            try updatedData.write(to: stagingURL, options: [.withoutOverwriting])
            try verify(update.values, in: Data(contentsOf: stagingURL, options: [.mappedIfSafe]), using: definitions)
            try Task.checkCancellation()

            let finalData = try Data(contentsOf: sidecarURL, options: [.mappedIfSafe])
            guard finalData == update.sidecar.data else {
                throw SidecarUpdateError.sourceChanged(update.frame.id)
            }
            _ = try fileManager.replaceItemAt(sidecarURL, withItemAt: stagingURL)
            let committedData = try Data(contentsOf: sidecarURL, options: [.mappedIfSafe])
            guard committedData == updatedData else {
                throw SidecarUpdateError.sourceChanged(update.frame.id)
            }
            try verify(update.values, in: committedData, using: definitions)

            let attributes = try fileManager.attributesOfItem(atPath: sidecarURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? Int64(updatedData.count)
            let modificationDate = attributes[.modificationDate] as? Date
            let fingerprint = FileFingerprint(byteCount: byteCount, modificationDate: modificationDate, digest: nil)
            return SidecarUpdateReceipt(
                frameID: update.frame.id,
                sidecarURL: sidecarURL,
                updatedFingerprint: fingerprint,
                updatedMetadata: RawMetadataDocument(
                    data: updatedData, mediaType: "application/rdf+xml", sourceFingerprint: fingerprint
                )
            )
        } catch let error as SidecarUpdateError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SidecarUpdateError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func verify(
        _ values: [DevelopmentParameter: Double],
        in data: Data,
        using definitions: [ParameterDefinition]
    ) throws {
        let packet = try packetReader.read(data)
        for (parameter, expectedValue) in values {
            guard let definition = definitions.first(where: { $0.parameter == parameter }) else {
                throw SidecarUpdateError.writtenValueMismatch(parameter)
            }
            let matches = packet.properties.filter {
                $0.namespaceURI == definition.namespaceURI && $0.localName == definition.xmpTag
            }
            guard matches.count == 1,
                  let actualValue = Double(matches[0].value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  actualValue == Double(XMPFieldRegistry.formattedValue(expectedValue, for: parameter)) else {
                throw SidecarUpdateError.writtenValueMismatch(parameter)
            }
        }
    }
}