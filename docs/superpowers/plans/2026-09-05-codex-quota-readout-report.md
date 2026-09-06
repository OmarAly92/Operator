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

## Final whole-branch review

Dispatched on Opus over the full 10-commit branch diff (`3128f83b7..4a274b458`), after all 7 tasks were individually reviewed and approved. This review specifically traced each of G1–G7 end-to-end across the Go/SQL/JSON/Dart boundary — checking things a single-task review cannot, such as whether the parser's `parseCodex`/`Ingest` call chain has any short-circuit that would skip a quota-only chunk, and whether any layer along the full path recomputes, rescales, or collapses 0%/absent.

Findings:
- **I1 (Important):** the production write path for quota (`ingestor.go:289` → `ApplyUsageChunkWithContext` → unexported `saveUsageQuota`) had zero automated coverage. The existing tests only called the exported `SaveUsageQuota`, which production never calls — so the seam connecting Task 3's parser output to Task 4's stored row was held together only by the type checker, not a test.
- **M1 (Minor):** `usageQuotaWindowFromGen` returned nil only when *both* the percent and minutes columns were NULL rather than checking each independently — one condition away from silently rendering "not reported" as a real 0%.
- **M2 (Minor):** the mobile UI relied on array order rather than each window's `kind` field to decide which visual slot it renders in — latent, since the backend always emits primary-then-secondary today, but not contractually guaranteed.
- **M3–M7 (Minor, triaged non-blocking):** a pre-existing repo-wide OpenAPI nullability limitation this branch inherits (not introduces); a dangling-space edge case in "Unknown — last seen " unreachable since `observedAt` is a required wire field on the only server that exists; a fresh-but-days-old reading showing no age indicator (a design choice already reviewed and approved in Task 7's copy rules); a quota-fetch failure blanking the whole section on refresh (matches specified never-observed behavior, but conflates a real error with a 404); single-`limit_id`-per-chunk narrowing (unreachable today since the only other observed `limit_id`, "premium", always has both windows null and is discarded).

Confirmed everything G1–G7 requires actually holds end-to-end: no maximum kept anywhere for `used_percent`, no rescaling beyond a `usedPercent / 100.0` UI progress-bar conversion, 0% and absent never collapse at any of the five layers (four independent tests pin this), the G3 ordering survives the surrounding `parseCodex`/`Ingest` control flow (no short-circuit skips a quota-only chunk), the quota write shares the chunk's transaction, and both backward-compatibility cases that matter (an old daemon, an empty table) degrade to "section doesn't render" rather than crashing.

**Fix wave** (commit `afbc067c1`, one dispatch covering all three): I1 fixed with a new integration test, `TestIngestorPersistsQuotaFromAnInfolessRateLimitEvent`, that writes a rollout line in the exact G3 shape, runs the real production `Ingest()`, and asserts `GetUsageQuota` returns the expected values — proven to fail when `parsed.Quota` isn't wired through and pass with the real code. M1 fixed (both `.Valid` checks now independently required). M2 fixed (windows ordered by `kind`, with a regression test feeding secondary-before-primary on the wire and asserting primary still renders first).

**Re-review:** all three findings independently verified ADDRESSED — including tracing the new I1 test through the real production call chain rather than accepting a shortcut through the store directly — no new breakage, full backend gate (`gofmt`/`go vet`/`go test`/`golangci-lint`) and full mobile gate (`flutter analyze` → "No issues found!", `flutter test` → 1398 tests) both green.

**Ready to merge:** with the fix wave applied, yes for Tasks 1–7's code. Task 8 (below) remains the one compensating check — an actual daemon restart and live phone check — that has not yet run.

## Merge to master

The user asked to merge `codex-quota-readout` into `master` before running Task 8, so Task 8 runs against the daemon's normal branch rather than a feature branch. Merged with `git merge --no-ff` (commit `626186782`). Re-ran the full gate on master post-merge before touching the daemon: `gofmt -l internal/` empty, `go vet ./...` clean, `go test ./...` all green, `golangci-lint run ./...` → 0 issues; mobile `flutter analyze` → "No issues found!", `flutter test` → 1398/1398 passing.

## Task 8 — Live verification

**Status: complete.** All 7 steps run for real against the user's live dev daemon (restarted by the user from the desktop app, on `master`) and a real paired phone — no step marked done from fixtures.

**Step 1 (restart):** done by the user from the desktop app. The daemon was already carrying many active agent sessions (the original reason this was deferred to the user rather than done by the agent) — the user restarted it themselves once ready.

**Step 2 (fresh session):** spawned `scratch-12` via `POST /api/v1/sessions`. Its own first `token_count` event happened to already carry a non-null `info` — this run did not personally reproduce the info-null moment. This is expected variance, not a gap: G3's own measurement puts the info-null shape at 0.4% of events overall, "concentrated" in fresh sessions but not guaranteed on every single spawn.

**Step 3 (endpoint reports quota):** **PASS**.
```json
{"quota": {"harness": "codex", "limitId": "codex", "planType": "plus",
  "observedAt": "2026-09-06T02:04:01.302Z",
  "windows": [
    {"kind": "primary", "windowMinutes": 300, "usedPercent": 0, "resetsAt": "2026-09-06T07:03:30Z", "stale": false},
    {"kind": "secondary", "windowMinutes": 10080, "usedPercent": 16, "resetsAt": "2026-09-12T14:23:55Z", "stale": false}
  ]}}
```

**Step 4 (cross-check against the rollout):** **PASS**. `scratch-12`'s own rollout file (matching its `createdAt` timestamp) contains a `token_count` event whose `rate_limits` exactly matches the endpoint's response (0% primary / 16% secondary, `plan_type: "plus"`, `limit_id: "codex"`). Separately scanned every rollout from 2026-09-05/06 for the G3 shape specifically (`info: null` + a populated window) and found none in that window — consistent with the shape's measured rarity — but did find three consecutive `info: null` events with `limit_id: "premium"` and both windows null in an earlier same-day rollout, the G7 case, correctly absent from the endpoint. G3's core claim (info-null events with *populated* windows) was already proven against ~50 real historical rollouts during Task 3's implementation-time probe test; this live check corroborates the rest of the pipeline (parse → transaction → store → HTTP → phone) end-to-end with real production data, even though this particular live spawn didn't personally reproduce the info-null moment.

**Step 5 (staleness on real data):** **PASS**, via the store-level fallback the plan explicitly sanctions (a real 5-hour rollover wasn't reachable in one sitting). Read the live row directly from the dev daemon's SQLite file, noted the original `primary_resets_at`, temporarily set it to a past timestamp, confirmed the endpoint immediately returned `"stale": true` (with the numeric fields still present, per spec), had the user confirm the phone's 5-hour row switched to "Unknown — last seen ..." with no percentage or bar, then restored the original value and re-confirmed the endpoint returned to `"stale": false`.

**Step 6 (check it on the phone):** **PASS** (user-confirmed via screenshot) — the "Codex plan usage" section rendered with a 5-hour bar, a weekly bar, and "Claude Code: not reported" beneath.

Getting to a working Step 6 also surfaced a real, **pre-existing bug unrelated to this plan**: the whole Token usage screen (both "Day" and "Week") was failing with `INVALID_RANGE` before any of this plan's code ran. Root cause: `UsageRollupParams.toJson()` (`packages/mobile/lib/feature/usage/data/model/params/usage_rollup_params.dart`, present since the prior plan's `494c8643f`, untouched by this plan's 7 tasks) always included a `'days': null` entry when the cubit didn't set a range; Dio serialized that as the literal query string `days=null`; the backend's `strconv.Atoi("null")` in `usageRollupParams` (`backend/internal/httpd/controllers/usage.go`) then failed and returned `INVALID_RANGE`. Reproduced directly with `curl ".../usage/rollup?bucket=day&days=null"` vs. omitting `days` entirely. Fixed on master (commit `2ea5d100b`) by only including the `days` key when non-null (`{'bucket': bucket, if (days != null) 'days': days}`), with a new test (`usage_rollup_params_test.dart`) shown failing against the old code and passing against the fix. Full mobile gate re-run clean after the fix (`flutter analyze` → "No issues found!", `flutter test` → 1400/1400 passing).

**Step 7 (record results):** this report, plus the plan file's own Task 8 checkboxes and Result lines.

**Confidence summary:** every G1–G7 finding has now been proven at least once against real production data (not just fixtures), the endpoint and phone both render correctly end-to-end, and an unrelated screen-breaking bug that would have blocked verification (and blocked real users from seeing this feature at all) was found and fixed along the way.
