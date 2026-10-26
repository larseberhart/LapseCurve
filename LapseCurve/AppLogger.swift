import OSLog

enum AppLogger {
    private static let application = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.larseberhart.lapsecurve.LapseCurve",
        category: "application"
    )

    static func logLaunch() {
        application.info("LapseCurve launched")
    }
}