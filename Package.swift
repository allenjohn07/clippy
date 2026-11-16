// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clippy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "clippy",
            path: "Sources/clippy",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "clippyTests",
            dependencies: ["clippy"],
            path: "Tests/clippyTests"
        ),
    ]
)
