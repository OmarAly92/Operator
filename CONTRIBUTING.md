# Contributing

We love contributions — code, docs, triage, examples, and tests.
Open an issue first so scope is clear before you invest time.

- **[Issues](https://github.com/OmarAly92/operator/issues)** → bugs, proposals, design threads
- **[Discussions](https://github.com/OmarAly92/operator/discussions)** → questions and ideas

Non-trivial work? Comment on the issue first. Get a thumbs-up, then build.

## Ways to contribute

| Type             | Examples                                       |
| ---------------- | ---------------------------------------------- |
| Code             | Fixes, features, adapters, performance         |
| Docs             | README, `docs/`, architecture notes            |
| Triage           | Repro bugs, tighten reports, label suggestions |
| Examples / tests | Recipes, edge cases, flaky-test hunts          |

## Quick start

1. **Open or find an issue** — say what you plan to do and get guidance
2. **Read the contract** — [AGENTS.md](AGENTS.md) (layout, commands, hard rules, PR hygiene)
3. **Pick something focused** — [open issues](https://github.com/OmarAly92/operator/issues); prefer `good-first-issue` / `help wanted`
4. **Claim it** — comment `I'd like to work on this` and wait for assignment
5. **Open a clear PR** — narrow change, link the issue, user-visible impact, tests
6. **Iterate** — address review; maintainers merge

Need the product/run overview first? Start with [README.md](README.md),
[docs/architecture.md](docs/architecture.md), and
[docs/development.md](docs/development.md).

Two onboarding notes matter on current `master`:

- On fresh Linux setups, prefer `cd frontend && npm run package` unless you have also installed distro packaging tools such as `rpm`/`rpmbuild` for `npm run make`.
- Mobile companion app docs are still being filled in. Do not assume `packages/mobile_rn/README.md` is a complete headless setup guide on this branch.

### Bugs and features

Use the GitHub issue forms (**Bug report** / **Feature request**) so reports stay reproducible.
Bug reports should include Operator version, environment, repro steps, and expected vs actual behavior.

### Pull requests

New PRs are prefilled from [`.github/pull_request_template.md`](.github/pull_request_template.md).
Also follow **PR hygiene** in [AGENTS.md](AGENTS.md): branch from `master`, one issue per PR, conventional commits, explain intentional omissions, and keep CI green for the area you touched.

## Code of Conduct

Be respectful, constructive, and assume good intent. Report problems to the maintainers by opening an issue.

Thanks for making Operator better for the next person who shows up.
