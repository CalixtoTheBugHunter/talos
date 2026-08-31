# Contributing to Talos

Contributions are welcome. **The contributing guide is the wiki, and it is the source of truth:
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing).**

This file deliberately does not repeat it. A rule copied here would be a second source of truth, and
[second sources of truth drift](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec).
Open the wiki page.

## Start here

| | |
| --- | --- |
| Before writing any code | [Contributing § Before you write code: read the constraints](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints) |
| Tests, commits, branches, releases | [Engineering Standards](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards) |
| How a change is traced to the SPEC | [Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow) |
| What to work on | The [Talos Board](https://github.com/users/CalixtoTheBugHunter/projects/5) |
| Decisions already made | [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) |
| Reporting a security issue | [`SECURITY.md`](SECURITY.md) and [Contributing § Reporting security issues](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#reporting-security-issues) — not a public issue |

## Signing your commits

`main` requires
[signed commits and signed tags](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main),
and that page states why. Setup is below because the requirement is a wall without it; the rule and
the reasoning stay on the wiki.

SSH signing is the shortest path on macOS — no extra software, and it reuses the key you already push
with. GPG works too and needs `brew install gnupg` first.

**Set it up per-clone, not globally**, with `git config` inside your checkout. A global signing key
signs your commits in every other repository too, under this identity — wrong if you use more than
one GitHub account on the machine:

```bash
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519.pub   # your key, the .pub
git config commit.gpgsign true
git config tag.gpgsign true                        # releases use signed tags
```

Then add the **same** key to GitHub a second time, at
[Settings → SSH and GPG keys](https://github.com/settings/keys), with key type **Signing Key**. A key
registered only as an Authentication Key does not verify signatures — the commit is signed, GitHub
still calls it Unverified, and nothing in the local setup looks wrong. That is the usual cause of a
rejected push that appears correctly configured.

### Verify it works

```bash
git commit --allow-empty -m "chore: signing check"
git log --format='%G? %GS' -1        # want: G <your signing identity>
```

`G` means good signature. If you get `N` (none) on a commit you just signed, check
`git cat-file -p HEAD | grep gpgsig` — when the header is present, the commit **is** signed and only
local verification is failing, because `git` needs to be told which keys to trust:

```bash
echo "$(git config user.email) $(cat ~/.ssh/id_ed25519.pub)" >> ~/.ssh/allowed_signers
git config gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
git verify-commit HEAD               # exits 0, names your key
```

This file is only for verifying locally; signing and GitHub's Verified badge do not depend on it.

Whether GitHub accepts a commit is the authoritative answer, and it is one command:

```bash
gh api repos/CalixtoTheBugHunter/talos/commits/<sha> --jq '.commit.verification'
```

`"verified": true` is what the ruleset enforces. A squash merge is signed by GitHub's own key, so a
merged PR reports `verified` even when the branch commit behind it was not — do not read a green
`main` as proof your local setup works. Test it on your own commit, before you need it.

## Linting and formatting

[SwiftLint and SwiftFormat](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain)
are the SPEC's tools, configured at the repo root in
[`.swiftlint.yml`](.swiftlint.yml) and [`.swiftformat`](.swiftformat). That page states what each one
enforces and why; setup is below.

```bash
brew install swiftlint swiftformat
```

```bash
swiftformat .          # autofix
swiftlint lint         # warnings are errors, from strict: true in .swiftlint.yml
```

### The pre-commit hook

Installing it is **optional and one command**, run inside your clone:

```bash
git config core.hooksPath .githooks
```

[`.githooks/pre-commit`](.githooks/pre-commit) then runs `swiftformat` and `swiftlint` over the Swift
files you staged. It formats a wholly-staged file and re-stages it; a file staged in part — `git add
-p`, or edited after staging — is linted and named instead, because formatting it would stage an edit
you have not read.

It also runs [`design-guard`](tools/design-guard/README.md), which is the half of the no-values rule
SwiftLint cannot see. That one scans the repository's tracked files rather than your staged set —
the same surface `lint` scans, so the two give the same answer — and it runs even when you staged no
Swift at all, because a bundled color asset is not a Swift file.

Set it **per-clone, not globally**, for the same reason signing is: `core.hooksPath` in your global
config points every other repository at a `.githooks` directory that does not exist there.

Uninstall with `git config --unset core.hooksPath`. The hook is a convenience, not the gate — `lint`
is a [required check](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order),
and it runs whether or not you installed this.

### The pre-push hook

Same `core.hooksPath .githooks` install as above covers this one too — no second command.

[`.githooks/pre-push`](.githooks/pre-push) runs the `lint` stage's repo-wide, PR-context-free checks
over your whole tracked tree before a push leaves your machine: `swiftformat --lint`, `swiftlint
lint`, [`design-guard`](tools/design-guard/README.md), and
[`comment-guard`](tools/comment-guard/README.md). The pre-commit hook above only lints your *staged*
files and never runs `comment-guard` at all, so a `comment-guard` violation — an issue/PR reference or
a `TODO` in a comment, an oversized DocC abstract, a `//` block beside a `///` one — or a violation in
a tracked file you didn't stage this time previously reached `main`'s required `lint` check
undetected locally.

It does not cover every `lint`-job step:

- `codeowners-guard`, `pr-title-guard`, and `dependency-justification-guard` each need a live GitHub
  API call or a PR's title/body/base-head range that does not exist yet at push time.
- `secret-scan`'s push-range scan is PR-scoped the same way — it diffs a PR's base and head SHAs.
- `workflow-hardening-guard` needs neither: it's a static scan of `.github/workflows/` with no PR
  context, the same shape as `design-guard`. It's simply out of scope for this hook for now, not
  excluded for a technical reason like the other four.

CI stays the required check for all five either way — this hook is a convenience, not the gate, same
as `.githooks/pre-commit` above.

## Contributing with an AI agent

The repo ships **Claude Skills** in [`.claude/skills/`](.claude/skills/README.md) that encode the
constraints, so an agent contributing to Talos already knows them.
[**`.claude/skills/README.md`**](.claude/skills/README.md) indexes what is in the repo and which
skill applies when; the authoritative skill-to-constraint mapping is
[Contributing § If you contribute with an AI agent: use the skills](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).

Start from [`spec-driven-change`](.claude/skills/spec-driven-change/SKILL.md) — it is the default
entry point for any change.

## License

Talos is licensed under **Apache-2.0** — see [LICENSE](LICENSE). By contributing, you agree your
contribution is licensed under Apache-2.0. The reasoning is on
[Contributing § License](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#license).
