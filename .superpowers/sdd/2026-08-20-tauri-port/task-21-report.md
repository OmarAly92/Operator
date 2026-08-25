# Task 21 Report: Delete Electron only after every replacement passes

Branch: `codex/tauri-port` (HEAD `1cd8a90ed`). All work left **uncommitted, nothing staged** per controller override. Working-tree deletions only.

## Step 1-2: Failing absence test written FIRST — RED evidence

Created `frontend/scripts/no-electron.test.mjs` (node --test suite, same convention as sibling `scripts/*.test.mjs`). 15 behavior-real assertions that stat/grep the actual tree: deleted paths absent, package.json dependency/script surface, source-import scans, broker-symbol scans, `app://renderer`, `VITE_NO_ELECTRON` sweep with dated-record exclusions, workflow stale-reference checks, tsconfig includes, three Tauri sidecar resources, and the run guide.

Command: `cd frontend && node --test scripts/no-electron.test.mjs`

Real RED output (before any deletion):

```
not ok 1 - every deleted electron surface is absent from the working tree
ok 3 - package.json keeps the tauri script surface that replaces electron
not ok 2 - package.json carries no electron runtime, updater, forge, or installer dependency
not ok 4 - package.json drops the electron lifecycle scripts and entry point
not ok 5 - dev:web selects the renamed renderer preview environment
not ok 6 - preview-mode reads the renamed renderer preview flag
not ok 7 - frontend sources import neither electron nor deleted main-process modules
not ok 8 - renderer and e2e fixtures expose no preload browser broker surface
not ok 9 - the go browser broker package stays deleted and unimported
not ok 10 - app://renderer disappears from every live surface
not ok 11 - VITE_NO_ELECTRON is renamed away from everything except dated planning records
not ok 12 - workflows reference no deleted electron artifact and the retired gate stays disabled
not ok 13 - tsconfig stops referencing deleted electron configs
ok 14 - the tauri bundle keeps all three sidecar resource entries
not ok 15 - the run guide instructs the tauri development path
# tests 15
# pass 2
# fail 13
```

(The two passing assertions — required Tauri scripts and the three sidecar resources — are positive invariants over already-shipped Task 7-20 surfaces.)

## Step 3a: Deletions

Plain `rm` / `rm -r` only; nothing staged; `git rm` never used. Per-file justification (replacement → proving gate):

| Deleted | Replaced by | Proof |
|---|---|---|
| `frontend/src/main.ts`, `frontend/src/preload.ts(+test)`, `frontend/src/main/**` (23 modules + 24 test files), `frontend/src/annotate-preload.ts(+test)` | Rust shell (`src-tauri/src/*`) + renderer `tauri-bridge.ts`; ledger rows carry owner/task/status per module | `npm run typecheck` clean; WDIO desktop e2e 12/12; parity check green |
| `frontend/src/shared/{browser-annotation-overlay,browser-annotations,browser-tabs,daemon-attach,daemon-discovery,daemon-launch,daemon-takeover,shell-env}{,.test}.ts` | Browser panel dropped by design (`docs/todo/browser-panel-webview.md`); daemon ownership/discovery moved to Rust supervisor + daemon | sole importers were the deleted main/preload files (grep-verified before deletion); typecheck + e2e green |
| `frontend/forge.config.ts`, `frontend/makers/**`, `frontend/vite.main.config.ts`, `frontend/vite.preload.config.ts` | Tauri bundler (`src-tauri/tauri.conf.json` targets app/dmg/nsis/deb/rpm/appimage) | `npm run tauri:build` exit 0 producing Operator.app + dmg |
| `backend/internal/browserruntime/**` (broker + unix/windows listeners + tests) | `agentbrowser.Adapter` standalone lifecycle, verified wired pre-deletion (below) | `go build ./...`, `go vet`, agentbrowser/session_manager suites green |
| Shared-module consumer audit before deletion: every importer of each deleted shared file was itself on the delete list (`src/main.ts`, `src/preload*.ts`, `src/annotate-preload*`, `src/main/browser-view-host.ts`). Zero surviving importers (grep cited in transcript). |

### Broker-deletion precondition verified in code (as required)

