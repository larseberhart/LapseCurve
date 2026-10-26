// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LapseCurveModules",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LapseCurveDomain", targets: ["LapseCurveDomain"]),
        .library(name: "LapseCurveSequence", targets: ["LapseCurveSequence"]),
        .library(name: "LapseCurveMetadata", targets: ["LapseCurveMetadata"]),
        .library(name: "LapseCurveEngine", targets: ["LapseCurveEngine"]),
        .library(name: "LapseCurveAnalysis", targets: ["LapseCurveAnalysis"]),
        .library(name: "LapseCurvePreview", targets: ["LapseCurvePreview"]),
        .library(name: "LapseCurveExport", targets: ["LapseCurveExport"]),
        .library(name: "LapseCurvePersistence", targets: ["LapseCurvePersistence"])
    ],
    targets: [
        .target(
            name: "LapseCurveDomain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurveSequence",
            dependencies: ["LapseCurveDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurveMetadata",
            dependencies: ["LapseCurveDomain", "LapseCurveSequence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurveEngine",
            dependencies: ["LapseCurveDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurveAnalysis",
            dependencies: ["LapseCurveDomain", "LapseCurveEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurvePreview",
            dependencies: ["LapseCurveDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurveExport",
            dependencies: ["LapseCurveDomain", "LapseCurveMetadata", "LapseCurveEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LapseCurvePersistence",
            dependencies: ["LapseCurveDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveDomainTests",
            dependencies: ["LapseCurveDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveSequenceTests",
            dependencies: ["LapseCurveSequence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveMetadataTests",
            dependencies: ["LapseCurveMetadata"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveEngineTests",
            dependencies: ["LapseCurveEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveAnalysisTests",
            dependencies: ["LapseCurveAnalysis"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurvePreviewTests",
            dependencies: ["LapseCurvePreview"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurveExportTests",
            dependencies: ["LapseCurveExport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LapseCurvePersistenceTests",
            dependencies: ["LapseCurvePersistence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)