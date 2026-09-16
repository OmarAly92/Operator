# De-fork: remove every Electron-era and upstream remnant

**Date:** 2026-09-16
**Decision owner:** Omar Aly
**Status:** implemented 2026-09-16 (see reports/2026-09-16-defork-report.md)

## Why

Operator was cloned from Untrivial's `agent-orchestrator` (an Electron app) and
rebranded on 2026-08-11; the shell was ported to Tauri on 2026-08-20..24. The
user's standing rule, stated 2026-09-16 while cutting the first real release
(`desktop-v0.13.0`): **Operator is its own product; nothing inherited from the
fork may remain in the code, the release path, or the living docs.**

The first release run exposed why this matters: the workflow still generated
Electron `latest*.yml` feeds "for the installed fleet" (there is none), the
hourly guard *requires* those files, and the notarize step assumed upstream's
Apple credentials. Inherited plumbing silently shapes what users download.

## Decisions already made (2026-09-16, in conversation)

| Decision | Choice |
|---|---|
| Nightly update channel | **Remove entirely.** Nothing publishes `nightly.json`; the only `EscalationFeeds` impl is the always-false stub (`frontend/src-tauri/src/updater/mod.rs:1098`). Stable + feature (`pr<N>`) builds stay. |
| Historical specs/plans/benchmark docs that exist only to compare against Electron | **Delete.** |
| Landing site `frontend/src/landing` (upstream marketing: blog, changelog 0.11.0, compare, design-partners, privacy, Sentry, Vercel) | **Delete entirely**, with `deploy-landing.yml` and every reference. |
| `LICENSE`, `NOTICE`, README fork attribution | **Keep.** Apache-2.0 §4 requires it. Out of scope. |
| Legacy import (upstream CLI layout → daemon, and Electron JSON prefs → `app_settings`) | **Remove** (see scope F). No users exist to migrate ([[operator-has-no-users-yet]]). |

## Scope — what is inherited, with evidence

Each item lists the files that implement it. "Living docs" means docs that
describe the current system; dated specs/plans are history and are deleted
only when listed.

### A. Electron-compatibility update feeds

The Tauri updater reads only `<channel>.json`
(`frontend/src-tauri/src/updater/channel.rs:138-141`). Everything that writes
or requires `*.yml` is for electron-updater:

- `frontend/scripts/feed.mjs` (+ `feed.test.mjs`) — generates `latest*.yml`,
  blockmaps. Header: "Generates electron-updater feed metadata".
- `frontend/scripts/blockmap.mjs` (+ test) — `app-builder-lib` blockmap
  sidecars; only consumer is `feed.mjs`.
- `frontend/package.json:72` — `"app-builder-lib": "^26.15.3"` devDependency.
- `frontend/scripts/tauri-feed.mjs:18,301-302,322-330,377,385-399` — imports
  `generateFeeds as generateCompatYaml`, `expectedFeedFilenames` returns the
  four-name family, `requireMacDittoZips` justifies itself with
  `latest-mac.yml`. Tests: `tauri-feed.test.mjs:288-300,316-338,348-352`.
- `.github/workflows/frontend-release.yml` `publish-feed` job (`assets=(dist/latest.json dist/latest*.yml)`), header lines 4 and 441-444.
- `.github/workflows/release-latest-guard.yml:53-55` — requires
  `latest.yml`, `latest-mac.yml`, `latest-linux.yml`.
- `.github/workflows/feature-release.yml:5-6,17,498,564,585` — `pr<N>*.yml`.
- `.github/workflows/mac-update-e2e.yml:21,113` and
  `frontend/scripts/e2e-mac-update.mjs:275` — comments.
- `frontend/scripts/verify-tauri-artifacts.sh:545,576` — failure messages cite
  `latest-mac.yml` (the zip requirement itself stays: `opr start` and the
  updater archive need it).
- `AGENTS.md:80` — "The zip and `latest-mac.yml` must keep publishing forever:
  electron-updater cannot install an update from a dmg."
- `frontend/docs/desktop-release.md:6-7,42-47,169,197,249`.
- `.github/actions/macos-signing-setup/action.yml:4,27-28,34` — comments
  describe electron-forge / `@electron/osx-sign` / `@electron/notarize`.

### B. Nightly channel

Shell (Rust): `frontend/src-tauri/src/updater/channel.rs:14,22,36,45,58,74-80,96,140`,
`updater/mod.rs:701-703,776-798,1023,1037-1039,1098-1105`,
`updater/escalation.rs` (whole `EscalationFeeds` trait, `important`,
`latest_stable_version`; keep only the 48-hour latest rule),
`updater/mod.rs:804-816` `is_manifest_404` (matches `.yml`), `tray.rs:97,464-470`
(`-nightly.` gate), `updater/tests.rs`.

