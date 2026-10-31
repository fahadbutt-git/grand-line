// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Finder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QueryKit", targets: ["QueryKit"]),
        .library(name: "IndexKit", targets: ["IndexKit"]),
        .library(name: "FileKit", targets: ["FileKit"]),
        .library(name: "ArchiveKit", targets: ["ArchiveKit"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
        .library(name: "LaunchKit", targets: ["LaunchKit"]),
    ],
    targets: [
        .target(name: "QueryKit"),
        .target(name: "IndexKit"),
        .target(name: "FileKit", dependencies: ["IndexKit"]),
        .target(name: "ArchiveKit"),
        .target(name: "ThemeKit", dependencies: ["IndexKit"]),
        .target(name: "LaunchKit"),
        .testTarget(name: "QueryKitTests", dependencies: ["QueryKit"]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
        .testTarget(name: "FileKitTests", dependencies: ["FileKit", "IndexKit"]),
        .testTarget(name: "ArchiveKitTests", dependencies: ["ArchiveKit"]),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit"]),
        .testTarget(name: "LaunchKitTests", dependencies: ["LaunchKit"]),
    ]
)
