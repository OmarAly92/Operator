# Codex Quota Readout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show how much of the Codex plan's 5-hour and weekly quota is used, on the phone, from data Operator already tails.

**Architecture:** Every `token_count` event in a Codex rollout carries a `rate_limits` object with a pre-computed `used_percent`, a `window_minutes`, and a `resets_at` for two windows. The parser that already reads those files discards it. This plan persists the newest observation in a single account-wide row, serves it at `GET /api/v1/usage/quota`, and renders it as a section on the usage screen that already exists.

**Tech Stack:** Go 1.x, chi, sqlc + goose (SQLite), code-first OpenAPI via `specgen`; Flutter (cubit-only, hand-written models, `AppSkin` theming).

**Spec:** No spec document. Scoped in conversation on 2026-09-05 against 25,357 real `token_count` events across 446 rollouts. The findings that ground it are reproduced below. **Read them before Task 1** — G3 in particular describes a guard that will silently swallow your work if you don't restructure around it.

**Prior work:** This builds directly on `docs/superpowers/plans/2026-09-05-mobile-context-and-usage.md`, merged to master as `12ea43eb1`. That plan's Task 12 built the usage screen this one extends, and its F4 established the precedent being followed here: Codex reports a fact, the parser reads it, and the parser throws it away.

---

## Global Constraints

- **Mobile is a thin client.** It renders numbers, it does not compute them. `used_percent` arrives pre-computed; never recompute or rescale it.
- **No `freezed`, no `json_serializable`** in first-party mobile code. Hand-written models, all fields nullable, `fromJson` does wire→domain mapping. One params class per method under `data/model/params/`.
- **Cubit only** — never `Bloc` with events. Static-only classes are `sealed class X`.
- **Parameterized paths get static methods on `EndPoints`.** Interpolating at a call site is forbidden.
- **Mobile feature code never imports `flutter_screenutil`.** Raw ints for spacing, padding, radii.
- **User-facing copy is inline English.** No `LocaleKeys` catalogue for product copy on mobile.
- **Response envelope:** every mobile parse is `GlobalResponse.fromJson(response.data, withDataKey: false)`. Keep `requestId` on errors.
- **Gates.** Backend: `gofmt -l internal/` clean, `go vet ./...`, `go test ./...`, `golangci-lint run ./...`. Mobile: `flutter analyze` must print `No issues found!`, then `flutter test`. Frontend (only if `openapi.yaml` changes): `npm run api` then `cd backend && go test ./internal/httpd/...`.
- **`golangci-lint` caches deleted worktrees.** If it reports issues in `.worktrees/` paths that do not exist, run `golangci-lint cache clean` and re-run before believing the failure.
- **Do not write code comments unless they explain non-obvious intent.** Match the density of the file you are editing.

---

## Findings that ground this plan

Measured on 2026-09-05 across every rollout in `~/.codex/sessions/2026/`.

**G1 — The data is complete and pre-computed.** A populated `rate_limits` looks exactly like this:

```json
"rate_limits": {
  "limit_id": "codex",
  "primary":   {"used_percent": 77.0, "window_minutes": 300,   "resets_at": 1788636235},
  "secondary": {"used_percent": 12.0, "window_minutes": 10080, "resets_at": 1789223035},
  "plan_type": "plus",
  "credits": {"has_credits": false, "unlimited": false, "balance": "0"}
}
```

`window_minutes: 300` is the 5-hour window; `10080` is the weekly one. `resets_at` is Unix epoch **seconds**. `used_percent` is already a percentage — there is no limit value to look up and nothing to divide.

**G2 — Quota is account-wide, not per-session.** Across different rollouts in time order the primary window reads 67 → 73 → 74 → 75 → 76 → 100%. Every Codex session reports the same account counter. Store **one row for the account**, never one per session. Do not put this on `usage_bindings`.

**G3 — The parser cannot currently see `rate_limits`, and the reason is a trap.** `parseCodexEvent` opens with:

```go
if err := json.Unmarshal(envelope.Payload, &payload); err != nil || payload.Type != "token_count" || payload.Info == nil {
    return
}
```

`rate_limits` is a **sibling of `info`**, not a field inside it — so an event with `"info": null` still carries quota, and that guard drops it before anything reads it. Of 25,357 `token_count` events, 25,078 carry both, 149 carry `info` only, and **113 carry `rate_limits` only**. 113 is 0.4% overall but it is not evenly spread: in a freshly spawned session all three events were that shape, so a naive implementation appears to work on old sessions and reports nothing on new ones. **Read `rate_limits` before the `Info == nil` guard, and return quota independently of usage events.**

**G4 — `used_percent` is not monotonic, even inside one window.** Within a single `resets_at` the primary window was observed going 96 → 97 → 98 → 99 → 100 → **77**. Codex re-accounts. So the rule is strictly *newest observation by timestamp wins*. Never keep a maximum, and never add a monotonic guard of the kind the token parser uses.

**G5 — A stale reading is worse than none, and `resets_at` tells you when.** Quota is only observed while a Codex session is running. If Codex has not run for two days, a stored "12% used" is false. But `resets_at` makes staleness *decidable*: once `now > resets_at` the window has rolled over and the stored percentage is known-meaningless. Such a window must be reported as unknown, never as a number. Always surface `observedAt` so the client can say when it was true.

