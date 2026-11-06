// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Finder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QueryKit", targets: ["QueryKit"]),
        .library(name: "IndexKit", targets: ["IndexKit"]),
        .library(name: "IndexService", targets: ["IndexService"]),
        .library(name: "LaunchKit", targets: ["LaunchKit"]),
        .library(name: "LauncherKit", targets: ["LauncherKit"]),
        .executable(name: "Sight", targets: ["Sight"]),
        // The background agent Sight searches through (Grand Line Index.app).
        .executable(name: "GrandLineIndex", targets: ["GrandLineIndex"]),
    ],
    dependencies: [
        // AppRuntime (log, hang watchdog, crash guard), shared with Iceberg.
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
            dependencies: ["IndexKit", "IndexService", .product(name: "AppRuntime", package: "icons")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .target(name: "LaunchKit"),
        // Sight's Settings window: its layout, its controls, the index status and Update now.
        .target(
            name: "SettingsKit",
            dependencies: ["IndexKit"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),
        .target(
            name: "LauncherKit",
            dependencies: ["IndexKit", "QueryKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Sight",
            dependencies: ["LauncherKit", "IndexKit", "IndexService", "QueryKit", "LaunchKit", "SettingsKit",
                           .product(name: "AppRuntime", package: "icons")],
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
        .testTarget(name: "LaunchKitTests", dependencies: ["LaunchKit"]),
        // The shared runtime pieces (apps/icons, AppRuntime), tested here so CI runs them.
        .testTarget(name: "AppRuntimeTests", dependencies: [.product(name: "AppRuntime", package: "icons")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LauncherKitTests", dependencies: ["LauncherKit", "IndexKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
