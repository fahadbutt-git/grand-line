// swift-tools-version: 6.0
import PackageDescription

// Iceberg, the notch app of Grand Line.
//
// IcebergKit holds everything that can be tested without a screen: config
// parsing, command running, refresh scheduling, themes, layout and the
// Now Playing stream. Iceberg is the AppKit and SwiftUI app on top of it.
// MediaRemoteAdapter is the vendored Now Playing helper (BSD-3), built as a
// dynamic library that /usr/bin/perl loads; Iceberg does not link it.
let package = Package(
    name: "Iceberg",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Iceberg", targets: ["Iceberg"]),
        .library(name: "IcebergKit", targets: ["IcebergKit"]),
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    dependencies: [
        // The app icons, shared with Nexus and Sight.
        .package(path: "../icons"),
    ],
    targets: [
        .target(name: "IcebergKit"),
        .executableTarget(
            name: "Iceberg",
            dependencies: ["IcebergKit", .product(name: "AppIcon", package: "icons"), .product(name: "AppRuntime", package: "icons")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                // The HUDs (volume, Bluetooth headphones, the key tap) and the
                // shelf's background removal.
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage"),
            ]
        ),
        .target(
            name: "MediaRemoteAdapter",
            path: "Vendor/mediaremote-adapter",
            exclude: ["LICENSE", "VENDORED.md", "src/test"],
            sources: ["src/adapter", "src/private", "src/utility"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .unsafeFlags(["-fobjc-arc", "-fvisibility=default"]),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreServices"),
                .linkedFramework("MediaPlayer"),
            ]
        ),
        .testTarget(name: "IcebergKitTests", dependencies: ["IcebergKit"]),
    ],
    // Swift 5 mode: strict concurrency checks warn instead of failing the build.
    swiftLanguageModes: [.v5]
)
