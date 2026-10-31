// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Finder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QueryKit", targets: ["QueryKit"]),
        .library(name: "IndexKit", targets: ["IndexKit"]),
        .library(name: "IndexService", targets: ["IndexService"]),
        .library(name: "FileKit", targets: ["FileKit"]),
        .library(name: "ArchiveKit", targets: ["ArchiveKit"]),
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
        .library(name: "LaunchKit", targets: ["LaunchKit"]),
        .library(name: "BrowserKit", targets: ["BrowserKit"]),
        .executable(name: "Nexus", targets: ["Nexus"]),
        .library(name: "LauncherKit", targets: ["LauncherKit"]),
        .executable(name: "Sight", targets: ["Sight"]),
        // The background agent both apps search through (Grand Line Index.app).
        .executable(name: "GrandLineIndex", targets: ["GrandLineIndex"]),
    ],
    dependencies: [
        // The app icons, shared with Iceberg.
        .package(path: "../icons"),
    ],
    targets: [
        .target(name: "QueryKit"),
        .target(name: "IndexKit"),
        // XPC between the apps and the index agent: Foundation's NSXPCConnection,
        // which predates Sendable, so Swift 5 mode.
        .target(
            name: "IndexService",
            dependencies: ["IndexKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "GrandLineIndex",
            dependencies: ["IndexKit", "IndexService"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .target(name: "FileKit", dependencies: ["IndexKit"]),
        .target(name: "ArchiveKit"),
        .target(name: "ThemeKit", dependencies: ["IndexKit", .product(name: "AppIcon", package: "icons")]),
        .target(name: "LaunchKit"),
        // The Settings window both apps share: its layout, the Appearance pane and Update now.
        .target(
            name: "SettingsKit",
            dependencies: ["ThemeKit", "IndexKit", .product(name: "AppIcon", package: "icons")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),
        .target(
            name: "BrowserKit",
            dependencies: ["QueryKit", "IndexKit", "FileKit", "ArchiveKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Nexus",
            dependencies: ["BrowserKit", "QueryKit", "IndexKit", "IndexService", "FileKit", "ArchiveKit", "ThemeKit", "LaunchKit", "SettingsKit",
                           .product(name: "AppIcon", package: "icons")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("Quartz"), .linkedFramework("QuickLookThumbnailing")]
        ),
        .target(
            name: "LauncherKit",
            dependencies: ["IndexKit", "QueryKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Sight",
            dependencies: ["LauncherKit", "IndexKit", "IndexService", "QueryKit", "ThemeKit", "LaunchKit", "SettingsKit",
                           .product(name: "AppIcon", package: "icons")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("Quartz"), .linkedFramework("Carbon"), .linkedFramework("ApplicationServices"), .linkedFramework("CoreServices")]
        ),
        .testTarget(name: "QueryKitTests", dependencies: ["QueryKit"]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
        .testTarget(
            name: "IndexServiceTests",
            dependencies: ["IndexService", "IndexKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "FileKitTests", dependencies: ["FileKit", "IndexKit"]),
        .testTarget(name: "ArchiveKitTests", dependencies: ["ArchiveKit"]),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit", .product(name: "AppIcon", package: "icons")]),
        .testTarget(name: "LaunchKitTests", dependencies: ["LaunchKit"]),
        .testTarget(
            name: "BrowserKitTests",
            dependencies: ["BrowserKit", "FileKit", "IndexKit", "ArchiveKit", "LaunchKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "LauncherKitTests", dependencies: ["LauncherKit", "IndexKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