- `backend/internal/session_manager/manager.go:1434-1440`: session teardown calls `m.browser.DestroySession(...)` when set.
- `backend/internal/session_manager/manager_test.go` `TestKill_TearsDownRuntimeAndWorkspace` (~line 2118) and `TestRetireForReplacementCapturesAndReleasesWorkspace` (~line 5009) pin teardown via `fakeBrowserLifecycle`.
- `backend/internal/adapters/agentbrowser/runtime_test.go`: `TestDestroySessionClosesBrowserAndRemovesStateSafely`, `TestDestroySessionSurvivesCloseTimeout`, `TestDestroySessionDeduplicatesConcurrentTeardown`.
- `backend/internal/daemon/daemon.go` previously fanned out via `browserTeardown{broker, standalone}`; after deletion `standaloneBrowser` (`*agentbrowser.Adapter`, whose `DestroySession(ctx, domain.SessionID) error` satisfies `sessionmanager.BrowserLifecycle`) is wired directly into `startSession`. Behavior change is strictly an improvement: the standalone adapter's error is now surfaced to the manager's warning log instead of being swallowed in favor of the broker's.
- `browserruntime` had exactly one non-test consumer: `internal/daemon/daemon.go` (repo-wide grep).

## Step 3b: Package uninstalls — zero-consumer verification per package

Post-deletion greps over remaining first-party code (`frontend/src scripts e2e e2e-tauri *.ts *.json`, backend `.go`, `.github/workflows`) plus `git show HEAD:` citation of pre-deletion consumers:

| Package | Pre-task consumers (from HEAD) | Surviving consumers post-deletion | Action |
|---|---|---|---|
| `electron` | `src/main.ts`, `src/main/*` (deleted). `scripts/benchmark-terminal.mjs:262` embeds a driver string for its retired phase-0 `--shell electron` leg only | none in production code | uninstalled |
| `electron-updater` | `src/main/auto-updater.ts`, `src/main/feature-builds.ts` (deleted). `feed.mjs` only writes feeds *for* it (comment/format references); `feature-channel-resolution.test.mjs` re-implements its predicate with semver fixtures and does not import it | none | uninstalled |
| `@electron-forge/{cli,maker-base,maker-deb,maker-rpm,maker-zip,plugin-vite,publisher-github}` (+transitive `shared-types`) | `forge.config.ts`, `vite.main/preload.config.ts`, makers (all deleted); manifest scripts `dev/package/make/publish` | none outside the manifest entries being removed | uninstalled |
| `electron-installer-{debian,redhat}` | `frontend/makers/maker-dmg.ts` only (`git grep` at HEAD) | none | uninstalled |
| `app-builder-lib` | `scripts/blockmap.mjs` ← `scripts/feed.mjs` — **both outside the brief's delete list** | SURVIVING consumer → **kept** (see dead-candidates note) | NOT uninstalled |

Uninstall commands (non-interactive): `npm uninstall electron electron-updater`, then forge batch, then per-package retries, then `--force` retries for the last two (see Concerns for the npm arborist saga). Result: all 11 removed from manifest.

Lockfile provenance audit (contract: lock changes only from uninstall ops):

```
git show HEAD:...package-lock.json vs working tree:
ADDED packages: 0
REMOVED packages: 394   (electron / @electron-forge / electron-updater /
                         electron-installer-* subtrees and transitives)
```

One deviation to disclose: two packages (`@electron-forge/cli`, `@electron-forge/publisher-github`) hit a hard npm-arborist failure loop (`ERR_INVALID_ARG_TYPE` in `rollbackMoveBackRetiredUnchanged` / repeated `ENOTEMPTY` renames against stale Aug-21 retirement dirs found under node_modules). After clearing 40 stale dot-staging dirs and retrying (including `--force`), cli was removed by `npm uninstall --force`; publisher-github likewise. A single reconciling `npm install --no-audit --no-fund` was run twice mid-sequence to restore node_modules consistency (first run confirmed not to alter the lock beyond the already-performed uninstalls; final state shows 0 added keys). Remaining `electron-publish`/`electron-builder-squirrel-windows`/`electron-winstaller` lock keys are dependencies of the retained `app-builder-lib`, not of any uninstalled package. Manifest hand-edits were limited to scripts/description/allowScripts (non-lock fields); every dependency removal went through `npm uninstall`.

## Step 3c: VITE_NO_ELECTRON → VITE_RENDERER_PREVIEW rename (fixture behavior unchanged)

Functional changes (identical semantics, new name):

