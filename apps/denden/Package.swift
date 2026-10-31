// swift-tools-version: 6.0
import PackageDescription

// Den Den, the notch app of Grand Line.
//
// DenDenKit holds everything that can be tested without a screen: config
// parsing, command running, refresh scheduling, themes, layout and the
// Now Playing stream. DenDen is the AppKit and SwiftUI app on top of it.
// MediaRemoteAdapter is the vendored Now Playing helper (BSD-3), built as a
// dynamic library that /usr/bin/perl loads; Den Den does not link it.
let package = Package(
    name: "DenDen",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DenDen", targets: ["DenDen"]),
        .library(name: "DenDenKit", targets: ["DenDenKit"]),
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    targets: [
        .target(name: "DenDenKit"),
        .executableTarget(
            name: "DenDen",
            dependencies: ["DenDenKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
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
        .testTarget(name: "DenDenKitTests", dependencies: ["DenDenKit"]),
    ],
    // Swift 5 mode: strict concurrency checks warn instead of failing the build.
    swiftLanguageModes: [.v5]
)