**G6 — Claude Code has no quota data at all.** Its JSONL was scanned for `ratelimit`, `rate_limit`, `resets_at`, `quota`, `weekly`, `five_hour` — nothing. This readout covers Codex only, which is a UI-honesty problem: a screen headed "usage limits" showing one bar reads as *the user's* limits. Every surface must name the harness and show Claude as "not reported", never omit it silently.

**G7 — `limit_id` varies.** `"codex"` is the populated one; a `"premium"` variant was seen with `primary` and `secondary` both null. Key the row on `limit_id` and ignore observations where both windows are null.

---

## File Structure

**Backend — new**
- `backend/internal/storage/sqlite/migrations/0100_usage_quota.sql` — the single account-wide table.
- `backend/internal/storage/sqlite/queries/usage_quota.sql` — upsert + read.

**Backend — modified**
- `backend/internal/domain/usage.go` — `UsageQuota`, `UsageQuotaWindow`, staleness rule.
- `backend/internal/observe/usage/parser.go` — read `rate_limits` ahead of the `Info` guard; `parseResult.Quota`.
- `backend/internal/storage/sqlite/store/usage_store.go` — persist in the existing atomic chunk; read the row.
- `backend/internal/service/usage/summary.go` — `Quota(ctx)`.
- `backend/internal/httpd/controllers/usage.go` — `GET /usage/quota`.

**Mobile — new**
- `packages/mobile/lib/feature/usage/data/model/usage_quota_model.dart`
- `packages/mobile/lib/feature/usage/logic/quota_readout.dart` — pure formatting, unit-tested without a widget.
- `packages/mobile/lib/feature/usage/presentation/usage_screen/ui/widgets/quota_section.dart`

**Mobile — modified**
- `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- `packages/mobile/lib/feature/usage/data/data_source/usage_remote_data_source.dart`
- `packages/mobile/lib/feature/usage/data/repository/usage_repository.dart`
- `packages/mobile/lib/feature/usage/presentation/usage_screen/logic/usage_cubit.dart` + `usage_state.dart`
- `packages/mobile/lib/feature/usage/presentation/usage_screen/ui/usage_screen.dart`

---

## Task 1: Migration for the account-wide quota row

**Files:**
- Create: `backend/internal/storage/sqlite/migrations/0100_usage_quota.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: table `usage_quota` keyed on `limit_id`.

Note 0098 and 0099 already exist on master; 0100 is the next free number.

- [ ] **Step 1: Write the migration**

```sql
-- Migration 0100: the account's Codex quota position.
--
-- One row for the account, not one per session: every Codex rollout reports the
-- same account-wide counter, and readings from different sessions are the same
-- fact observed twice. Keyed on limit_id because Codex reports more than one
-- ("codex" carries the populated windows; a "premium" variant was seen with both
-- windows null).
--
-- Percentages are nullable because a window can be absent from an observation,
-- and absent must stay distinguishable from zero -- 0% used and "not reported"
-- are opposite messages. resets_at is stored as a timestamp; the wire format is
-- Unix epoch seconds.

-- +goose Up
-- +goose StatementBegin
CREATE TABLE usage_quota (
    limit_id                TEXT PRIMARY KEY,
    harness                 TEXT NOT NULL,
    plan_type               TEXT NOT NULL DEFAULT '',
    observed_at             TIMESTAMP NOT NULL,
    primary_used_percent    REAL    CHECK (primary_used_percent IS NULL OR primary_used_percent >= 0),
    primary_window_minutes  INTEGER CHECK (primary_window_minutes IS NULL OR primary_window_minutes > 0),
    primary_resets_at       TIMESTAMP,
    secondary_used_percent  REAL    CHECK (secondary_used_percent IS NULL OR secondary_used_percent >= 0),
    secondary_window_minutes INTEGER CHECK (secondary_window_minutes IS NULL OR secondary_window_minutes > 0),
    secondary_resets_at     TIMESTAMP
);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS usage_quota;
-- +goose StatementEnd
```

- [ ] **Step 2: Verify it applies to a fresh database**

Run: `cd backend && go test ./internal/storage/sqlite/...`
Expected: PASS. `sqlitetest.MustOpen` runs every migration, so bad SQL fails here.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/storage/sqlite/migrations/0100_usage_quota.sql
git commit -m "feat(usage): add the account quota table"
```

---

## Task 2: Domain types and the staleness rule

**Files:**
- Modify: `backend/internal/domain/usage.go`
- Test: `backend/internal/domain/usage_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type UsageQuotaWindow struct { UsedPercent float64; WindowMinutes int; ResetsAt time.Time }`
  - `func (w UsageQuotaWindow) IsStale(now time.Time) bool`
  - `type UsageQuota struct { LimitID, Harness, PlanType string; ObservedAt time.Time; Primary, Secondary *UsageQuotaWindow }`
  - `func (q UsageQuota) IsEmpty() bool` — true when both windows are nil (the G7 case worth discarding)

- [ ] **Step 1: Write the failing test**

```go
func TestUsageQuotaWindowIsStaleAfterItsWindowRolls(t *testing.T) {
	reset := time.Date(2026, 9, 5, 22, 23, 55, 0, time.UTC)
	w := domain.UsageQuotaWindow{UsedPercent: 77, WindowMinutes: 300, ResetsAt: reset}

	if w.IsStale(reset.Add(-time.Minute)) {
		t.Fatal("a reading inside its own window is current")
	}
	if !w.IsStale(reset.Add(time.Minute)) {
		t.Fatal("once the window rolls the stored percentage is known-meaningless")
	}
}