- `package.json`: `"dev:web": "VITE_RENDERER_PREVIEW=1 vite --config vite.renderer.config.ts"`
- `src/renderer/lib/preview-mode.ts`: `usesPreviewWorkspaceData = import.meta.env.VITE_RENDERER_PREVIEW === "1"` (same comparison, same exported const)
- Direct env reads renamed identically in `useMigrationOffer.ts`, `useShellTerminals.ts`, `useSessionScmSummary.ts` (`import.meta.env.VITE_NO_ELECTRON === "1"` → `VITE_RENDERER_PREVIEW === "1"`)
- `bridge.test.ts`: `vi.stubEnv("VITE_NO_ELECTRON", "1")` → `vi.stubEnv("VITE_RENDERER_PREVIEW", "1")` (same test body/assertion)

Comment-only updates: `playwright.config.ts` (command unchanged: `npm run dev:web`), `vite.renderer.config.ts` (proxy config unchanged), five e2e spec headers, `useWorkspaceQuery.ts`. No fixture data, mock shape, seam, or assertion changed. Proof of unchanged behavior: renderer Playwright gate `npm run test:e2e:renderer` → **21 passed**, and unit suite shows zero new failures versus a HEAD baseline worktree run (9 identical pre-existing failures both sides).

Also cleaned while in these files (honesty, not behavior): fake bridge's two dead `browser:` namespaces removed (no spec touches them; `OperatorBridge` has had no browser namespace since Task 16 — they didn't even typecheck at HEAD, see Concerns), unused `navState` helpers removed, missing-but-required `preview.openExternalPreview` stubs added to both fake bridges so `satisfies OperatorBridge` holds, `createElectronBridge` → `createWindowBridge` and the stub message de-Electronized in `lib/bridge.ts`, sanitizer pattern in `telemetry.ts` swapped `\bapp:\/\/renderer\/\S+` → `\btauri:\/\/\S+` plus `tauri.localhost` host (fixture URL in `telemetry.test.ts` updated accordingly), stale comments in `setup.ts`.

## Parity-checker evolution (kept protective, not weakened)

The old checker derived its inventory from three Electron-only sources (preload `const api`, renderer `../../main/` imports, production modules under `src/main/`). Post-deletion all three vanish, so it was evolved rather than deleted:

- **Live inventory**: parses `createTauriBridge`'s returned object literal in `src/renderer/lib/tauri-ledger…` (`src/renderer/lib/tauri-bridge.ts`) via TS AST → `{source: "bridge.<namespace>", member}` rows. Bidirectional validation continues: a new bridge member without a row errors `missing …`; a removed one errors `stale …`.
- **Renderer `../../main/` import scanner kept**: any re-introduced main-process import must be ledgered or fails `missing renderer/…`.
- **Archive class**: the 46 rows describing deleted Electron surfaces (`main/*` ×23, `preload.browser/*` ×23) are kept verbatim as the Task-20 disposition record (dispositions/statuses untouched). They are exempt from staleness because their referents are gone by design — and the checker enforces the inverse invariant: if `src/main/` ever reappears on disk while archived rows exist, validation fails ("archived electron main-process modules reappeared under src/main"). Deferred-browser rows still enforce exact record/disposition/null-owner rules; exception rows outside the pinned deferred set still error.
- **Unknown source classes rejected**: any row whose source neither starts with `bridge.`/`renderer/` nor is `main`/`preload.browser` errors, catching category drift.
- **Ledger changes** (102 entries now): 55 rows renamed `preload.X` → `bridge.X` (mechanical; dispositions/statuses byte-identical), plus one new live row `{"source":"bridge.preview","member":"openExternalPreview","disposition":"open validated previews in the user's default browser","owner":"tauri","task":16}` — the Task-16 surface the Electron-era ledger could not see. Diff vs HEAD: 63 insertions / 55 deletions.
- **Test suite rewritten behavior-real** (18 tests, all passing): fixtures now build a temp `tauri-bridge.ts` instead of `preload.ts`; every old guarantee has a counterpart (duplicates, missing members, deferred-record exactness ×3, exception pinning, regex-literal survival, single-quote/re-export scanning, owner/task validation) plus new ones (unledgered new member caught, archived reappearance caught, unknown source class caught, archived staleness exemption).

## Full GREEN gate outputs