Renderer: `frontend/src/shared/update-settings.ts:1,10`,
`src/renderer/components/settings/UpdatesSection.tsx:19,87,102,111,157,187-201`,
`UpdateOptInPrompt.tsx:25-26`, `lib/tauri-bridge.ts:23,279,291`,
`lib/bridge.ts:106`, `lib/build-channel.ts` (+ test), `lib/telemetry.ts:100-129,562`,
`test/setup.ts:222`, `styles.css` (`.nightly-warning`), i18n keys
`settings.updates.channel.nightly`, `settings.updates.nightlyWarning`,
`settings.updates.returnToNightly`, `shell.nightly` in all eight
`src/renderer/i18n/*.json`, `src/api/schema.ts:2799-2802` (generated).

Daemon: `backend/internal/service/settings/preferences.go:37,48-49`,
`storage/sqlite/migrations/0088_desktop_settings.sql:14-16` (CHECK includes
`'nightly'`, `update_nightly_ack` column), `queries/app_settings.sql:14`,
`gen/*` (regenerate), `store/app_settings_store.go`, `daemon/settings_wiring.go:96`,
`httpd/apispec/openapi.yaml:7716-7727` (generated),
`adapters/telemetry/posthog.go:348,502-506`.

Scripts/CI: `frontend/scripts/nightly-version.mjs` (+ test),
`feature-release.yml:550-571` (guard against `nightly*`),
`feature-release-cleanup.yml:17,20,91,102`, `feature-version.test.mjs`,
`feature-channel-resolution.test.mjs`, `e2e-mac-update.mjs` (+ test),
`benchmark-result.test.mjs`.

Mobile: `packages/mobile` — check `grep -rni nightly packages/mobile/lib`; remove
any channel enum value found.

### C. Landing site

`frontend/src/landing/**` (Next.js app, own `package-lock.json`, `vercel.json`,
Sentry configs, `content/changelog/operator-0-11-0.mdx` = upstream's release
notes, `design-partners`, `compare`, `blog`, `privacy`).
References: `.github/workflows/deploy-landing.yml`, `frontend.yml:34,57-58`,
`react-doctor.yml:7,11,28,34`, `build-artifacts.yml:41` (comment),
`frontend/tsconfig.json:33`, `frontend/eslint.config.js:16`,
`frontend/scripts/no-electron.test.mjs` (landing entries).

### D. Tauri-port evidence harness (Electron vs Tauri decision gate)

`frontend/scripts/phase0-*.mjs` (+ tests, `phase0-release-trust.json`),
`benchmark-artifact.mjs`, `benchmark-shell.mjs`, `benchmark-terminal.mjs`,
`benchmark-result.mjs` (+ test), `check-parity-ledger.mjs` (+ test),
`heap-summary.mjs` (+ test), `route-bundle-report.mjs` (+ test),
`agent-browser-phase0.mjs` (+ test), `frontend/perf/**` (`parity-ledger.json`,
`scenarios.json`, `results/`, `browser/`, `terminal/`),
`package.json` scripts `bench:artifact`, `bench:shell`, `bench:terminal`,
`check:desktop-parity`, `docs/benchmarks/tauri-port-baseline.md`,
`docs/development.md:44,240,250-269`, `AGENTS.md:42`,
`.github/workflows/tauri-webdriver.yml:38` (path filter),
`docs/todo/tauri-port-bugs-and-deferred.md`,
`docs/todo/tauri-port-release-and-follow-ups.md`.

`audit-tauri-state.mjs` (+ test) stays — it audits that Tauri state never lands
outside `~/.operator`; only its `"electron"` fixture directory name
(`audit-tauri-state.test.mjs:122`) is renamed.

`no-electron.test.mjs` is deleted: its `deletedPaths` list is a memory of
upstream's file layout, and with the shell gone the guard has nothing to guard.

### E. Electron-era comments and names in code that stays

Backend: `adapters/projectscan/scan.go:3`, `cli/start.go:32-33,201,216,248-260,362,633`
(`windowsInstalledExe` = electron-builder `Programs\Operator` path and its
fallback in `resolveWindowsInstalledExe:254-260,402-404`; tests
`start_test.go:206-250`), `httpd/controllers/dto.go:538`, `httpd/cors_test.go:92`,
`httpd/log.go:20`, `httpd/router.go:47,93`, `runfile/runfile.go:1`,
`session_manager/manager.go:148,384`, `cli/browser_test.go:30` (transport string
`electron-webcontents-debugger`).