func TestUsageQuotaWindowWithNoResetTimeIsNeverStale(t *testing.T) {
	w := domain.UsageQuotaWindow{UsedPercent: 12, WindowMinutes: 10080}
	if w.IsStale(time.Now()) {
		t.Fatal("with no reset time there is no evidence of staleness, so do not invent it")
	}
}

func TestUsageQuotaIsEmptyWhenNoWindowReported(t *testing.T) {
	if !(domain.UsageQuota{LimitID: "premium"}).IsEmpty() {
		t.Fatal("an observation with neither window carries nothing and must be discarded")
	}
	if (domain.UsageQuota{Primary: &domain.UsageQuotaWindow{UsedPercent: 0}}).IsEmpty() {
		t.Fatal("0% used is a real reading, not an absent one")
	}
}
```

The last case is the one that matters: `0.0` used and "not reported" must never collapse into each other.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/domain/ -run TestUsageQuota -v`
Expected: FAIL — `undefined: domain.UsageQuotaWindow`.

- [ ] **Step 3: Implement**

```go
// UsageQuotaWindow is one rate-limit window as the provider reported it.
// UsedPercent arrives pre-computed; there is no limit value to divide by.
type UsageQuotaWindow struct {
	UsedPercent   float64
	WindowMinutes int
	ResetsAt      time.Time
}

// IsStale reports that the window has rolled over since this reading, which
// makes UsedPercent meaningless rather than merely old. Quota is only observed
// while a Codex session runs, so a reading can outlive its window by days.
func (w UsageQuotaWindow) IsStale(now time.Time) bool {
	return !w.ResetsAt.IsZero() && now.After(w.ResetsAt)
}

// UsageQuota is the account's position, not a session's. Every Codex rollout
// reports the same counter.
type UsageQuota struct {
	LimitID    string
	Harness    string
	PlanType   string
	ObservedAt time.Time
	Primary    *UsageQuotaWindow
	Secondary  *UsageQuotaWindow
}

// IsEmpty reports an observation carrying no window at all, which Codex emits
// under some limit ids and which is not worth storing.
func (q UsageQuota) IsEmpty() bool { return q.Primary == nil && q.Secondary == nil }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/domain/ -run TestUsageQuota -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/domain
git commit -m "feat(usage): add quota types and the staleness rule"
```

---

## Task 3: Parse `rate_limits` ahead of the `Info` guard

**Files:**
- Modify: `backend/internal/observe/usage/parser.go`
- Test: `backend/internal/observe/usage/parser_test.go`

**Interfaces:**
- Consumes: `domain.UsageQuota` (Task 2).
- Produces: `parseResult.Quota *domain.UsageQuota`, set from the newest `token_count` event that reports a window — **including events where `info` is null**.

This is the task G3 warns about. Restructure `parseCodexEvent` so the quota read happens before the `payload.Info == nil` return, and so an info-less event still yields quota.

- [ ] **Step 1: Write the failing test**

