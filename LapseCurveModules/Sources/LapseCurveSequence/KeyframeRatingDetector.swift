import LapseCurveDomain

/// Applies a conservative source policy for one-star keyframe detection.
public enum KeyframeRatingDetector {
    /// Resolves ratings without guessing when metadata sources disagree.
    ///
    /// A valid sidecar rating is preferred when it agrees with embedded metadata. A conflict
    /// is unresolved and never promotes a frame to keyframe. Exactly rating `1` is a keyframe.
    public static func resolve(
        embedded: RatingMetadataRead,
        sidecar: RatingMetadataRead,
        frameID: FrameID
    ) -> KeyframeRatingResolution {
        let embeddedValues = Set(embedded.values)
        let sidecarValues = Set(sidecar.values)
        var warnings: [ValidationIssue] = []

        if sidecar.status == .malformed {
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "ratingValueMalformed",
                    message: "The XMP sidecar contains malformed rating data; keyframe status is unresolved.",
                    frameID: frameID
                )
            )
            return unresolved(warnings: warnings)
        }

        if sidecarValues.count > 1 {
            warnings.append(conflictWarning(frameID: frameID))
            return unresolved(warnings: warnings)
        }

        if let rating = sidecarValues.first {
            if embedded.status == .malformed || embeddedValues.count > 1
                || embeddedValues.first.map({ $0 != rating }) == true {
                warnings.append(conflictWarning(frameID: frameID))
            }
            return resolved(rating, source: .xmpSidecar, warnings: warnings)
        }

        if embedded.status == .malformed {
            warnings.append(
                ValidationIssue(
                    severity: .warning,
                    code: "ratingValueMalformed",
                    message: "Embedded rating data is malformed and no valid XMP sidecar rating is available.",
                    frameID: frameID
                )
            )
            return unresolved(warnings: warnings)
        }
        if embeddedValues.count > 1 {
            warnings.append(conflictWarning(frameID: frameID))
            return unresolved(warnings: warnings)
        }
        if let rating = embeddedValues.first {
            return resolved(rating, source: .embeddedMetadata, warnings: warnings)
        }

        warnings.append(
            ValidationIssue(
                severity: .warning,
                code: "ratingUnavailable",
                message: "No readable rating was found; this frame is not confirmed as a keyframe.",
                frameID: frameID
            )
        )
        return unresolved(warnings: warnings)
    }

    private static func resolved(
        _ rating: Int,
        source: RatingSource,
        warnings: [ValidationIssue]
    ) -> KeyframeRatingResolution {
        KeyframeRatingResolution(
            rating: rating,
            source: source,
            isKeyframe: rating == 1,
            isUnreadable: false,
            warnings: warnings
        )
    }

    private static func unresolved(warnings: [ValidationIssue]) -> KeyframeRatingResolution {
        KeyframeRatingResolution(
            rating: nil,
            source: .unavailable,
            isKeyframe: false,
            isUnreadable: true,
            warnings: warnings
        )
    }

    private static func conflictWarning(frameID: FrameID) -> ValidationIssue {
        ValidationIssue(
            severity: .warning,
            code: "ratingSourceConflict",
            message: "Embedded and sidecar ratings conflict; the valid XMP sidecar rating is authoritative.",
            frameID: frameID
        )
    }
}