Frontend: `e2e/smoke-datadir.spec.ts:11`, `.gitignore:1,66-69`
(`dist-electron/`, electron-builder debug dump).

Skills/docs: `.agents/skills/opr-desktop-dev/SKILL.md` (whole file describes
Electron Forge; `CLAUDE.md:26` marks it stale), `.agents/skills/bug-triage/SKILL.md:13-14`,
`CLAUDE.md:24-27`, `docs/STATUS.md:6,96,188-189`, `docs/architecture.md:1069`,
`docs/daemon-environment.md:4,7,12,27,38,83,153`, `docs/development.md:266`,
`docs/stack.md`, `docs/opr-start-bootstrapper-and-npm-deprecation.md`,
`docs/todo/browser-panel-webview.md`, `docs/plans/chinese-ui-i18n.md`.

Dated docs to delete outright (exist only for the port):
`docs/superpowers/specs/2026-08-16-tauri-port-design.md`,
`docs/superpowers/plans/2026-08-20-tauri-port.md`,
`docs/superpowers/specs/2026-08-26-tauri-ci-confinement-parity-design.md`,
`docs/benchmarks/tauri-port-baseline.md`, `docs/plans/2026-06-26-import-offer.md`.
Other dated docs that merely mention Electron in passing stay.

### F. Legacy import

Two layers, both migrating from upstream's older layouts:

1. **Project import from the pre-daemon CLI** (`~/.operator/config.yaml`,
   `portfolio/preferences.json`): `backend/internal/legacyimport/*`,
   `service/importer/importer.go`, `cli/import.go` (+ test, the `opr import`
   command), `httpd/controllers/imports.go` (+ test; `GET/POST /api/v1/import`),
   `dto.go` `ImportStatusResponse`/`ImportRunResponse`, `apispec/specgen/build.go`
   entries, renderer `hooks/useMigrationOffer.ts`, `components/MigrationPopup.tsx`
   (+ test), `components/MigrationSection.tsx`, `shared/app-state.ts`
   `MigrationState`/`MigrationStatus`, `shared/operator-bridge.ts`
   `appState.getMigration/setMigration`, `lib/bridge.ts`, `lib/tauri-bridge.ts:266-268`
   (+ tests), `test/setup.ts`, i18n keys under `migration.*`.
2. **Electron JSON preference import** into `app_settings`:
   `service/settings/legacy_import.go` (+ test), `service.go:48`
   `ApplyLegacyDesktopImport`, `daemon/daemon.go:216-223`,
   `daemon/settings_wiring.go:88-120`, `store/app_settings_store.go:29-69,120-190`,
   `preferences.go:192-220` (`MigrationStatus`, `MigrationReport`),
   `httpd/controllers/settings.go:40,109` (`PATCH /settings/migration`),
   columns `migration_json`, `legacy_desktop_imported_at` and query
   `ClaimAppLegacyDesktopImport` / `MarkAppLegacyDesktopImported` /
   `SetAppMigrationState` in `queries/app_settings.sql`.

`adapters/projectscan` (the import-folder scan used by "add project") is a
current feature and stays; only its comment at `scan.go:3` changes.

### G. Upstream "ao" (agent-orchestrator) identifiers

- `backend/internal/storage/sqlite/migrations/0085_agent_switching.sql:65` —
  column `agent_native_sessions.ao_session_id` (7 uses in
  `queries/agent_switching.sql`, 4 trigger references in `0109_claude_accounts.sql`,
  `store/agent_switching_store.go` field `AoSessionID`). Rename to `session_id`
  via `ALTER TABLE ... RENAME COLUMN` (SQLite rewrites triggers) + `npm run sqlc`.
- `backend/internal/httpd/auth.go:133` — cookie `ao_conn` → `opr_conn`.
- `backend/internal/adapters/telemetry/posthog.go:217,346` and
  `frontend/src/renderer/lib/telemetry.ts:145` — `ao_version` property
  (duplicate of `app_version`); drop it.
- `backend/internal/adapters/reviewer/pi/pi.go:125` and
  `assets/opr-pi-reviewer.ts:93,108,184` (+ `pi_test.go`) — tool names
  `ao_read`, `ao_search`, `ao_review_submit` → `opr_read`, `opr_search`,
  `opr_review_submit`.
- `backend/sqlc.yaml:183` — column override for `agent_native_sessions.ao_session_id`.
- `scripts/daemon-build.sh:17,55,115` — function `resolve_ao` → `resolve_opr`.
- `backend/internal/adapters/agent/kimi/trust_test.go:97-102` — fixtures use
  upstream's developer home `/Users/nikhilachale/.ao/dev/data/worktrees/agent-orchestrator/...`;
  replace with `/Users/dev/.operator/dev/data/worktrees/operator/operator-346` and
  recompute the expected `wd_...` ids from the test's own hashing helper.