```go
func TestParseCodexReadsQuotaFromAnInfolessEvent(t *testing.T) {
	// The exact shape a freshly spawned session emits: no usage, quota present.
	line := []byte(`{"timestamp":"2026-09-05T16:29:43.649Z","type":"event_msg","payload":{` +
		`"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","plan_type":"plus",` +
		`"primary":{"used_percent":77.0,"window_minutes":300,"resets_at":1788636235},` +
		`"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1789223035}}}}`)

	result := parseCodexForTest(t, line)

	if len(result.Events) != 0 {
		t.Fatalf("events = %d, want 0 -- there is no usage in this event", len(result.Events))
	}
	if result.Quota == nil {
		t.Fatal("quota = nil: the Info==nil guard swallowed a rate_limits-only event (G3)")
	}
	if result.Quota.Primary == nil || result.Quota.Primary.UsedPercent != 77 {
		t.Fatalf("primary = %+v, want 77%%", result.Quota.Primary)
	}
	if result.Quota.Primary.WindowMinutes != 300 {
		t.Fatalf("primary window = %d, want 300", result.Quota.Primary.WindowMinutes)
	}
	if result.Quota.Secondary == nil || result.Quota.Secondary.WindowMinutes != 10080 {
		t.Fatalf("secondary = %+v, want the 10080-minute window", result.Quota.Secondary)
	}
	if result.Quota.PlanType != "plus" || result.Quota.LimitID != "codex" {
		t.Fatalf("plan/limit = %q/%q", result.Quota.PlanType, result.Quota.LimitID)
	}
	want := time.Unix(1788636235, 0).UTC()
	if !result.Quota.Primary.ResetsAt.Equal(want) {
		t.Fatalf("resetsAt = %v, want %v (epoch seconds)", result.Quota.Primary.ResetsAt, want)
	}
}

func TestParseCodexQuotaTakesTheNewestReadingNotTheHighest(t *testing.T) {
	// Codex re-accounts inside one window: 100 then 77, same resets_at (G4).
	high := codexRateLimitLine(t, "2026-09-05T15:26:53Z", 100.0, 1788636235)
	low := codexRateLimitLine(t, "2026-09-05T15:26:55Z", 77.0, 1788636235)

	result := parseCodexForTest(t, high, low)

	if result.Quota == nil || result.Quota.Primary == nil {
		t.Fatal("quota = nil")
	}
	if result.Quota.Primary.UsedPercent != 77 {
		t.Fatalf("used = %v, want 77 -- newest wins, never the maximum", result.Quota.Primary.UsedPercent)
	}
}

func TestParseCodexIgnoresAnObservationWithNoWindows(t *testing.T) {
	line := []byte(`{"timestamp":"2026-09-05T16:29:43.649Z","type":"event_msg","payload":{` +
		`"type":"token_count","info":null,"rate_limits":{"limit_id":"premium",` +
		`"primary":null,"secondary":null,"credits":{"has_credits":false,"balance":"0"}}}}`)

	result := parseCodexForTest(t, line)

	if result.Quota != nil {
		t.Fatal("an observation with neither window carries nothing and must not be stored (G7)")
	}
}
```

Write `codexRateLimitLine(t, timestamp string, primaryPercent float64, resetsAt int64) []byte` as a helper in the test file, emitting the G1 shape with `info` null. `parseCodexForTest` already exists at `parser_test.go:619` — reuse it, do not write a second one.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseCodexReadsQuota -v`
Expected: FAIL — `result.Quota` undefined.

- [ ] **Step 3: Implement**

Add `Quota *domain.UsageQuota` to `parseResult`. Then restructure the head of `parseCodexEvent`:

```go
func parseCodexEvent(source domain.UsageSourceContext, envelope codexEnvelope, state *codexParserStateV1, result *parseResult) {
	var payload struct {
		Type string `json:"type"`
		Info *struct {
			Total              codexTokenVector `json:"total_token_usage"`
			ModelContextWindow int64            `json:"model_context_window"`
		} `json:"info"`
		RateLimits *codexRateLimits `json:"rate_limits"`
	}
	if err := json.Unmarshal(envelope.Payload, &payload); err != nil || payload.Type != "token_count" {
		return
	}
	// Before the Info guard: rate_limits is a sibling of info, not a field in
	// it, so an event with "info": null still reports the account's quota. A
	// freshly spawned session emits nothing else (G3).
	if quota := payload.RateLimits.toDomain(envelopeTimestamp(envelope)); quota != nil {
		result.Quota = quota
	}
	if payload.Info == nil {
		return
	}
	...
}
```

with:

```go
type codexRateLimitWindow struct {
	UsedPercent   float64 `json:"used_percent"`
	WindowMinutes int     `json:"window_minutes"`
	ResetsAt      int64   `json:"resets_at"`
}

type codexRateLimits struct {
	LimitID   string                `json:"limit_id"`
	PlanType  string                `json:"plan_type"`
	Primary   *codexRateLimitWindow `json:"primary"`
	Secondary *codexRateLimitWindow `json:"secondary"`
}

func (r *codexRateLimits) toDomain(observedAt time.Time) *domain.UsageQuota {
	if r == nil {
		return nil
	}
	quota := domain.UsageQuota{
		LimitID:    r.LimitID,
		Harness:    string(domain.HarnessCodex),
		PlanType:   r.PlanType,
		ObservedAt: observedAt,
		Primary:    r.Primary.toDomain(),
		Secondary:  r.Secondary.toDomain(),
	}
	if quota.IsEmpty() {
		return nil
	}
	return &quota
}

func (w *codexRateLimitWindow) toDomain() *domain.UsageQuotaWindow {
	if w == nil {
		return nil
	}
	out := domain.UsageQuotaWindow{UsedPercent: w.UsedPercent, WindowMinutes: w.WindowMinutes}
	if w.ResetsAt > 0 {
		out.ResetsAt = time.Unix(w.ResetsAt, 0).UTC()
	}
	return &out
}
```

Assigning `result.Quota` unconditionally on each qualifying event means the last one parsed wins, which is the newest — that is G4's rule, and it is why there is no comparison here.

`envelopeTimestamp` already exists from the prior plan's Task 4. If it does not, read `codexEnvelope` for the timestamp field name and add it.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/observe/usage/ -run TestParseCodex -v`
Expected: PASS, including the pre-existing Codex tests.

- [ ] **Step 5: Verify against a real rollout**

This proves the shape against genuine provider output rather than a fixture. Create a throwaway test, run it, then delete it:

```go
func TestProbeRealRollout(t *testing.T) {
	matches, _ := filepath.Glob(os.Getenv("HOME") + "/.codex/sessions/2026/*/*/*.jsonl")
	if len(matches) == 0 {
		t.Skip("no real rollouts on this machine")
	}
	var found int
	for _, path := range matches {
		f, err := os.Open(path)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		scanner.Buffer(make([]byte, 1024*1024), 8*1024*1024)
		var records [][]byte
		for scanner.Scan() {
			records = append(records, append([]byte(nil), scanner.Bytes()...))
		}
		f.Close()
		if len(records) == 0 {
			continue
		}
		if r := parseCodexForTest(t, records...); r.Quota != nil {
			found++
			t.Logf("%s -> limit=%s plan=%s primary=%+v secondary=%+v",
				filepath.Base(path), r.Quota.LimitID, r.Quota.PlanType, r.Quota.Primary, r.Quota.Secondary)
		}
	}
	if found == 0 {
		t.Fatal("no rollout yielded quota, but real files are known to carry it")
	}
}
```

Expected: many rollouts report quota, with `window_minutes` 300 and 10080. Delete the file before committing.

- [ ] **Step 6: Run the whole package**

Run: `cd backend && go test ./internal/observe/usage/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/observe/usage
git commit -m "feat(usage): read the Codex rate limits the parser was discarding"
```

---

## Task 4: Persist and read the quota

**Files:**
- Create: `backend/internal/storage/sqlite/queries/usage_quota.sql`
- Modify: `backend/internal/storage/sqlite/store/usage_store.go`
- Test: `backend/internal/storage/sqlite/store/usage_store_test.go`

**Interfaces:**
- Consumes: `domain.UsageQuota`, `parseResult.Quota`.
- Produces:
  - `func (s *Store) SaveUsageQuota(ctx context.Context, q domain.UsageQuota) error` — newest-wins upsert
  - `func (s *Store) GetUsageQuota(ctx context.Context) (domain.UsageQuota, bool, error)` — newest row across limit ids
  - `ApplyUsageChunkWithContext` gains a trailing `quota *domain.UsageQuota` parameter so the write joins the existing transaction

- [ ] **Step 1: Write the queries**

```sql
-- name: UpsertUsageQuota :exec
-- Newest observation wins. used_percent is not monotonic even inside one window
-- (G4), so this compares observation time and never the percentage.
INSERT INTO usage_quota (
    limit_id, harness, plan_type, observed_at,
    primary_used_percent, primary_window_minutes, primary_resets_at,
    secondary_used_percent, secondary_window_minutes, secondary_resets_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (limit_id) DO UPDATE SET
    harness = excluded.harness,
    plan_type = excluded.plan_type,
    observed_at = excluded.observed_at,
    primary_used_percent = excluded.primary_used_percent,
    primary_window_minutes = excluded.primary_window_minutes,
    primary_resets_at = excluded.primary_resets_at,
    secondary_used_percent = excluded.secondary_used_percent,
    secondary_window_minutes = excluded.secondary_window_minutes,
    secondary_resets_at = excluded.secondary_resets_at
WHERE excluded.observed_at > usage_quota.observed_at;

-- name: GetLatestUsageQuota :one
SELECT limit_id, harness, plan_type, observed_at,
       primary_used_percent, primary_window_minutes, primary_resets_at,
       secondary_used_percent, secondary_window_minutes, secondary_resets_at
FROM usage_quota
ORDER BY observed_at DESC
LIMIT 1;
```

- [ ] **Step 2: Regenerate sqlc and write the failing test**

Run: `cd backend && go generate ./internal/storage/sqlite/...`

```go
func TestSaveUsageQuotaKeepsTheNewestObservation(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	ctx := context.Background()

	older := domain.UsageQuota{
		LimitID: "codex", Harness: "codex", PlanType: "plus",
		ObservedAt: parseTime(t, "2026-09-05T15:26:53Z"),
		Primary:    &domain.UsageQuotaWindow{UsedPercent: 100, WindowMinutes: 300},
	}
	newer := domain.UsageQuota{
		LimitID: "codex", Harness: "codex", PlanType: "plus",
		ObservedAt: parseTime(t, "2026-09-05T15:26:55Z"),
		Primary:    &domain.UsageQuotaWindow{UsedPercent: 77, WindowMinutes: 300},
	}

	if err := store.SaveUsageQuota(ctx, older); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveUsageQuota(ctx, newer); err != nil {
		t.Fatal(err)
	}
	got, ok, err := store.GetUsageQuota(ctx)
	if err != nil || !ok {
		t.Fatalf("get = %v %v", ok, err)
	}
	if got.Primary.UsedPercent != 77 {
		t.Fatalf("used = %v, want 77 -- newest wins even when it is lower", got.Primary.UsedPercent)
	}
}

func TestSaveUsageQuotaIgnoresAnOlderObservation(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	ctx := context.Background()
	newer := domain.UsageQuota{LimitID: "codex", ObservedAt: parseTime(t, "2026-09-05T15:26:55Z"),
		Primary: &domain.UsageQuotaWindow{UsedPercent: 77, WindowMinutes: 300}}
	older := domain.UsageQuota{LimitID: "codex", ObservedAt: parseTime(t, "2026-09-05T10:00:00Z"),
		Primary: &domain.UsageQuotaWindow{UsedPercent: 5, WindowMinutes: 300}}

	if err := store.SaveUsageQuota(ctx, newer); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveUsageQuota(ctx, older); err != nil {
		t.Fatal(err)
	}
	got, _, _ := store.GetUsageQuota(ctx)
	if got.Primary.UsedPercent != 77 {
		t.Fatalf("used = %v, want 77 -- a late-arriving old reading must not win", got.Primary.UsedPercent)
	}
}

func TestGetUsageQuotaReportsAbsenceRatherThanZero(t *testing.T) {
	store := sqlitetest.MustOpen(t)
	_, ok, err := store.GetUsageQuota(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if ok {
		t.Fatal("want ok=false on an empty table, so the client renders nothing rather than 0%")
	}
}
```

`parseTime` already exists in this test file from the prior plan's Task 5 — reuse it.

- [ ] **Step 3: Run to verify failure, then implement**

Run: `cd backend && go test ./internal/storage/sqlite/store/ -run TestUsageQuota -v` (and the Save/Get names above)
Expected: FAIL — methods undefined.

Implement `SaveUsageQuota` and `GetUsageQuota` following the neighbouring methods' locking convention (`s.writeMu.Lock()` for writes, `s.qr` for reads). `GetUsageQuota` maps `sql.ErrNoRows` to `(zero, false, nil)`. Then thread the quota through `ApplyUsageChunkWithContext` and `applyUsageChunk` so it is written inside the same transaction as the events — the context snapshot already works this way (`usage_store.go:449`), and quota should not be able to land while the chunk that produced it rolls back.

- [ ] **Step 4: Run to verify it passes**

Run: `cd backend && go test ./internal/storage/sqlite/store/`
Expected: PASS.

- [ ] **Step 5: Wire the collector**

In `backend/internal/service/usage/collector.go`, pass `result.Quota` into the `ApplyUsageChunkWithContext` call alongside the existing `result.Context`.

- [ ] **Step 6: Run the service and storage tests**

Run: `cd backend && go test ./internal/service/usage/ ./internal/storage/sqlite/...`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/storage backend/internal/service/usage
git commit -m "feat(usage): persist the account quota with the usage chunk"
```

---

## Task 5: Service and HTTP endpoint

**Files:**
- Modify: `backend/internal/service/usage/summary.go`
- Modify: `backend/internal/httpd/controllers/usage.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Test: `backend/internal/service/usage/summary_test.go`, `backend/internal/httpd/controllers/usage_test.go`

**Interfaces:**
- Consumes: `Store.GetUsageQuota`.
- Produces:
  - `func (r *SummaryReader) Quota(ctx context.Context) (domain.UsageQuota, bool, error)`
  - `GET /api/v1/usage/quota` → `200` with `{"quota": null}` when never observed, otherwise:

```json
{"quota": {
  "harness": "codex", "limitId": "codex", "planType": "plus",
  "observedAt": "2026-09-05T15:26:55Z",
  "windows": [
    {"kind": "primary",   "windowMinutes": 300,   "usedPercent": 77, "resetsAt": "2026-09-05T19:23:55Z", "stale": false},
    {"kind": "secondary", "windowMinutes": 10080, "usedPercent": 12, "resetsAt": "2026-09-12T14:23:55Z", "stale": false}
  ]}}
```

`stale` is computed server-side from `IsStale(now)` — mobile is a thin client and must not decide this. A stale window still reports its numbers so the client can explain *why* it is showing nothing, but the client must not render the percentage when `stale` is true.

- [ ] **Step 1: Write the failing tests**

```go
func TestQuotaMarksARolledWindowStale(t *testing.T) {
	past := time.Now().Add(-2 * time.Hour)
	rec := doRequest(t, newUsageController(&fakeSummary{
		quota: domain.UsageQuota{
			LimitID: "codex", Harness: "codex", PlanType: "plus",
			ObservedAt: past.Add(-time.Hour),
			Primary:    &domain.UsageQuotaWindow{UsedPercent: 77, WindowMinutes: 300, ResetsAt: past},
		},
		hasQuota: true,
	}), http.MethodGet, "/usage/quota", nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var body UsageQuotaEnvelope
	mustDecode(t, rec, &body)
	if body.Quota == nil || len(body.Quota.Windows) != 1 {
		t.Fatalf("quota = %+v", body.Quota)
	}
	if !body.Quota.Windows[0].Stale {
		t.Fatal("a window whose resetsAt has passed must be reported stale")
	}
}

func TestQuotaReturnsNullWhenNeverObserved(t *testing.T) {
	rec := doRequest(t, newUsageController(&fakeSummary{hasQuota: false}), http.MethodGet, "/usage/quota", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 with a null quota rather than an error", rec.Code)
	}
	var body UsageQuotaEnvelope
	mustDecode(t, rec, &body)
	if body.Quota != nil {
		t.Fatal("want null so the client can say 'not observed' rather than 0%")
	}
}
```

Extend the existing `fakeSummary` with `quota`/`hasQuota` and a `Quota` method. `doRequest`, `mustDecode` and `assertErrorCode` already exist — reuse them.

- [ ] **Step 2: Run to verify failure**

Run: `cd backend && go test ./internal/httpd/controllers/ -run TestQuota -v`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add `Quota` to `usageSummaryStore` and `SummaryReader`; register `r.Get("/usage/quota", c.quota)`; add `UsageQuotaEnvelope`, `UsageQuotaResponse` and `UsageQuotaWindowResponse` DTOs beside the existing usage DTOs; register the new named types in `specgen/build.go` per `AGENTS.md:117`. Omit a nil window from `windows` rather than emitting a null entry.

- [ ] **Step 4: Run to verify it passes**

Run: `cd backend && go test ./internal/httpd/... ./internal/service/usage/`
Expected: PASS, including spec-drift and route-parity tests.

- [ ] **Step 5: Regenerate the API artifacts**

```bash
cd /Users/omaraly/development/AI/Operator && npm run api
cd backend && go test ./internal/httpd/...
```
Expected: PASS. Commit `openapi.yaml` and `frontend/src/api/schema.ts` with the Go changes.

- [ ] **Step 6: Full backend gate**

```bash
cd backend && gofmt -l internal/ && go vet ./... && go test ./... && golangci-lint run ./...
```
Expected: clean, all pass, `0 issues`.

- [ ] **Step 7: Commit**

```bash
git add backend frontend/src/api/schema.ts
git commit -m "feat(usage): serve the Codex quota position over HTTP"
```

---

## Task 6: Mobile model, endpoint and repository

**Files:**
- Create: `packages/mobile/lib/feature/usage/data/model/usage_quota_model.dart`
- Modify: `packages/mobile/lib/core/api/api_request_helpers/end_points.dart`
- Modify: `packages/mobile/lib/feature/usage/data/data_source/usage_remote_data_source.dart`
- Modify: `packages/mobile/lib/feature/usage/data/repository/usage_repository.dart`
- Test: `packages/mobile/test/feature/usage/usage_quota_model_test.dart`

**Interfaces:**
- Consumes: the wire shape from Task 5.
- Produces: `UsageQuotaModel{harness, limitId, planType, observedAt, windows}`, `UsageQuotaWindowModel{kind, windowMinutes, usedPercent, resetsAt, stale}`, `EndPoints.usageQuota`, `UsageRepository.quota() → Future<UsageQuotaModel?>`.

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  group('UsageQuotaModel', () {
    test('parses both windows', () {
      final m = UsageQuotaModel.fromJson(const {
        'harness': 'codex', 'limitId': 'codex', 'planType': 'plus',
        'observedAt': '2026-09-05T15:26:55Z',
        'windows': [
          {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'resetsAt': '2026-09-05T19:23:55Z', 'stale': false},
          {'kind': 'secondary', 'windowMinutes': 10080, 'usedPercent': 12, 'resetsAt': '2026-09-12T14:23:55Z', 'stale': false},
        ],
      });
      expect(m.windows, hasLength(2));
      expect(m.windows.first.usedPercent, 77);
      expect(m.windows.first.windowMinutes, 300);
      expect(m.planType, 'plus');
    });

    test('keeps a stale window rather than dropping it', () {
      final m = UsageQuotaModel.fromJson(const {
        'harness': 'codex',
        'windows': [
          {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'stale': true},
        ],
      });
      expect(m.windows.single.stale, isTrue);
      expect(m.windows.single.usedPercent, 77);
    });

    test('tolerates missing fields', () {
      final m = UsageQuotaModel.fromJson(const {});
      expect(m.windows, isEmpty);
      expect(m.planType, isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/usage_quota_model_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Hand-written, all fields nullable, `Equatable`. Add `static const String usageQuota = '/api/v1/usage/quota';` to `EndPoints`. The repository returns `null` when the envelope's `quota` is null — mirror how `sessionContext` already handles absence in this same repository.

- [ ] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): add the usage quota model and repository call"
```

---

## Task 7: Quota section on the usage screen

**Files:**
- Create: `packages/mobile/lib/feature/usage/logic/quota_readout.dart`
- Create: `packages/mobile/lib/feature/usage/presentation/usage_screen/ui/widgets/quota_section.dart`
- Modify: `packages/mobile/lib/feature/usage/presentation/usage_screen/logic/usage_cubit.dart` + `usage_state.dart`
- Modify: `packages/mobile/lib/feature/usage/presentation/usage_screen/ui/usage_screen.dart`
- Test: `packages/mobile/test/feature/usage/quota_readout_test.dart`, `packages/mobile/test/feature/usage/quota_section_test.dart`

**Interfaces:**
- Consumes: `UsageQuotaModel`, `UsageRepository.quota()`.
- Produces: `sealed class QuotaReadout` with `static QuotaReadoutData? of(UsageQuotaWindowModel?)`; `QuotaSection`; `UsageState` gains `quota` and `quotaStale`.

**Copy rules, from G5 and G6.** The section is headed **"Codex plan usage"**, never "limits" alone, and it names the harness. Windows are labelled from `windowMinutes`: 300 → "5-hour window", 10080 → "Weekly", anything else → "<n>-minute window". Under it, a line reading **"Claude Code: not reported"** — Claude publishes no quota, and silently omitting it would let the Codex bar read as the machine's overall position. A stale window shows **"Unknown — last seen <relative time>"** and no percentage and no bar.

- [ ] **Step 1: Write the failing tests**

```dart
void main() {
  test('labels the windows from their length', () {
    expect(QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77))!.label, '5-hour window');
    expect(QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 10080, usedPercent: 12))!.label, 'Weekly');
  });

  test('renders a stale window as unknown with no percentage', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77, stale: true))!;
    expect(r.percentLabel, isNull);
    expect(r.fraction, isNull);
    expect(r.isUnknown, isTrue);
  });

  test('keeps a fresh reading', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 77))!;
    expect(r.percentLabel, '77%');
    expect(r.fraction, closeTo(0.77, 0.0001));
    expect(r.isUnknown, isFalse);
  });

  test('zero percent is a reading, not an absence', () {
    final r = QuotaReadout.of(const UsageQuotaWindowModel(windowMinutes: 300, usedPercent: 0))!;
    expect(r.percentLabel, '0%');
    expect(r.isUnknown, isFalse);
  });

  test('renders nothing without a window', () {
    expect(QuotaReadout.of(null), isNull);
  });
}
```

And for the widget:

```dart
testWidgets('names the harness and says Claude is not reported', (tester) async {
  await tester.pumpWidget(_wrap(QuotaSection(quota: UsageQuotaModel.fromJson(const {
    'harness': 'codex', 'planType': 'plus',
    'windows': [
      {'kind': 'primary', 'windowMinutes': 300, 'usedPercent': 77, 'stale': false},
    ],
  }))));
  expect(find.text('Codex plan usage'), findsOneWidget);
  expect(find.text('5-hour window'), findsOneWidget);
  expect(find.text('77%'), findsOneWidget);
  expect(find.textContaining('Claude Code'), findsOneWidget);
  expect(find.textContaining('not reported'), findsOneWidget);
});

