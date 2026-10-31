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
        .library(name: "BrowserKit", targets: ["BrowserKit"]),
        .executable(name: "LogPose", targets: ["LogPose"]),
        .library(name: "LauncherKit", targets: ["LauncherKit"]),
        .executable(name: "Byakugan", targets: ["Byakugan"]),
    ],
    targets: [
        .target(name: "QueryKit"),
        .target(name: "IndexKit"),
        .target(name: "FileKit", dependencies: ["IndexKit"]),
        .target(name: "ArchiveKit"),
        .target(name: "ThemeKit", dependencies: ["IndexKit"]),
        .target(name: "LaunchKit"),
        .target(
            name: "BrowserKit",
            dependencies: ["QueryKit", "IndexKit", "FileKit", "ArchiveKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "LogPose",
            dependencies: ["BrowserKit", "QueryKit", "IndexKit", "FileKit", "ArchiveKit", "ThemeKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("Quartz"), .linkedFramework("QuickLookThumbnailing")]
        ),
        .target(
            name: "LauncherKit",
            dependencies: ["IndexKit", "QueryKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Byakugan",
            dependencies: ["LauncherKit", "IndexKit", "QueryKit", "ThemeKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("Quartz"), .linkedFramework("Carbon"), .linkedFramework("ApplicationServices"), .linkedFramework("CoreServices")]
        ),
        .testTarget(name: "QueryKitTests", dependencies: ["QueryKit"]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
        .testTarget(name: "FileKitTests", dependencies: ["FileKit", "IndexKit"]),
        .testTarget(name: "ArchiveKitTests", dependencies: ["ArchiveKit"]),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit"]),
        .testTarget(name: "LaunchKitTests", dependencies: ["LaunchKit"]),
        .testTarget(
            name: "BrowserKitTests",
            dependencies: ["BrowserKit", "FileKit", "IndexKit", "ArchiveKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "LauncherKitTests", dependencies: ["LauncherKit", "IndexKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
