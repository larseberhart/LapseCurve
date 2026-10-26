import Foundation
import LapseCurveDomain

/// Deterministic sequence ordering and timestamp diagnostics.
public enum SequenceOrdering {
    /// Sorts frames by reliable capture time when requested, then by natural filename/path.
    public static func sort(_ frames: [ImageFrame], sortByCaptureTime: Bool) -> [ImageFrame] {
        frames.sorted { leftFrame, rightFrame in
            if sortByCaptureTime,
               let leftTime = leftFrame.captureTime,
               let rightTime = rightFrame.captureTime,
               leftTime != rightTime {
                return leftTime < rightTime
            }
            return naturalPathLessThan(leftFrame.relativePath, rightFrame.relativePath)
        }
    }

    /// Reports missing and duplicate timestamps when capture-time ordering is enabled.
    public static func timestampWarnings(
        for frames: [ImageFrame],
        sortByCaptureTime: Bool
    ) -> [ValidationIssue] {
        guard sortByCaptureTime else {
            return []
        }
        var warnings: [ValidationIssue] = []
        var framesByTimestamp: [Date: [FrameID]] = [:]

        for frame in frames {
            guard let captureTime = frame.captureTime else {
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "captureTimeMissing",
                        message: "Capture time is unavailable; filename order is used as a deterministic fallback.",
                        frameID: frame.id
                    )
                )
                continue
            }
            framesByTimestamp[captureTime, default: []].append(frame.id)
        }

        for frameIDs in framesByTimestamp.values where frameIDs.count > 1 {
            for frameID in frameIDs {
                warnings.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "captureTimeDuplicate",
                        message: "Capture time is shared by multiple frames; filename order breaks the tie.",
                        frameID: frameID
                    )
                )
            }
        }
        return warnings
    }

    private static func naturalPathLessThan(_ leftPath: String, _ rightPath: String) -> Bool {
        let comparison = leftPath.compare(
            rightPath,
            options: [.numeric, .caseInsensitive, .literal],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return comparison == .orderedAscending
    }
}