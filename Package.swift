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
    dependencies: [
        // YAML parsing for `.talos/*.yaml` — MIT, zero dependencies of its own,
        // wraps a vendored libyaml. Chosen over a hand-rolled parser because
        // `.talos/` is spec'd as human-editable plain text and a bespoke
        // parser would mis-handle legitimate hand-written YAML, which is the
        // exact thing "a human edit is not silently discarded" forbids:
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
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
            dependencies: ["TalosCore", "TalosPersistence", .product(name: "Yams", package: "Yams")]
        ),
        .testTarget(name: "TalosProjectLibraryTests", dependencies: ["TalosProjectLibrary"]),

        .target(name: "TalosSafeguards", dependencies: ["TalosCore"]),

        .target(name: "TalosAdapters", dependencies: ["TalosCore"]),
        .testTarget(name: "TalosAdaptersTests", dependencies: ["TalosAdapters"]),

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
