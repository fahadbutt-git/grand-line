// swift-tools-version: 6.0
import PackageDescription

// The app icons of Grand Line, shared by Nexus, Sight and Iceberg.
//
// AppIcon holds the glyphs (as a table that tools/make-icons.py also reads,
// so the bundled .icns files and the icons drawn at run time match), the
// ICON_* theme keys and their fallbacks, and the AppKit drawing.
let package = Package(
    name: "AppIcons",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppIcon", targets: ["AppIcon"]),
    ],
    targets: [
        .target(name: "AppIcon"),
        .testTarget(name: "AppIconTests", dependencies: ["AppIcon"]),
    ],
    swiftLanguageModes: [.v5]
)