testWidgets('renders nothing when quota was never observed', (tester) async {
  await tester.pumpWidget(_wrap(const QuotaSection(quota: null)));
  expect(find.text('Codex plan usage'), findsNothing);
});
```

Copy `_wrap` from an existing usage-screen widget test.

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: FAIL.

- [ ] **Step 3: Implement**

`UsageState` gains `final UsageQuotaModel? quota;` with `copyWith` and `props` updated. `UsageCubit.load` fetches quota alongside the rollup; a quota failure must not fail the screen — the buckets still render. Use `context.skin` for colours, `AppTextStyle` for type, raw ints for spacing.

- [ ] **Step 4: Run to verify it passes**

Run: `cd packages/mobile && flutter test test/feature/usage/`
Expected: PASS.

- [ ] **Step 5: Full mobile gate**

```bash
cd packages/mobile && flutter analyze && flutter test
```
Expected: `No issues found!`, then all tests pass.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile
git commit -m "feat(mobile): show the Codex plan quota on the usage screen"
```

---

## Task 8: Live verification

**Files:** none — verification only, no code deliverable.

Every prior task tests against fixtures. This feature is a claim about what Codex writes into real files, and the highest-risk defect (G3) is invisible to fixtures if the fixtures happen to include `info`.

- [ ] **Step 1: Restart the daemon on this branch**

