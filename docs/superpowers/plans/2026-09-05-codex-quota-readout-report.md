# Codex Quota Readout — Implementation Report

Branch: `codex-quota-readout` (worktree `.worktrees/codex-quota-readout`, off `master` at `3128f83b7`).
Process: superpowers:subagent-driven-development — one fresh implementer subagent per task, a dedicated task reviewer per task, fix loops as needed.

## Task 1 — Migration for the account-wide quota row

Commits: `32188fa3e` (migration), `935719a47` (gofmt fix, see Ruling below).

- Created `backend/internal/storage/sqlite/migrations/0100_usage_quota.sql` exactly per spec.
- `go test ./internal/storage/sqlite/...`: **PASS**.
- Reviewer flagged (Important) that the commit also touched `migrate_burned_versions_test.go` (added the `100: "0100_usage_quota.sql"` ledger entry), which the brief's file list didn't mention.
  **Ruling:** not a defect. `migrate_burned_versions_test.go:127-158` enforces that every new migration file has a `shippedMigrations` entry added in the same change, or the test suite fails outright. The brief's file list was incomplete (a plan-authoring gap), not a requirement the implementer violated.
- **Separately discovered while reviewing Task 5's gate report:** the implementer's edit to `migrate_burned_versions_test.go` left the file gofmt-dirty (confirmed via `gofmt -l` against the pre-Task-1 commit vs. post-Task-1 commit — clean before, dirty after). Fixed in a standalone commit `935719a47` (`gofmt -w`, no semantic change, `go test` re-confirmed green).

Status: **complete**.

## Task 2 — Domain types and the staleness rule

Commit: `2b7cc86a4`.

- `domain.UsageQuotaWindow`, `domain.UsageQuota`, `IsStale`, `IsEmpty` added exactly per spec, including the "0% is not absent" test.
- TDD evidence: failing (`undefined: domain.UsageQuotaWindow`) → passing, both shown in `task-2-report.md`.
- Review: **clean, no findings.**

Status: **complete**.

## Task 3 — Parse `rate_limits` ahead of the `Info` guard (G3)

Commit: `844507f53`.

- This is the highest-risk task in the plan. The reviewer traced `parseCodexEvent`'s control flow line by line and confirmed `rate_limits` is read and assigned to `result.Quota` **before** the `payload.Info == nil` guard's `return` — the exact ordering G3 requires.
- All three required tests present and passing, including the info-null case and the newest-wins-not-highest case.
- The implementer additionally ran (then deleted, per instructions) a throwaway probe test against real `~/.codex/sessions/2026/*/*/*.jsonl` files on this machine: quota was found in ~50 real rollouts with `window_minutes` 300/10080, corroborating the fixture tests against genuine data.
- Review: **clean, no findings.**

Status: **complete**.

## Task 4 — Persist and read the quota

Commit: `d9918c358`.

- `SaveUsageQuota`/`GetUsageQuota` added following the neighboring locking convention; `sql.ErrNoRows` maps to `(zero, false, nil)`.
- `ApplyUsageChunkWithContext` gained the trailing `quota *domain.UsageQuota` param, written inside the same transaction as the rest of the chunk.
- The brief named `internal/service/usage/collector.go` as the wiring point; the implementer found (and the reviewer independently confirmed via `grep -rn "ApplyUsageChunkWithContext("`) that the real, sole call site is `internal/observe/usage/ingestor.go:289`. `collector.go` has no such call at all. Wired there instead — a plan-authoring inaccuracy, not a deviation.
- All three required tests present (newest wins even when lower, late-arriving old observation ignored, absence reported as `ok=false`).
- Review: **clean, no findings.**

Status: **complete**.

## Task 5 — Service and HTTP endpoint

Commit: `856299a57`.

- `SummaryReader.Quota(ctx)` added as a thin pass-through to `Store.GetUsageQuota`.
- `GET /api/v1/usage/quota` returns `200 {"quota": null}` when never observed, and the full windows-array shape otherwise, with `stale` computed server-side from `IsStale(now)` and nil windows omitted from the array.
- New named types registered in `specgen/build.go` per `AGENTS.md`'s documented convention.
- `openapi.yaml` and `frontend/src/api/schema.ts` regenerated via `npm run api` and committed with the Go changes.
- The implementer's gate report mischaracterized the Task-1-introduced gofmt failure as "pre-existing, unrelated" — independently verified false and corrected (see Task 1 above); Task 5's own files were independently spot-checked gofmt-clean and `go vet`-clean.
- Full backend gate after the correction: `gofmt -l internal/` empty, `go vet ./...` clean, `go test ./...` **PASS**, `golangci-lint run ./...` clean.
- Review: **approved**, 2 minor items deferred (not fixed, non-blocking): `time.Now()` used instead of `time.Now().UTC()` in the quota handler (likely correctness-neutral); no test locks the both-windows-present ordering explicitly.

