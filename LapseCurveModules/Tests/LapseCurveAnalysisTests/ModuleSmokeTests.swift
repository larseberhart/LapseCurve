import Testing
@testable import LapseCurveAnalysis

@Test func moduleTargetIsImportable() {
    #expect(String(reflecting: PackageTarget.self).hasPrefix("LapseCurveAnalysis."))
}