Restart it **from the desktop app**, not a shell. A daemon launched from an agent shell inherits `CLAUDE_*` and `ANTHROPIC_*` variables and every agent it spawns exits immediately. If launching by hand is unavoidable, unset every such variable and set `TERM` and `LANG`.

- [ ] **Step 2: Spawn a fresh Codex session and take one turn**

```bash
curl -s -X POST http://127.0.0.1:3002/api/v1/sessions \
  -H 'Content-Type: application/json' \
  -d '{"projectId":"scratch","prompt":"say ok","harness":"codex","kind":"worker"}'
```

A brand-new session is the important case: its early `token_count` events carry `"info": null`, so this is what proves G3 was handled.

- [ ] **Step 3: Confirm the endpoint reports quota**

```bash
curl -s http://127.0.0.1:3002/api/v1/usage/quota | python3 -m json.tool
```

Expected: a `primary` window with `windowMinutes` 300 and a `secondary` with 10080, both with a `usedPercent` and a `resetsAt`, `stale: false`, and a `planType`. **If `quota` is null, the `Info == nil` guard is still swallowing the event — that is G3, and the task is not done.**

Result: _(fill in)_

- [ ] **Step 4: Cross-check against the rollout**

```bash
ls -t ~/.codex/sessions/2026/*/*/*.jsonl | head -1 | xargs python3 -c "
import json,sys
for line in open(sys.argv[1]):
    p=(json.loads(line).get('payload') or {})
    if p.get('type')=='token_count' and p.get('rate_limits'):
        print(json.dumps(p['rate_limits']))" | tail -1
```

