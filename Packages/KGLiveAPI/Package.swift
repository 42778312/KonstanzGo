// swift-tools-version: 6.0
import PackageDescription

// The live server's API, shared by the app and the server: Codable types and the trip key, Foundation only,
// so it builds on iOS, macOS and Linux. A change here breaks the build on both sides instead of breaking users.
let package = Package(
    name: "KGLiveAPI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "KGLiveAPI", targets: ["KGLiveAPI"])],
    targets: [
        .target(name: "KGLiveAPI"),
        .testTarget(name: "KGLiveAPITests", dependencies: ["KGLiveAPI"]),
    ],
    swiftLanguageModes: [.v6]
)
