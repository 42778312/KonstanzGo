// swift-tools-version: 6.0
import PackageDescription

// The app's code outside the app target:
// - KGCore: data and logic (timetable, routing, search). No UI. Tests run on macOS with `swift test`.
// - KGDesign: colours, type, motion, icons, Seeri, components. No data.
// - KGFeatures: the screens. Uses both.
let package = Package(
    name: "KonstanzKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KGCore", targets: ["KGCore"]),
        .library(name: "KGDesign", targets: ["KGDesign"]),
        .library(name: "KGFeatures", targets: ["KGFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        // The live server's API, shared with Server/: a change breaks the build on both sides.
        .package(path: "../KGLiveAPI"),
        // The offline map. iOS only, so `swift test` keeps running on the Mac.
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", exact: "6.31.0"),
    ],
    targets: [
        .target(
            name: "KGCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KGLiveAPI", package: "KGLiveAPI"),
            ]
        ),
        .target(name: "KGDesign", resources: [.process("Resources")]),
        .target(
            name: "KGFeatures",
            dependencies: [
                "KGCore", "KGDesign",
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution", condition: .when(platforms: [.iOS])),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "KGCoreTests", dependencies: ["KGCore"]),
        .testTarget(name: "KGDesignTests", dependencies: ["KGDesign"]),
        .testTarget(name: "KGFeaturesTests", dependencies: ["KGFeatures"]),
    ],
    swiftLanguageModes: [.v6]
)
