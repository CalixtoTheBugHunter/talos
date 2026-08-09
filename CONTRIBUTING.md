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
| Reporting a security issue | [Contributing § Reporting security issues](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#reporting-security-issues) — not a public issue |

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
