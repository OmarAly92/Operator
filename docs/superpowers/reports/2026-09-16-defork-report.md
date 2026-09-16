# De-fork report — 2026-09-16

Spec: `docs/superpowers/specs/2026-09-16-defork-design.md`. Branch `defork`,
11 commits above master `85761aaaf`. Version bumped 0.13.0 → 0.14.0.

## Commits (`git log --oneline master..HEAD`)

```
release: bump to 0.14.0 after the de-fork cleanup
c49cc2f0d chore: remove the last Electron-era names from code, skills and docs
34e62b327 chore: rename every inherited ao identifier to Operator
1125690f7 daemon+renderer: delete the legacy import and migration offer
e83bc25e0 chore: delete the Electron-vs-Tauri port evidence harness
133424d66 chore: delete the inherited landing site
8ef8472b6 ci: drop the nightly train from feature releases and scripts
ade0f446e renderer: remove the nightly update channel
4f5c65ebe daemon: drop the nightly channel and the Electron preference import
e79c2fc90 tauri: remove the nightly update channel
8946fbd43 release: publish only the Tauri latest.json feed
```

## Final sweep

Run from the repo root. Output was empty.

```bash
grep -rniE "electron|\bforge\b|nightly|latest-mac|latest\.yml|blockmap|phase0|parity-ledger|legacyimport|src/landing|\bao_[a-z]+|agent[ _-]?orchestrator" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target --exclude-dir=.worktrees --exclude-dir=.claude --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=out . | grep -vE "^(\./)?(LICENSE|NOTICE|README\.md|DESIGN\.md|CLAUDE\.md|docs/superpowers/|packages/terminal/|translations/README\.pt-BR\.md|frontend/src/renderer/i18n/pt-BR\.json|docs/design/.*standalone\.html|packages/mobile/docs/design/.*standalone\.html|packages/mobile/packages/xterm/script/lines\.txt|.*package-lock\.json)" | grep -vE "(migrations/|migrate_burned_versions_test\.go.*)(0085|0088|0109|0111|0112|0113)" | grep -vE "mobile-parity-ledger\.md"
```

```
(no output)
```

Differences from the command in the plan, each deliberate:

- `^\./` became `^(\./)?`: BSD grep prints `docs/...` rather than `./docs/...`,
  so the plan's exclusion list never matched anything.