| Gate (exact command) | Result |
|---|---|
| `node --test scripts/no-electron.test.mjs` | `# tests 15 # pass 15 # fail 0` |
| `node --test scripts/check-parity-ledger.test.mjs` | `# tests 18 # pass 18 # fail 0` |
| `npm run check:desktop-parity` | `Desktop parity ledger covers 102 entries.` |
| `npm run typecheck` | exit 0, no output |
| `npm run typecheck:e2e` | exit 0, no output |
| `npm run typecheck:e2e-tauri` | exit 0 (run during investigation) |
| `npm run test` (vitest; extra insurance, not in brief list) | 1690 passed, 9 failed — the exact same 9 fail on pristine HEAD (verified via throwaway worktree): 4× `shell-new-session-shortcut.test.tsx` ("No QueryClient set"), 5× `src/landing` markdown-twins (landing deps not installed locally). Files-failed count dropped 29→24 solely because ~30 deleted `src/main` suites no longer exist. `scripts/*.test.mjs` fail-to-bundle under vitest as a class at HEAD too (they are `node --test` suites). |
| `npm run test:e2e:renderer` | `21 passed (15.2s)` |
| `npm run test:e2e:tauri` (mac leg) | `12 passing (1m 8.7s)` — boots real renderer through embedded WebDriver, project+terminal mux+clipboard+dropped files+theme/menu/tray/notification seams, external preview seams, updater fail-closed surface, settings persistence, standalone-browser route wiring |
| `npm run tauri:build` | exit 0 — `Built application at .../target/release/operator`, bundled `Operator.app` + `Operator_0.10.3_aarch64.dmg` |
| `cd ../backend && go test ./...` | 136-138 pkgs ok; 2 load-flakes under full-suite parallelism: `kilocode TestAuthStatusUnknownWhenKeyOnlyComesFromInteractiveShell` and `opencode TestOpenCodeAuthStatusUnknownWithZeroCredentials` (3.00s deadline exceeded). Proven pre-existing: reproduced identically on a pristine HEAD worktree with `go test -count=1 ./...`; both pass in isolation, together, and in `-count=1 ./internal/adapters/agent/...` (35 pkgs). Untouched by this task (last modified at the rebrand fork commit). |

## Release-mandatory chain — DO NOT REMOVE (corrects an earlier draft of this list)

**`frontend/scripts/feed.mjs`, `frontend/scripts/blockmap.mjs`, and devDep `app-builder-lib` are transitively mandatory for every production release today. DO-NOT-REMOVE in Task 22.** An earlier draft of this report called them a "legacy electron-updater feed generator, uncalled by any workflow or script" — that was wrong. The live call chain:

- `.github/workflows/frontend-release.yml:450` and `.github/workflows/feature-release.yml:550` run `node scripts/tauri-feed.mjs …` on every release.
- `frontend/scripts/tauri-feed.mjs:18` imports `{ generateFeeds as generateCompatYaml } from "./feed.mjs"` and calls it at `:377` to produce the Electron-compatibility YAML feeds (`latest*.yml`) that both release workflows upload alongside the Tauri JSON feeds.
- `frontend/scripts/feed.mjs:13` imports `{ writeBlockmap } from "./blockmap.mjs"`, whose module-level `require("app-builder-lib/out/targets/blockmap/blockmap.js")` (`blockmap.mjs:10`) loads at import time even when the caller passes `{ blockmap: false }`.

So uninstalling `app-builder-lib` or deleting either script breaks production releases. This is why `app-builder-lib` stayed while all eleven Electron runtime/packaging packages were uninstalled.

## Dead-but-outside-the-delete-list (left in place; flagged for controller / Task 22)

1. `frontend/scripts/ensure-browser-runtime.mjs`: thin wrapper over prepare-agent-browser; lost its only caller when `predev` died. `browser-runtime:prepare` remains used (testing-build.yml, frontend.yml).
2. `frontend/scripts/feature-channel-resolution.test.mjs`: regression guard for electron-updater's channel predicate; moot without the dependency (does not import it).
3. `benchmark-terminal.mjs --shell electron` leg + `benchmark-shell.mjs --shell electron` leg + `phase0-legacy-{exercise,update}.mjs` + related aggregate/platform-summary expectations: the Electron-comparison half of the phase-0 decision machinery; unrunnable post-uninstall.
4. `.github/workflows/tauri-phase0.yml` — **modified, not deleted**: triggers removed with an explanatory header (invariant enforced by the absence test: `on:` must stay gone). Rationale: its `bundle-feasibility`/`legacy-update` jobs invoke `npm run package` (deleted script) and would hard-fail on the next push touching `frontend/package.json` (a trigger path), leaving guaranteed-red CI; fully porting/removing those legs would require rewriting the recorded decision gate (`phase0-platform-summary.mjs` hard-refuses without `legacy-update-evidence.json`), which is far outside this task's file list. The still-portable checks live on in `tauri-webdriver.yml` and `testing-build.yml`. Recommend structural retirement/archival in Task 22.
5. `frontend/src/shared/browser-view-types.ts`: imported only by deleted `browser-view-host.ts`; now fully unreferenced.
6. Root `CLAUDE.md` line ~38: the "opr preview renders in the desktop browser panel (Browser tab)" instruction has been wrong since Task 16 removed the panel (pre-existing staleness, not touched here).

