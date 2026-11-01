// swift-tools-version: 6.0
import PackageDescription

// The app icons of Grand Line, shared by Nexus, Sight and Iceberg, and the
// small runtime pieces they share (AppRuntime).
//
// AppIcon holds the glyphs (as a table that tools/make-icons.py also reads,
// so the bundled .icns files and the icons drawn at run time match), the
// ICON_* theme keys and their fallbacks, and the AppKit drawing.
let package = Package(
    name: "AppIcons",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppIcon", targets: ["AppIcon"]),
        // What every app does to stay out of the way: its log, the hang
        // watchdog, crash records and the crash-loop guard, the busy marker
        // the unattended update reads. Its tests are in apps/finder
        // (AppRuntimeTests), which CI builds and tests.
        .library(name: "AppRuntime", targets: ["AppRuntime"]),
    ],
    targets: [
        .target(name: "AppIcon"),
        .target(name: "AppRuntime"),
        .testTarget(name: "AppIconTests", dependencies: ["AppIcon"]),
    ],
    swiftLanguageModes: [.v5]
)
