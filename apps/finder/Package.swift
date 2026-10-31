// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Finder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QueryKit", targets: ["QueryKit"]),
    ],
    targets: [
        .target(name: "QueryKit"),
        .testTarget(name: "QueryKitTests", dependencies: ["QueryKit"]),
    ]
)