Status: **complete**.

## Task 6 — Mobile model, endpoint and repository

Commit: `7fdb19096`.

- `UsageQuotaModel`/`UsageQuotaWindowModel` hand-written, all fields nullable, `Equatable`; `UsageQuotaWindowModel` has a genuine `const` constructor (verified, since Task 7 depends on it).
- `EndPoints.usageQuota` added as a parameterless static const.
- Repository's null-handling verified line-by-line to faithfully mirror the existing `sessionContext` pattern.
- `flutter test test/feature/usage/`: **14 passed**. `flutter analyze`: **No issues found!**
- Review: **approved**, 2 minor items deferred: `usedPercent` parsed as `int` (would truncate a fractional wire value, though the wire always sends whole numbers today); a minor `fromJson` style nit.

Status: **complete**.

## Task 7 — Quota section on the usage screen

Commits: `1a6afcc93` (initial), `6f87e0e45` (fix round 1).

- `QuotaReadout` (pure formatting) and `QuotaSection` (widget) implemented; `UsageState`/`UsageCubit` extended; a quota-fetch failure is caught locally and does not fail the screen.
- Reviewer verified every G5/G6 copy rule directly against the diff, file:line: heading text, window labels, "Claude Code: not reported" always present, stale window suppresses the percentage and bar entirely, 0% renders as "0%" not absent, null quota renders nothing.
- **Fix round 1:** reviewer flagged (Important), and the controller independently confirmed via grep, that `quota_section.dart` had a private `_relativeTime(DateTime? time)` helper duplicating the existing shared `core/utils/relative_time.dart` utility (already used by the notification and session_card features). Fixed by deleting the private helper and calling the shared `relativeTime()`, updating the "Unknown — last seen" copy/tests to the shared function's actual bare-token output (e.g. "10m", "2h"). Re-review: **all findings addressed, no new breakage**.
- Full mobile gate after the fix: `flutter analyze` → **No issues found!**; `flutter test` → **22/22 passed** in `test/feature/usage/` (full suite also reported green by the implementer: 1396 passed).
- 1 minor item deferred: per-window "last seen" is sourced from the shared `observedAt` on the model rather than a per-window timestamp (the wire model has no per-window timestamp today, so this is the correct implementation of the current contract).

Status: **complete**.

## Task 8 — Live verification

**Status: blocked pending user action — see below.** No code deliverable for this task; this section records what could and could not be verified.

Checking the running daemon on this machine before attempting Step 1:

```
$ curl -s -m 3 http://127.0.0.1:3002/api/v1/usage/quota
{"error":"not_found","code":"ROUTE_NOT_FOUND","message":"GET /api/v1/usage/quota has no handler", ...}
```

This confirms the currently-running daemon is not built from this branch (expected — the endpoint is new). However, `ps aux` shows this daemon is the user's live **dev** daemon with a large number of active, in-progress agent sessions attached to it right now (multiple `scratch-*`, `tbm-online-coaching-*`, and orchestrator sessions, each with a live `opr pty-host` / `opr agent-process supervise` process pair).

The plan's own Task 8 Step 1 warning is explicit: a daemon launched from an agent shell inherits `CLAUDE_*`/`ANTHROPIC_*` environment variables and every agent it spawns exits immediately, so it must be restarted **from the desktop app**, not from a shell — and restarting it at all will interrupt every session currently attached to it.

I did not restart the daemon. This is a side effect outside this branch's worktree, affecting the user's live sessions, and the plan itself flags it as something that must be done carefully and deliberately (from the desktop app) rather than by an agent. Steps 1–6 of Task 8 all depend on that restart and are left **unchecked** in the plan rather than marked done from fixtures, per the plan's own explicit instruction not to claim this step passed without doing it for real.

**What this means for confidence in the feature:** Tasks 1–7 are fully covered by unit/integration tests against fixtures and, for Task 3 specifically, against ~50 real Codex rollout files already on this machine (via the throwaway probe test, run and deleted per the brief). The one thing fixtures cannot prove — the exact "info: null" shape of a brand-new session's first events, live end-to-end through this branch's actual running daemon and onto the phone — is exactly what Task 8 exists to catch, and it has not been run.

**Recommended next step:** when convenient (i.e., when it's acceptable to interrupt the currently-running agent sessions on the dev daemon), restart the daemon from the desktop app on this branch, then run Task 8 Steps 2–7 as written in the plan. Step 5 (staleness rollover) may not be reachable in one sitting since it needs a real 5-hour window to roll over; the plan already anticipates this and allows verifying the staleness branch at the store level instead if so — that fallback has not been exercised either, since it wasn't attempted in favor of asking first.
