// swift-tools-version: 6.0
import PackageDescription

// The journey driver: launches the built app bundles against a fixture home
// folder, drives them with keystrokes, clicks and the Accessibility API the way
// a person would, checks the layout at every step and keeps a screenshot of it.
// It is its own package so the app packages stay untouched.
let package = Package(
    name: "Journeys",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "journeys", targets: ["Journeys"]),
    ],
    targets: [
        .executableTarget(
            name: "Journeys",
            path: "Sources/Journeys",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ],
    // Swift 5 mode: the driver is single-threaded and synchronous.
    swiftLanguageModes: [.v5]
)
