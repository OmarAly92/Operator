# Parity contract and documentation truth fix report

## Status

Implemented the Tasks 1–4 review fix wave's parity-contract and documentation track, base `44b86e366`.

## What I implemented

### 1. Symmetric deferred-Browser parity validation (RED then GREEN)

The parity ledger validator already rejected an entry carrying a deferred exception when the key was
not a known deferred Browser entry. The symmetric direction was missing: a *known* deferred Browser
entry could appear in the ledger encoded as a normal task row (exception `null`, `disposition:
"native"`, owner/task set) and the validator accepted it. Every key in the checker's
`deferredBrowserEntries` set must use the exact deferred Browser record: the exception must be the
record path, `disposition: "deferred"`, and `owner`/`task` both `null`.

`validateParityLedger` in `frontend/scripts/check-parity-ledger.mjs` now checks that direction for
every ledger entry whose `(source, member)` is a known deferred Browser entry, emitting
`deferred Browser entry must use the exact deferred record for …`, `deferred Browser entry
disposition must be deferred for …`, and `deferred Browser entry owner and task must be null for …`.

### 2. Browser-panel decision record reworded

`docs/todo/browser-panel-webview.md` was rewritten so it records the approved *future* Task 16
disposition rather than describing the replacement as already shipped. It now states explicitly that
the embedded Electron Browser panel still exists in the desktop app today, that automatic external
preview and daemon-owned standalone automation are not implemented yet, and that this page is a
decision record, not a change log. The deferred/removal decision for the Tauri base port is
preserved, and the "If we rebuild it" scope is unchanged.

### 3. SDD ledger statuses corrected

`.superpowers/sdd/2026-08-20-tauri-port/progress.md` now records: Task 1 complete; Tasks 2 and 3
implementation/review complete with native evidence pending; Task 4 implementation complete with
review/fix status and native matrix evidence pending. Missing Windows/Linux/minimum-macOS and
signed-release evidence is never described as complete.

### 4. Task 2–3 report overstatements corrected

- `task-2-report.md` (fix round 2): replaced the claim that "Native signing and installed Electron
  launch remain mocked only where a signed native release is unavailable on this host" with the
  final fixed behavior: no native path is mocked, the tests drive the real production
  signing/installed-launch/payload-binding code, and the production paths fail closed unless a
  signed native release with trusted publisher inputs is supplied.
- `task-3-report.md` (fix round 1): removed the unsupported claim that the `DefaultAllowedOrigins`
  comment rewrite was "authorized", and noted the comment has since been removed by this review fix
  wave. The same removal is recorded in that report's final self-review documentation check.

Historical RED/GREEN narratives were left intact.

### 5. Unauthorized `DefaultAllowedOrigins` comment removed

The doc comment on `DefaultAllowedOrigins` in `backend/internal/config/config.go` — the one
production source comment materially rewritten by Task 3 with no authorizing ruling — was removed.
No replacement comment was written. The three exact origins remain explicit in the source values
and are pinned by `config_test.go` (`want := []string{"app://renderer", "tauri://localhost",
"http://tauri.localhost"}`) and the `httpd/cors_test.go` origin allowlist cases.

## TDD evidence

### RED

Command (run before the validator existed):

```text
cd frontend
node --test scripts/check-parity-ledger.test.mjs
```

Observed `# tests 15 / # pass 12 / # fail 3`. The three new regressions failed as intended because
the symmetric validator was absent:

```text
requires a known deferred Browser entry to use the exact deferred record
requires a known deferred Browser entry to keep a deferred disposition
requires a known deferred Browser entry to keep null owner and task
```

A known deferred entry encoded with `exception: null` (`preload.browser/navigate` as a normal task
row) was previously accepted with zero errors; that is the RED regression the brief required.

### GREEN

After the validator was implemented, the same command passed:

```text
# tests 15
# pass 15
# fail 0
```

The live parity checker over the committed ledger continues to pass:

```text
node ./scripts/check-parity-ledger.mjs
Desktop parity ledger covers 108 entries.
```

## Verification

- `node --test scripts/check-parity-ledger.test.mjs` — 15/15 GREEN.
- `node ./scripts/check-parity-ledger.mjs` — live check passes, 108 entries.
- `git diff --check` — clean.
- `go build ./internal/config/...` and `go vet ./internal/config/...` — pass after comment removal.
- `go test ./internal/config ./internal/httpd -run 'AllowedOrigins|CORS' -count=1` — pass.
- Full `go test ./internal/config/... ./internal/httpd/... -count=1` — all packages pass.
- Docs claims verified against source: `frontend/src/main/browser-view-host.ts` still exists (panel
  still embedded); `AGENT_BROWSER_CDP` is still consumed by
  `frontend/src/main/agent-browser-runtime.ts` (bridge not yet independent); Task 15 and Task 16
  sections of `docs/superpowers/plans/2026-08-20-tauri-port.md` describe the two replacement paths
  as planned; the `docs/todo/browser-panel-webview.md` path referenced as the deferred exception
  record by the checker and the ledger is unchanged.

## Files changed

Committed:

- `frontend/scripts/check-parity-ledger.mjs`
- `frontend/scripts/check-parity-ledger.test.mjs`
- `docs/todo/browser-panel-webview.md`
- `backend/internal/config/config.go`
- `.superpowers/sdd/2026-08-20-tauri-port/fix-contract-docs-report.md`

SDD working documents (untracked, not committed — they are gitignored and no prior fix track
committed them):

- `.superpowers/sdd/2026-08-20-tauri-port/progress.md`
- `.superpowers/sdd/2026-08-20-tauri-port/task-2-report.md`
- `.superpowers/sdd/2026-08-20-tauri-port/task-3-report.md`

## Self-review

- Completeness: every brief item is addressed — RED regression with symmetric validator (1), doc
  reword (2), ledger statuses (3), report corrections (4), origin comment removal (5).
- Honesty: ledger statuses and report corrections reflect the evidence actually present; no missing
  native evidence is described as complete; the doc records nothing as shipped that has not shipped.
- Discipline: only owned paths touched; no source comments added; `frontend/src-tauri/gen/` and
  `frontend/src-tauri/target/` remain untracked and were not staged, modified, or deleted.

## Concerns

1. **revive `exported` lint.** The repo gates merges on `golangci-lint` (`.github/workflows/go.yml`)
   with `revive` rule `exported` enabled (`.golangci.yml`), which requires a doc comment on
   package-level exported variables. Removing the `DefaultAllowedOrigins` comment entirely will
   likely surface `exported var DefaultAllowedOrigins should have comment or be unexported` on the
   next CI ran. The brief instructed removal with no replacement comment, so I did not add one; the
   lint trade-off is the controller's call. The alternative would be a minimal (non-explanatory)
   doc comment, which the brief explicitly forbade.