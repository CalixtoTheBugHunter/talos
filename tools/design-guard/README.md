# design-guard

The two checks the no-values rule needs that SwiftLint's `custom_rules` structurally cannot do, plus
the honest record of what each class is actually enforced by.

The rule is on the wiki and is not restated here:

- [Design System § The platform is the design system](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system)
- [Design System § Liquid Glass is inherited, never applied](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied)
- [Foundations: Accessibility § How the gate is checked](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked)
- [Decision Log § Engineering decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) — decision 56 is the decision this directory implements

## Run it

```bash
tools/design-guard/design-guard.sh     # scan this repository's tracked files
tools/design-guard/self-test.sh        # prove the rule still fails on a violation
```

Both run in the `lint` job, self-test first. `design-guard` is a **step inside `lint`**, not a stage
of its own, so it adds no required status check on `main` — see
[§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order).

## What enforces each class

Decision 56 enumerates eight violation classes. **Seven are SwiftLint's** — five through new custom
rules, two through rules already enabled — and class 3 is **split**, since the asset is not a Swift
file but the lookup that resolves it is. This directory owns that asset and the escape hatch. Two
classes have a residue that is review-enforced rather than claimed.

| # | Class | Enforced by | Rule ID |
| --- | --- | --- | --- |
| 1 | Hex and literal colors | `lint` — SwiftLint | `talos_no_hex_or_literal_color` |
| 2 | `#colorLiteral` | `lint` — SwiftLint, an **existing** rule | `discouraged_object_literal` |
| 3 | Bundled color assets — the asset | `lint` — **design-guard**, check 1 | — |
| 3 | Bundled color assets — the Swift-side lookup | `lint` — SwiftLint | `talos_no_named_color_asset` |
| 4 | Fixed font point sizes | `lint` — SwiftLint | `talos_no_fixed_point_size` |
| 5 | `Font.custom` | `lint` — SwiftLint | `talos_no_font_custom` |
| 6 | Hardcoded frame and spacing values | `lint` — SwiftLint, an **existing** rule, **partially** | `no_magic_numbers` |
| 7 | Custom materials and blurs | `lint` — SwiftLint, **partially** | `talos_no_hand_placed_blur` |
| 8 | Glass-effect modifiers on a Talos view | `lint` — SwiftLint | `talos_no_applied_glass_effect` |

Class 3's asset half is here rather than in `.swiftlint.yml` because a `.colorset` is a directory of
JSON. No SwiftLint configuration can reach one, however it is written. Its lookup half is not here,
because `Color("BrandBlue")` is ordinary Swift and a rule that matches it belongs where the other
Swift rules are.

## False-positive assessment, per rule

Decision 56 requires this, because "a rule developers disable is worse than no rule". Every row was
measured against SwiftLint 0.65.0, the version `ci.yml` pins.

| Rule | Risk | Why |
| --- | --- | --- |
| `talos_no_hex_or_literal_color` | Low | Matches an initializer argument label (`hex:`, `red:`, `white:`) or a quoted `#RRGGBB`. `Color(.red)` and `Color(nsColor:)` carry no such label and stay clean. `NSColor(named: "red")` is clean **of this rule** — it is `talos_no_named_color_asset` that reports it, one row down. |
| `talos_no_fixed_point_size` | Low | Requires `size:` or `ofSize:`. `Font.system(.body)` and `preferredFont(forTextStyle:)` — the correct spellings — stay clean. |
| `talos_no_font_custom` | Low | `.custom(` is required to be followed by a string literal, which is the font-name form. |
| `talos_no_hand_placed_blur` | Low | Two exact spellings, `.blur(radius:)` and `NSVisualEffectView`. |
| `talos_no_applied_glass_effect` | Low | **Inheriting** Liquid Glass involves no modifier at all, so these spellings cannot match a standard SwiftUI component that carries glass by default — the distinction [decision 20](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions) requires. |
| `talos_no_named_color_asset` | Low | Requires a color initializer immediately followed by a string literal or `named:`. Measured clean on `Color(.systemBlue)`, `Color(nsColor:)`, `Color.primary`, `Image("Logo")`, `Image(systemName:)`, and `NSImage(named:)` — a string in a non-color initializer is untouched, which is what keeps SF Symbol names out of it. |
| `no_magic_numbers` | Moderate, and pre-existing | Already enabled before decision 56. Measured: rejects `VStack(spacing: 12)`, `.padding(16)`, `.frame(width: 320, height: 240)`; leaves `.padding()` and `.frame(maxWidth: .infinity)` clean. |
| design-guard check 1 | None | A path match on `*.colorset/`. |
| design-guard check 2 | None | Reads a suppression's citation only. |

Every rule excludes `comment` and `docComment` kinds, so a comment that *describes* a forbidden
spelling is not a violation of it — otherwise this file's own reasoning would fail the build.

## What is NOT covered, stated so a green run is not read as a claim it never made

| Gap | Why it is here rather than in a rule |
| --- | --- |
| **Class 6's named-constant loophole.** `let panelWidth = 320` then `.frame(width: panelWidth)` | `no_magic_numbers` sees no literal. Decision 56 records this as **review-enforced**. Closing it needs a rule matching a numeric literal in `.frame`/`.padding`/`spacing:`, which is the one place in this rule set where real false positives live. |
| **Class 7's custom `Material` or `ShapeStyle` type.** A `struct FrostedMaterial: ShapeStyle` of Talos's own | The two greps catch a hand-placed blur, not a hand-written material type. **Review-enforced.** |
| **A hand-placed *system* material**, e.g. `.background(.ultraThinMaterial)` | The SPEC forbids "a **custom** material, tint, or blur behind a Talos surface". Whether hand-placing a *system* material is that is not something the page settles, so it is not decided in a regex here. It is an open SPEC question rather than a review residue: [Decision Log § Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions), the row asking whether a hand-placed system material is applying glass. |
| **Whether a cited suppression is legitimate** | Check 2 reads the citation, never whether the cited decision permits the suppression. That is a reviewer's judgement, and the citation is what makes it a short one. |

## The escape hatch

Per decision 56, a suppression is legal only with a `// SPEC: <wiki URL>` citation on the line
**immediately before** it:

```swift
// SPEC: https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
// swiftlint:disable:next talos_no_fixed_point_size
```

Without it, check 2 fails the build. The hatch is braked rather than removed because
`swiftlint:disable` suppresses a custom rule whether or not a hatch is decided — so the only
available choice was whether a suppression is **cited or invisible**. What stops it becoming
routine: each use names a Decision Log row that has to exist, the same requirement
[`spec-guard`](../spec-guard/README.md) places on its allowlist.

## Why the fixture is generated

`self-test.sh` writes its violating tree to a temporary directory. A hex literal or a `.colorset`
committed as a test fixture is itself the violation the rule exists to catch, and there is no
allowlist to exempt its path. Those generated literals are why `tools/design-guard/` is the one
directory `design-guard.sh` does not scan — the same structural exclusion
[`spec-guard`](../spec-guard/README.md) has, and for the same reason.