Docs touched (minimal, forced by Step-1 stale-reference requirements): `RUN_APP_COMMANDS.md` (normal path now `npm run tauri:dev`; build section now `tauri:build`; renderer-preview section renamed), root `CLAUDE.md` (Electron-userData paragraph replaced with shell-neutral wording; the `~/.operator` hard rule intact), `docs/STATUS.md` (env-var token + Electron-main line), `docs/telemetry.md` (redaction list matches new sanitizer pattern), `docs/todo/browser-panel-webview.md` (record updated: Task 21 deleted the implementation), `AGENTS.md` (repo-layout line now Tauri + React desktop shell; hard-rule paragraph shell-neutral with the `data_directory` citation), `docs/README.md` (frontend descriptor), `docs/architecture.md` (Browser Runtime Bridge section rewritten as Standalone Browser Runtime — the broker socket, WebContentsView debugger, and panel-only network capture it described are deleted; network/devtools actions are pinned unavailable by `TestExecuteRejectsDesktopPanelOnlyActions`), `.github/workflows/testing-build.yml` (step running deleted `src/main/agent-browser-runtime.test.ts` removed; its native-binary compat coverage lives in Go contract tests and `verify-tauri-artifacts.sh`).

Dated planning records (`docs/superpowers/**`, `docs/plans/**`, `docs/todo/**` history, `.superpowers/**`) intentionally untouched; the absence test exempts them.

## Rejected alternatives

1. **Weaken/delete the parity checker** — rejected by brief and by me; evolved to the live bridge surface instead (above).
2. **Keep `preload.*` source names in the ledger** while parsing tauri-bridge.ts — dishonest keying; renamed to `bridge.*`. Chose in-place rename over restructuring the JSON (array shape, row order, field order preserved).
3. **Delete the 46 archived rows** once their surfaces vanished — rejected: Task-20 dispositions/statuses are the record; made them a validated archive class instead (staleness-exempt, reappearance-rejecting).
4. **Rewrite the phase-0 gate machinery** (make legacy evidence optional in platform-summary/aggregate/decision) to keep tauri-phase0.yml green — rejected: post-hoc weakening of a recorded kill-gate, 4 scripts + suites, way out of scope. Disabled the trigger instead and flagged.
5. **Delete tauri-phase0.yml outright** — file deletion outside the brief's list is forbidden by the controller contract.
6. **Hand-strip electron entries from package-lock.json** to dodge the npm bug — rejected; every dependency removal went through `npm uninstall` (with documented `--force` retries), keeping the diff semantically "uninstall-only".
7. **Absence test asserting "no 'electron' substring anywhere"** — impossible without touching out-of-list historical tooling (feed.mjs comments, benchmark drivers, phase0 evidence scripts, dated docs); scoped assertions to live surfaces + deleted-artifact references instead, with explicit dated-record exemptions.

## Self-review

- Contract compliance: everything uncommitted/staged-free (`git status` shows M/D + one untracked test file only; no index changes at any point). Deletions confined to the brief's list (79 tracked deletions = exactly the listed paths). No new dependencies. `frontend/src-tauri/gen/` and `target/` untouched.
- The absence test is the permanent guard and is behavior-real: filesystem stats, AST-backed manifest reads, recursive content sweeps with explicit exclusions (`.git`, `.claude`, `.superpowers`, `node_modules`, build outputs, vendored landing app, dated records). It self-excludes from its own sweep.
- Risk noted: `typecheck:e2e` needed `"node"` added to its `types` array (`tsconfig.e2e.json`) — removing electron evidently removed the incidental path that made NodeJS globals visible to that project (proven: HEAD sources + clean HEAD deps show only the unrelated fake-bridge browser errors; HEAD + current deps show the NodeJS breakage; my fix restores it explicitly, matching what `tsconfig.e2e-tauri.json` already did).
- Two latent pre-existing bugs surfaced and were fixed as a consequence of legitimate edits: fake-bridge's invalid `browser` namespaces (failed typecheck:e2e even at HEAD) and missing `preview` stubs (masked by the former error).
- Verification honesty: every claim above traces to a command output in this session; the two Go flaky tests and nine vitest failures are demonstrated pre-existing via HEAD-worktree runs, not assumed.

