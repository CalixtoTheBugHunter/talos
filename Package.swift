// swift-tools-version: 6.2

import PackageDescription

/// Platform, architecture, and toolchain are SPEC decisions, not defaults:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain
let package = Package(
    name: "Talos",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TalosCore", targets: ["TalosCore"]),
        .library(name: "TalosPersistence", targets: ["TalosPersistence"]),
        .library(name: "TalosProjectLibrary", targets: ["TalosProjectLibrary"]),
        .library(name: "TalosSafeguards", targets: ["TalosSafeguards"]),
        .library(name: "TalosAdapters", targets: ["TalosAdapters"]),
        .library(name: "TalosOrchestration", targets: ["TalosOrchestration"]),
        .library(name: "TalosUI", targets: ["TalosUI"])
    ],
    targets: [
        .target(name: "TalosCore"),
        .testTarget(name: "TalosCoreTests", dependencies: ["TalosCore"]),

        .target(
            name: "TalosPersistence",
            dependencies: ["TalosCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "TalosPersistenceTests", dependencies: ["TalosPersistence"]),

        .target(
            name: "TalosProjectLibrary",
            dependencies: ["TalosCore", "TalosPersistence"]
        ),

        .target(name: "TalosSafeguards", dependencies: ["TalosCore"]),

        .target(name: "TalosAdapters", dependencies: ["TalosCore"]),

        .target(
            name: "TalosOrchestration",
            dependencies: [
                "TalosCore",
                "TalosProjectLibrary",
                "TalosSafeguards",
                "TalosAdapters",
                "TalosPersistence"
            ]
        ),

        .target(name: "TalosUI", dependencies: ["TalosOrchestration"])
    ]
)
