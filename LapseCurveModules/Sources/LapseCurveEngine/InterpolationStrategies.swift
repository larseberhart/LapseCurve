enum LinearInterpolation {
    static func value(start: Double, end: Double, progress: Double) -> Double {
        start + (end - start) * progress
    }
}

enum SmoothstepInterpolation {
    static func value(start: Double, end: Double, progress: Double) -> Double {
        let easedProgress = progress * progress * (3 - 2 * progress)
        return start + (end - start) * easedProgress
    }
}

enum HoldInterpolation {
    static func value(start: Double) -> Double {
        start
    }
}