Status: DONE_WITH_CONCERNS (concerns = npm-arborist uninstall deviation disclosed above, disabled-not-retired tauri-phase0.yml, and the pre-existing red baseline items enumerated for Task 22).

## Fix report round 1

Review verdict addressed: SPEC COMPLIANT / QUALITY APPROVED; two Important findings fixed. All work remains uncommitted, nothing staged.

### T21-1 — dead-candidate handoff corrected (feed.mjs chain is release-mandatory)

The original item 1 claimed feed.mjs + blockmap.mjs + app-builder-lib were "uncalled by any workflow or script". FALSE, now corrected in the body (section "Release-mandatory chain — DO NOT REMOVE"). Verified citations before rewriting:

```
frontend/scripts/tauri-feed.mjs:18:  import { generateFeeds as generateCompatYaml } from "./feed.mjs";
frontend/scripts/tauri-feed.mjs:377: await generateCompatYaml(dir, rawVersion, channel, releaseDate, important, { blockmap: false });
frontend/scripts/feed.mjs:13:        import { writeBlockmap } from "./blockmap.mjs";
frontend/scripts/blockmap.mjs:10:    const { buildBlockMap } = require("app-builder-lib/out/targets/blockmap/blockmap.js");
.github/workflows/frontend-release.yml:450:  node scripts/tauri-feed.mjs dist "${TAG#v}" latest ...
.github/workflows/feature-release.yml:550:  node scripts/tauri-feed.mjs dist "$version" "$channel" ...
```

`blockmap.mjs`'s require is module-level, so it loads on import even with `{ blockmap: false }`. The report now marks the chain DO-NOT-REMOVE for Task 22; the keep decision itself was already correct and unchanged.

### T21-2 — stale Electron references in docs updated

- `AGENTS.md` repo-layout line: "`frontend/` — Electron + React supervisor…" → "Tauri + React desktop shell wired to the daemon via the generated typed client" (governance sentence preserved).
- `AGENTS.md` hard-rule bullet: Electron-userData sentences replaced shell-neutral — state root under `~/.operator` via `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE`, webview data named as part of that root, and the pin cited at its live location: "The Tauri shell pins its webview `data_directory` under the operator state root (`src-tauri/src/lib.rs`, `.data_directory(state_root.join("webview"))`)". Verified against source before writing (`lib.rs` main-window builder).
- `docs/README.md:4`: "Electron + TypeScript frontend" → "Tauri + TypeScript desktop frontend".
- `docs/architecture.md` ~979-998: the "Browser Runtime Bridge" section described the deleted broker socket (`browser.sock` / `opr-browser[-dev]`), the deleted Electron `WebContentsView` debugger capture, and panel-only request observation — all gone with this task. Rewritten as "Standalone Browser Runtime": Go daemon owns discovery/runtime/policy/execution over the packaged `agent-browser` binary with per-session isolated Chromium under the state root; policy blocks CDP/profile/executable/proxy escapes; `opr browser` CLI routes through the daemon for capability issuance; embedded panel removed (previews external; deferred record referenced). Panel-only actions documented factually as rejected with stable codes — verified against `runtime.go` `desktopOnlyActionCodes` and pinned by `internal/adapters/agentbrowser/runtime_test.go:428 TestExecuteRejectsDesktopPanelOnlyActions`. TOC entry updated to match.
- Left untouched on purpose: AGENTS.md:71's electron-updater dmg/zip rationale (release-history reasoning behind the compat YAML feeds that remain mandatory per T21-1) and dated planning records.

### Validation after fix round 1 (real outputs)

```
cd frontend && node --test scripts/no-electron.test.mjs
# tests 15
# pass 15
# fail 0

node --test scripts/check-parity-ledger.test.mjs
# tests 18
# pass 18
# fail 0

npm run check:desktop-parity
Desktop parity ledger covers 102 entries.

npm run typecheck   → exit 0
```

Files touched this round: `AGENTS.md`, `docs/README.md`, `docs/architecture.md`, `.superpowers/sdd/2026-08-20-tauri-port/task-21-report.md`. No source/config/deletion changes; index still empty.
