// swift-tools-version: 6.0
import PackageDescription

// KonstanzGo Live: the small server that gives the app real-time delays.
// - LiveCore: all the logic, plain Swift, never imports Vapor. Tested with `swift test`.
// - LiveServer: the thin Vapor shell (routes, config, lifecycle).
// - Run: the executable.
let package = Package(
    name: "KonstanzGoLive",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../Packages/KGLiveAPI"),
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.3"),
        .package(url: "https://github.com/swift-server/async-http-client.git", exact: "1.37.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"])]),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.apt(["zlib1g-dev"])]),
        .target(
            name: "LiveCore",
            dependencies: [
                "CSQLite", "CZlib", "KGLiveAPI",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "LiveServer",
            dependencies: ["LiveCore", "KGLiveAPI", .product(name: "Vapor", package: "vapor")]
        ),
        .executableTarget(name: "Run", dependencies: ["LiveServer"]),
        .testTarget(name: "LiveCoreTests", dependencies: ["LiveCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
