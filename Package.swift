// swift-tools-version: 6.2

import PackageDescription

// Platform, architecture, and toolchain are SPEC decisions, not defaults:
// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution
// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain
let package = Package(
    name: "Talos",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TalosCore", targets: ["TalosCore"])
    ],
    targets: [
        .target(name: "TalosCore"),
        .testTarget(name: "TalosCoreTests", dependencies: ["TalosCore"])
    ]
)