Expected: the `used_percent` values match what the endpoint returned.

Result: _(fill in)_

- [ ] **Step 5: Confirm the staleness rule on real data**

Note the `resetsAt` the endpoint reported for the 5-hour window. After it passes — or by temporarily checking a row whose `resets_at` is in the past — confirm the window comes back `stale: true` and that the phone shows "Unknown", not a percentage.

Result: _(fill in)_

- [ ] **Step 6: Check it on the phone**

Settings → Token usage. Expected: a "Codex plan usage" section with a 5-hour and a weekly bar, and a "Claude Code: not reported" line beneath.

Result: _(fill in)_

- [ ] **Step 7: Record the results**

Write the actual output into `docs/superpowers/plans/2026-09-05-codex-quota-readout-report.md`. State each gate as pass or fail, never as "was run".

---

## Self-Review

**Finding coverage.** G1 → Tasks 1–3 (shape and units). G2 → Task 1's single account row, Task 4's `GetLatestUsageQuota`. G3 → Task 3, its first test, and Task 8 Step 3's explicit failure condition. G4 → Task 3's newest-wins assignment, Task 4's `observed_at` comparison and both upsert tests. G5 → Task 2's `IsStale`, Task 5's server-computed `stale` flag, Task 7's "Unknown" branch, Task 8 Step 5. G6 → Task 7's copy rules and the "Claude Code: not reported" test. G7 → Task 2's `IsEmpty` and Task 3's third test.

**Placeholders.** None. Tasks 3, 4, 5 and 7 direct the implementer to reuse named existing helpers (`parseCodexForTest` at `parser_test.go:619`, `parseTime`, `doRequest`/`mustDecode`, `_wrap`) rather than inventing fixtures — those signatures are the contract, and guessing them yields tests that compile against nothing.

**Type consistency.** `UsageQuota{LimitID, Harness, PlanType, ObservedAt, Primary, Secondary}` and `UsageQuotaWindow{UsedPercent, WindowMinutes, ResetsAt}` are used identically in Tasks 2–5. The wire flattens the two windows into a `windows` array with a `kind` discriminator, and Task 6's Dart model mirrors that array, not the Go struct — this is deliberate, and Task 5's example response is the contract both sides follow. `stale` is computed once, server-side, and only read on the client.

**Known risk.** Task 8 Step 5 depends on a real window rolling over, which may not happen inside a working session. If it does not, verify the branch with a store-level test instead and say so in the report rather than ticking it unverified.
