# GitHub repository configuration

GitHub stores rulesets and merge settings in its own database, not in this repository. **GitHub is the
live configuration; the files here are the reviewable export of it.** They exist so a change to what
protects `main` arrives as a diff somebody can read, rather than as a settings page nobody sees.

The rules these files implement are on the wiki and are not repeated here — a copy would be a second
source of truth, and
[second sources of truth drift](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

| | |
| --- | --- |
| What `main` requires | [Engineering Standards § Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main) |
| The required status check names | [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) |
| Why the owner is a bypass actor | [Decision 46](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) |
| Why an approval is dismissed on push | [Decision 48](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) |
| Why signing is required rather than optional | [Engineering Standards § Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main) |

| File | What it covers |
| --- | --- |
| [`ruleset-main.json`](ruleset-main.json) | The branch ruleset on the default branch |
| [`ruleset-tags.json`](ruleset-tags.json) | The tag ruleset, which is how "signed tags required" is enforced — a branch ruleset cannot reach tags |
| [`verify-rulesets.sh`](verify-rulesets.sh) | Asserts the live configuration still matches, criterion by criterion |

## Verifying

```sh
docs/github/verify-rulesets.sh
```

It reads the live configuration and exits non-zero on the first drift, naming the requirement that
drifted. Run it after any change to repository settings.

## Applying

Creating the rulesets, once:

```sh
gh api -X POST repos/CalixtoTheBugHunter/talos/rulesets --input docs/github/ruleset-main.json
gh api -X POST repos/CalixtoTheBugHunter/talos/rulesets --input docs/github/ruleset-tags.json
```

Updating one that already exists, by its id from `gh api repos/CalixtoTheBugHunter/talos/rulesets`:

```sh
gh api -X PUT repos/CalixtoTheBugHunter/talos/rulesets/<id> --input docs/github/ruleset-main.json
```

The merge methods are a repository setting rather than a ruleset rule, so they are applied separately:

```sh
gh api -X PATCH repos/CalixtoTheBugHunter/talos \
  -F allow_squash_merge=true -F allow_merge_commit=false \
  -F allow_rebase_merge=false -F delete_branch_on_merge=true
```

## Notes on two values that look wrong and are not

- **`actor_id: 5` is GitHub's built-in `admin` repository role**, which is how
  [decision 46](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) is
  expressed in a ruleset. Without it the ruleset would contradict the wiki line stating the owner is
  not bound by the list.
- **The six required checks do not exist yet.** They are built by
  [#23](https://github.com/CalixtoTheBugHunter/talos/issues/23),
  [#24](https://github.com/CalixtoTheBugHunter/talos/issues/24),
  [#26](https://github.com/CalixtoTheBugHunter/talos/issues/26), and
  [#108](https://github.com/CalixtoTheBugHunter/talos/issues/108). Until then a check that never
  reports leaves a PR pending, which is what
  [§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order)
  asks for — every stage is required — and is why the bypass above is currently load-bearing.

`require_code_owner_review` is `false` here because no `CODEOWNERS` file exists yet;
[#19](https://github.com/CalixtoTheBugHunter/talos/issues/19) adds the file and flips it in the same
change, since its own criteria require the ruleset to enforce owner review rather than merely advise
it.
