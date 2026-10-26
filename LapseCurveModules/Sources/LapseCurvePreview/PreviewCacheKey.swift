import Foundation
import CryptoKit
import LapseCurveDomain

/// Cache identity including source versions and requested output dimensions.
public struct PreviewCacheKey: Hashable, Sendable {
    /// Stable frame identity.
    public let frameID: FrameID
    /// Canonical source path.
    public let sourcePath: String
    /// Source fingerprint captured at the request boundary.
    public let sourceFingerprint: FileFingerprint?
    /// Explicit companion JPEG path, if any.
    public let companionPath: String?
    /// Companion file fingerprint, if available.
    public let companionFingerprint: FileFingerprint?
    /// Maximum requested dimension in pixels.
    public let maximumPixelSize: Int

    /// Stable cache filename token for a disk entry.
    var diskFileName: String {
        let fingerprintString = [sourceFingerprint, companionFingerprint]
            .map { fingerprint in
                guard let fingerprint else { return "-" }
                return "\(fingerprint.byteCount):\(fingerprint.modificationDate?.timeIntervalSince1970 ?? 0):\(fingerprint.digest ?? "-")"
            }
            .joined(separator: "|")
        let identity = [
            frameID.rawValue.uuidString,
            sourcePath,
            fingerprintString,
            companionPath ?? "-",
            String(maximumPixelSize)
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Creates a cache identity for a preview request.
    public init(
        frameID: FrameID,
        sourcePath: String,
        sourceFingerprint: FileFingerprint?,
        companionPath: String?,
        companionFingerprint: FileFingerprint?,
        maximumPixelSize: Int
    ) {
        self.frameID = frameID
        self.sourcePath = sourcePath
        self.sourceFingerprint = sourceFingerprint
        self.companionPath = companionPath
        self.companionFingerprint = companionFingerprint
        self.maximumPixelSize = maximumPixelSize
    }
}