- `backend/internal/adapters/workspace/gitworktree/workspace_integration_test.go:434,540,556`
  — git `user.name` fixture "Ao Agents" → "Operator Agents".
- `docs/telemetry.md:52,243`, `docs/posthog-cost-controls.md`,
  `backend/internal/adapters/telemetry/posthog_test.go`,
  `frontend/src/renderer/lib/telemetry.test.ts` — `ao_version` mentions.
- Portuguese "ao" in `translations/README.pt-BR.md` and `i18n/pt-BR.json` is the
  preposition, not the product; leave it.
- `DESIGN.md` / `CLAUDE.md` references to `~/Projects/agent-orchestrator` point at
  the user's *other* app (the design reference), not upstream; leave them.

The user's rule (2026-09-16): "remove any ao or agent orchestrator — this was
the old name, now its name is Operator."

### Shape decisions

- **`UpdateSettings` loses `channel` and `nightlyAck`** in Go, Rust, TS, the
  OpenAPI spec and the DB (`update_channel`, `update_nightly_ack` columns
  dropped). The remaining shape is `{ enabled: bool, feature: FeaturePin | null }`.
  The Rust `Channel` enum is deleted; `ActiveChannel { Latest, Feature(i64) }`
  stays. The Updates settings tab loses its "Updates channel" row; the feature
  pin row with "Return to Stable" stays.
- **Escalation** keeps only the 48-hour rule for a staged stable update:
  `evaluate_escalation(staged_at_ms, now_ms) -> bool`. The `EscalationFeeds`
  trait, `StoppedEscalationFeeds`, `important`, `latest_stable_version` and
  `is_manifest_404` are deleted.
- **Tray:** `is_tray_enabled` (`tray.rs:97`) currently enables the macOS tray only
  for unpackaged or `-nightly.` builds. With nightly gone the packaged stable app
  would never show the tray the user just designed (commit `e0ade15c7`). New rule:
  `platform == MenuPlatform::Macos` — always on macOS.
- **Telemetry:** `ReleaseChannel` becomes `"stable" | "feature" | "unknown"`;
  `VersionChannel`/`version_channel` is deleted on both sides (a version string
  can no longer say anything a channel does not).

## Non-goals

- Rewriting attribution files (`LICENSE`, `NOTICE`, README §"Acknowledgements").
- Touching `packages/terminal` or `DESIGN.md` (the design reference is the
  user's *other* app, not upstream).
- Renaming `dev.operator.desktop`, `OmarAly92/operator`, or any Operator name.
- Adding a nightly train, Apple signing, or new release features.

## Constraints

- One change per removal, nothing dangling
  ([[breaking-changes-buy-cleanliness]]): a flag, column, route, i18n key,
  script, or doc line that no longer has an implementation must not remain.
- Database: add a new goose migration (`0111_drop_fork_settings.sql`) that
  drops `update_nightly_ack`, `migration_json`, `legacy_desktop_imported_at`
  and recreates the `update_channel` CHECK as `IN ('latest')`. SQLite cannot
  alter a CHECK in place; rebuild the column via the table-copy pattern used by
  earlier migrations in `backend/internal/storage/sqlite/migrations/`.
- Generated files are regenerated, never hand-edited: `npm run sqlc`,
  `npm run api` (spec + `schema.ts`). CI fails on drift.
- No new comments in code ([user instruction]); removed comments are not
  replaced by other comments.
- Gates for every task: `cd backend && go build ./... && go test ./...`,
  `cd frontend && npm run typecheck && npm test`, `cd frontend/src-tauri && cargo test`,
  `python3 -c "import yaml,glob;[yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"`.
- Final gate: `grep -rniE "electron|forge|nightly|latest-mac|latest\.yml|blockmap|phase0|parity-ledger|legacyimport|src/landing" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=target --exclude-dir=.worktrees --exclude-dir=.claude .`
  returns only `LICENSE` ("electronic"), `NOTICE`, `README.md` attribution,
  dated docs not listed for deletion, and `packages/terminal` (which has its own
  history and is out of scope).

## Release consequences

After this lands, a stable release publishes exactly: the platform installers,
the `.app.tar.gz`/`.exe`/`.AppImage` updater archives with `.sig` sidecars,
the version-free `opr start` aliases, and `latest.json`. The guard workflow
requires exactly that set. `desktop-v0.13.0` (already tagged before this spec)
is the last release carrying `*.yml`; the next is `0.14.0`.