- `forge` became `\bforge\b`: the bare term matched the English word
  "forget" ~40 times (Go method `Manager.forget`, mobile "Disconnect & forget
  server" copy, i18n "Operator forgets this account", `fire-and-forget`).
  Electron Forge is always a standalone word, so the boundary loses nothing.
- Added exclusions: `CLAUDE.md` (its "Name collision warning" and design-rule
  paragraphs name `agent-orchestrator` as the user's other app), any
  `package-lock.json` (`electron-to-chromium` is a transitive browserslist
  dependency), `docs/design/*standalone.html` and
  `packages/mobile/docs/design/*standalone.html` (user-authored design exports:
  a mock "Nightly" dropdown option and base64 `Ao…` substrings),
  `packages/mobile/packages/xterm/script/lines.txt` (vendored Flutter file
  listing containing `fortnightly`), `migrate_burned_versions_test.go` lines
  naming `0111_drop_nightly_and_legacy_prefs.sql` (the migration's own
  filename, same allowance as the `migrations/` paths), and
  `docs/mobile-parity-ledger.md` references (that ledger records the
  Expo → Flutter mobile port, not the Electron → Tauri parity ledger the term
  targeted; `CLAUDE.md` documents it as living).

## Touch points the sweep found and this task fixed

- `__ao*` test/e2e globals renamed to `__opr*` (Task 10's regex missed the
  `__ao` prefix): `__oprFakeAgent`, `__oprFakeTerminalMux`,
  `__oprXtermForTest`, `__oprScrollEvents`, `__oprRevealFrame(s)`,
  `__oprRevealSamples`, `__oprRevealObserver`, `__oprDomStability` across
  `frontend/e2e/**`, `frontend/src/renderer/hooks/useWorkspaceQuery.ts`,
  `backend/internal/adapters/agentbrowser/policy.go`. `grep -rnE "__ao[A-Z]"`
  with the standard exclusions is empty; the two remaining mentions are in
  dated `docs/superpowers/` plans/specs, which are history.
- "forged" → "spoofed" in `backend/internal/cli/browser_test.go` (fixture
  strings and a failure message) and `backend/internal/httpd/router.go` (the
  `mountMobile` comment now reads "a transport-based check that a spoofed Host
  header cannot defeat"); "forge" → "spoof" in
  `backend/internal/httpd/auth_test.go:283` and
  `packages/mobile/test/core/api/end_points_test.dart:13`. Prose only, no
  behaviour change.
- `frontend/vitest.config.ts:2`: the comment no longer attributes the
  per-target `vite.*.config.ts` files to Forge.
- `todo_without_tmux.md`: §11.2 (the instruction to run the deleted
  `npm --prefix frontend run bench:terminal` harness) deleted; the `phase0.json`
  reference in the §2 table now names the capability file's current name
  `main.json` (renamed in e83bc25e0).
- Forge-era build directories: nothing in `frontend/vite*.config.ts`,
  `frontend/package.json`, `frontend/src-tauri/tauri.conf.json` or
  `.github/workflows` produces `.vite`, `release` or `out` (the only `release/`
  is `src-tauri/target/release`, already ignored via `target`). Dropped
  `.vite`, `release`, `out` from `frontend/tsconfig.json` `exclude`, `out/**`
  from `frontend/eslint.config.js` ignores, and `out/` from `.gitignore`.
  `dist/` and `build/` stay: Vite emits `dist`, Flutter and Go emit `build`.

## Gates

All run from the worktree root on the final tree (before the version bump;
the bump changes only version strings).

```
cd backend && go build ./... && go vet ./... && go test ./...
```
Every package `ok` (or `[no test files]`); no `FAIL` line.

```
cd frontend && npm run typecheck && npm run lint && npm test && node --test scripts/*.test.mjs
```
- `typecheck`: exit 0.
- `lint`: `✖ 143 problems (0 errors, 143 warnings)`, exit 0.
- `npm test`: `Test Files  121 passed (121)`, `Tests  1425 passed (1425)`.
- `node --test scripts/*.test.mjs`: `# tests 69`, `# pass 66`, `# fail 3` —
  the three failures are `feature-version.test.mjs`, `go-version.test.mjs`,
  `verify-mac-artifact.test.mjs`, pre-existing vitest-style files that
  `npm test` already covers and passes; every other file is green.
- Also run: `npm run typecheck:e2e` and `npm run typecheck:e2e-tauri`, both
  exit 0 (the `__opr*` rename touched `frontend/e2e/**`, which the main
  `typecheck` does not include).

```
cd frontend/src-tauri && cargo test
```
`test result: ok. 213 passed; 0 failed; 0 ignored` (plus two empty doc-test
harnesses, `0 passed; 0 failed`).

```
cd packages/mobile && flutter analyze && flutter test
```
`No issues found! (ran in 5.9s)`; `01:07 +1220: All tests passed!`
(Flutter 3.44.5).

```
python3 -c "import yaml,glob;[yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"
```
Exit 0.

```
npm run api && npm run sqlc && git status --short backend/internal/httpd/apispec frontend/src/api backend/internal/storage/sqlite/gen
```
Both regenerate cleanly; the `git status` prints nothing.

## Version bump

```
cd frontend && npm version 0.14.0 --no-git-tag-version && sed -i '' '3s/^version = "0.13.0"/version = "0.14.0"/' src-tauri/Cargo.toml && (cd src-tauri && cargo metadata --offline -q --format-version 1 >/dev/null)
```
`git diff --stat` for that step: `frontend/package.json`,
`frontend/package-lock.json`, `frontend/src-tauri/Cargo.toml`,
`frontend/src-tauri/Cargo.lock` — 4 files, 5 insertions, 5 deletions.

## Database migrations added

The spec called for one (`0111_drop_fork_settings.sql`); three landed, because
the work split across tasks:

- `0111_drop_nightly_and_legacy_prefs.sql` (4f5c65ebe): rebuilds
  `app_settings` via the table-copy pattern, dropping `update_nightly_ack` and
  `legacy_desktop_imported_at` and recreating `update_channel` with
  `CHECK (update_channel IN ('latest'))`.
- `0112_drop_migration_json.sql` (1125690f7): `ALTER TABLE app_settings DROP
  COLUMN migration_json`.
- `0113_rename_ao_session_id.sql` (34e62b327): `ALTER TABLE
  agent_native_sessions RENAME COLUMN ao_session_id TO session_id`.

## Left out / deviations

- Allowed sweep hits, excluded by path as listed above: `LICENSE`
  ("electronic"), `NOTICE`, `README.md` attribution (Apache-2.0 §4),
  `DESIGN.md` and `CLAUDE.md` (the `agent-orchestrator` design reference is
  the user's other app), dated `docs/superpowers/` history, `packages/terminal`
  (own history, out of scope), the pt-BR translation files, the two
  user-authored `standalone.html` design exports, the vendored xterm
  `lines.txt`, `package-lock.json` (`electron-to-chromium`), the migration
  filenames, and `docs/mobile-parity-ledger.md`.
- The `terminal-benchmark` Tauri window and capability are kept: they are
  driven by `packages/terminal/bench`, which is product-independent and
  out of scope. `todo_without_tmux.md` §2 keeps its historical table of
  benchmark scenarios (it records fixes made 2026-09-02), minus the
  `phase0.json` name.
- The `window.operator` injected-bridge seam (`frontend/src/renderer/lib/bridge.ts`)
  is kept: it is the renderer's contract with the Tauri shell, not a fork
  remnant.
- `frontend/src/docs` (upstream's operator-docs app) was deleted together with
  the landing site in 133424d66.
- The Electron-driven release e2e pod gate was deleted with the release
  workflow rewrite (8946fbd43 / 8ef8472b6); the Tauri launch marker's
  `migration` block was deleted with the legacy import (1125690f7).
- Only the sweep's `forge` term changed (`\bforge\b`); every other term is as
  the plan wrote it.
- The `__ao*` mentions in `docs/superpowers/plans/2026-08-28-block-actions-find-selection.md`
  and `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
  are left: dated history, excluded by the sweep.
- During Task 10 a single `go test ./...` run printed one transient `FAIL`
  line that did not reproduce on reruns; this task's run was green
  first time.
- `node --test scripts/*.test.mjs` keeps its three pre-existing vitest-style
  failures (listed under Gates); converting or moving those files is outside
  the de-fork.
