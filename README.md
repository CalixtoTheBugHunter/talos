# talos

AI Plataform for Software Developement

The **SPEC lives in the [wiki](https://github.com/CalixtoTheBugHunter/talos/wiki)** and is the source
of truth. This file states how to build; it does not restate any rule the wiki owns. Work is tracked
on the [Talos Board](https://github.com/users/CalixtoTheBugHunter/projects/5).

## Build prerequisites

| | Requirement | Why |
| --- | --- | --- |
| OS | **macOS 26** or later | [Technology & Distribution § Decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions) |
| Hardware | **Apple Silicon (arm64)** | Same page — the app bundle is `arm64` only. The package target needs the `xcodebuild` overrides [below](#build-and-test) |
| Xcode | **Xcode 26** or later, with its license accepted | Swift Testing ships inside Xcode; the Command Line Tools alone cannot build or test this project |
| Swift | **6.2** toolchain (bundled with Xcode 26) | `swift-tools-version` in `Package.swift` |

Xcode must be the selected developer directory, and its license must be accepted, before either
command below works:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Build and test

```bash
swift build                                    # the SPM package
swift test                                     # Swift Testing suite
xcodebuild -project Talos.xcodeproj -scheme Talos \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build                # the app bundle
```

The `ARCHS`/`ONLY_ACTIVE_ARCH` overrides are **required, not optional**: they are the only way to
keep the package target from also compiling for `x86_64`, and the reason is a documented limitation
on the wiki —
[Technology & Distribution § Intel Macs, Rosetta, and universal binaries](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#intel-macs-rosetta-and-universal-binaries).

Open `Talos.xcodeproj` in Xcode to build and test from the IDE; the local Swift package is
referenced by the project, so no separate checkout step is needed.

## Layout

| Path | Contains |
| --- | --- |
| `Package.swift` | The Swift package — `TalosCore` and its test target |
| `Sources/` | Package sources |
| `Tests/` | Swift Testing suites |
| `Talos/` | The app target's sources, `Info.plist`, and entitlements |
| `Talos.xcodeproj` | The app project — deployment target, architecture, Hardened Runtime |
| `docs/github/` | Repository configuration kept as reviewable files |
| `.github/workflows/` | CI — the stages, their order, and which are still unbuilt are on the wiki: [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) |
| `.claude/skills/` | The skills that carry the dev cycle — see [`.claude/skills/README.md`](.claude/skills/README.md) |

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md), which points at the wiki pages that bind a change.
