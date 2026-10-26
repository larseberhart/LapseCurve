import Foundation
import LapseCurveDomain

/// Controls for deterministic, read-only directory discovery.
public struct SequenceScanOptions: Sendable {
    /// Whether subdirectories are included.
    public var recursive: Bool
    /// Lowercased filename extensions accepted as photo files.
    public var supportedExtensions: Set<String>
    /// Whether reliable capture timestamps participate in ordering.
    public var sortByCaptureTime: Bool
    /// Whether to resolve ratings and mark exactly-one-star keyframes.
    public var detectKeyframesFromOneStarRating: Bool
    /// Whether hidden files and directories are included.
    public var includeHiddenFiles: Bool
    /// Previously imported frames used to retain identities across rescans.
    public var previousFrames: [ImageFrame]

    /// Creates scan options.
    public init(
        recursive: Bool = false,
        supportedExtensions: Set<String> = SequenceScanOptions.defaultSupportedExtensions,
        sortByCaptureTime: Bool = true,
        detectKeyframesFromOneStarRating: Bool = true,
        includeHiddenFiles: Bool = false,
        previousFrames: [ImageFrame] = []
    ) {
        self.recursive = recursive
        self.supportedExtensions = Set(supportedExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        self.sortByCaptureTime = sortByCaptureTime
        self.detectKeyframesFromOneStarRating = detectKeyframesFromOneStarRating
        self.includeHiddenFiles = includeHiddenFiles
        self.previousFrames = previousFrames
    }

    /// Common RAW and raster formats considered for initial discovery.
    public static let defaultSupportedExtensions: Set<String> = [
        "dng", "nef", "nrw", "cr2", "cr3", "arw", "srf", "sr2",
        "raf", "rw2", "orf", "pef", "srw", "jpg", "jpeg", "tif",
        "tiff", "png", "heic"
    ]
}