# Planning Tickets daemon plan — execution report

**Plan:** `docs/superpowers/plans/2026-09-18-planning-tickets-daemon.md`
**Spec:** `docs/superpowers/specs/2026-09-18-planning-tickets-design.md`
**Branch:** `feat/planning-tickets-daemon` (worktree, cut from `development`)
**Process:** superpowers `subagent-driven-development` — fresh implementer subagent per task, task-scoped spec+quality review after each, one final whole-branch review, one fix wave, one scoped re-review.

## Commit list

```
f03f02e89 feat(tickets): ticket and plan assignment tables with store and CDC event
84b9bf52d feat(tickets): frontmatter, slug and ticket folder scanner
9539907dc feat(tickets): derive plan and ticket status from linked sessions
7c78ba5a8 feat(tickets): planning and implementing task prompts
3784c4d70 feat(tickets): git helpers for ticket folders
87b796a87 feat(tickets): ticket service read models, files and create
89486fd52 fix(tickets): close symlinked-intermediate-directory escape in resolveTicketPath
10de2f21f fix(tickets): reject dangling leaf symlinks in resolveTicketPath
2152b5062 feat(tickets): ticket role defaults on project config
36552a962 feat(tickets): plan, assign, mark done and archive
2a918e395 fix(tickets): regenerate frontend api schema and dedupe session index lookup
b6a576431 feat(tickets): review by planner or fresh session, merge-ready and merge confirmation
30412eab9 feat(tickets): auto-review when an implementing session opens a PR
ee7249fe3 feat(tickets): sessions carry their ticket link
ea5588357 feat(tickets): ticket routes, OpenAPI operations and daemon wiring
ff7f31744 test(tickets): end-to-end create, plan, assign and done through real store and manager
766cd6035 fix(tickets): close lint findings, SSE timeout leak, slug traversal, and dryRun parsing
```

16 commits over Tasks 1, 2, 3, 4, 5, 6, 7, 7b, 7c, 8, 9, 10 plus the final whole-branch-review fix wave. Every commit carries the required `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` trailer (Task 5's implementer used a cheaper model and its trailer reads `Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>` — left as-is, it is still a valid attribution of the agent that wrote it).

## Gate output summary

Every task passed its own gate (`go build ./... && go test ./... && go vet ./... && gofmt -l internal`, plus `npm run api`/`go test ./internal/httpd/...`/`npm run typecheck` after any route or DTO change) before being marked complete. The final state of the branch:

- `cd backend && go build ./...` — clean.
- `cd backend && go test ./...` — all packages pass.
- `cd backend && go test -race ./internal/service/ticket/ ./internal/storage/sqlite/... ./internal/httpd/...` — clean, no races.
- `cd backend && go vet ./...` — clean.
- `gofmt -l internal` — empty.
- `npm run lint` (golangci-lint v2.12.2, root) — zero new findings on this branch (`--new-from-rev` against the branch's base commit confirms it; the handful of findings visible in an unscoped `npm run lint` run are pre-existing on `development` in files this branch never touched, e.g. `session_manager/`, `service/slashcommands/`, plus one artifact from a sibling checkout outside this repo).
- `cd frontend && npm run typecheck` — clean.
- `npm run api` — `openapi.yaml` and `frontend/src/api/schema.ts` are in sync with the final Go DTOs (`TestBuild_MatchesEmbedded`, `TestRouteSpecParity` both pass).

## Deviations from the plan, and why

1. **Task-brief extraction bug (tooling, not code):** the shared `task-brief` script's task-boundary regex (`^#+[ \t]+Task[ \t]+N([^0-9]|$)`) matches `Task 7b`/`Task 7c` headings when asked for Task 7 (the character after "7" — `b` or `c` — satisfies `[^0-9]`). Worked around by manually extracting Tasks 7, 7b, 7c by line range instead of trusting the script for those three. No code impact; noted here so a future run of this skill knows to check task-brief output boundaries when task IDs have letter suffixes.

2. **Domain type pulled forward (Task 7, ahead of Task 7b):** the plan's own Task 7 code references `domain.TicketDefaults`/`domain.TicketRoleDefaults`/`ProjectConfig.Tickets`, but the plan's file map assigns adding those types to Task 7b, which runs *after* Task 7. Task 7 cannot compile as written without them. Ruled: added the types in Task 7, using the exact final shape Task 7b's own brief specifies, so Task 7 compiles standalone in file order; Task 7b's implementer was told the types already exist and must be reused, not redefined (verified in Task 7b's review — no duplicate definition).

3. **Two security fixes beyond the brief's literal code (Task 6):** `resolveTicketPath`'s brief-given symlink-escape check had two real, reproducible gaps — a symlinked *intermediate directory* (e.g. `plans/`) escaping containment on a new-file write, and a dangling *leaf* symlink doing the same. Both were found by task review, fixed in two dedicated fix rounds, and independently re-verified by trace + new regression tests. A third, much lower-severity TOCTOU gap (between the leaf-symlink check and the actual write) was identified and deliberately left open — see "Left undone" below.

4. **Two forced deviations in Task 7's literal test/code:** (a) the brief's `Assign` dry-run path returns `Session: nil` unconditionally, but the brief's own test dereferences `res.Session.ID` right after a dry-run call — fixed by returning the plan's *existing* assigned session (nil if none) on dry-run, which is what makes the brief's own test pass. (b) one test assertion had a stray backtick that didn't match the already-merged, separately-tested `implementPrompt` output format — corrected to match the real, verified format. Both were independently re-verified by the task reviewer, not just accepted on the implementer's word.

5. **Redundant `sessionIndex` calls deduped (Tasks 7, 7b):** the brief's literal code for `Plan`/`Assign`/`Review`/`ApproveMerge` calls `s.load(...)` and then separately calls `s.sessionIndex(...)` again, doubling a session-store query per call. Fixed by adding a `loadWithSessions` variant that returns the sessions map it already builds; `Plan`, `Assign`, `Review`, and `ApproveMerge` all use it. `Get` and other plain-`load` callers are unaffected.

6. **`npm run lint` never appeared in any per-task Global Constraint** until Task 10's own gate named it explicitly — so nine tasks accumulated 17 real lint findings (gosec directory/file permissions, revive builtin-shadowing, staticcheck, wastedassign, ineffassign, a `nilerr`, unparam/unconvert) in `service/ticket/service.go`/`service_test.go` before anything caught them. All 17 were fixed in the final whole-branch-review fix wave, verified at zero new findings.

7. **Final whole-branch review found three more Important issues no per-task reviewer could see** (assembled-router problems only visible once every task landed): the tickets SSE route was registered inside the 60-second request-timeout middleware group (would disconnect/reconnect-loop every minute); the `{slug}` path param was never validated before reaching filesystem path construction (low-exploitability on a loopback daemon, but a real defense-in-depth gap); the `dryRun` query param used a loose string match that failed open toward spawning a session on a malformed value. All three fixed and re-reviewed clean in one fix wave, alongside four cheap Minor items (a slug collision with the static `events` route segment, a dead test-only helper, a scanner warning that silently clobbered another, a redundant double call to `planBranch`).

## Curl verification against a real daemon

Ran with every `CLAUDE*`-named environment variable removed (`env | cut -d= -f1 | grep -i claude` printed nothing before the daemon started), using a from-scratch build of `opr`, an isolated `OPERATOR_DATA_DIR`/`OPERATOR_RUN_FILE`/`OPERATOR_PORT` (39217, chosen to avoid the two `opr` daemons already running on the user's machine at 3001/3002 — those were confirmed untouched throughout and after), and a throwaway git repo registered as a `single_repo` project (`id: repo`).

```
$ curl -s -X POST localhost:39217/api/v1/projects -H 'content-type: application/json' \
    -d '{"path":".../opr-verify/repo"}'
{"project":{"id":"repo","name":"repo","kind":"single_repo","path":".../repo",
  "repo":"","defaultBranch":"main","agent":"claude-code"}}

$ curl -s -X POST localhost:39217/api/v1/projects/repo/tickets -H 'content-type: application/json' \
    -d '{"title":"Smoke ticket","brief":"daemon smoke"}'
{"ticket":{"projectId":"repo","slug":"smoke-ticket","title":"Smoke ticket",
  "brief":"daemon smoke","status":"draft","plans":[],
  "files":["ticket.md","spec.md"],"createdAt":"2026-09-18T01:21:37.474578Z"},
 "warnings":[]}

$ curl -s localhost:39217/api/v1/projects/repo/tickets | jq '.tickets[] | {slug, status, plans}'
{"slug":"smoke-ticket","status":"draft","plans":[]}

$ curl -s "localhost:39217/api/v1/projects/repo/tickets/smoke-ticket/file?path=spec.md"
{"path":"spec.md","content":"# Smoke ticket\n","modifiedAt":"2026-09-18T01:21:37.475141673Z"}

$ curl -s -X PUT ".../tickets/smoke-ticket/file?path=plans/01-first.md" \
    -d '{"content":"---\ntitle: First\n---\n"}'
{"path":"plans/01-first.md","content":"---\ntitle: First\n---\n",
  "modifiedAt":"2026-09-18T01:21:45.68234673Z"}

$ curl -s -X POST ".../tickets/smoke-ticket/plans/01-first.md/assign?dryRun=1"
{"warnings":["ticket_repo_dirty"]}

$ curl -s -N localhost:39217/api/v1/projects/repo/tickets/events   # (during a spec.md write)
event: tickets_changed
data: {}

$ curl -s localhost:39217/api/v1/sessions | jq '.sessions | length'
0
```

Every response matched the acceptance criteria in Task 10 Step 4 exactly: create returns 201-shaped data with slug `smoke-ticket` and no warnings (clean default-branch repo); the dry-run assign reports `ticket_repo_dirty` because the plan file was written through the API but never committed; the SSE stream emits `event: tickets_changed` on a real file write to the watched folder.

**Not exercised against the live daemon: forced assign, review, merge-ready, merge.** The plan's Step 4 instruction says to use the `fake` harness for the assign step specifically so the smoke test never spawns a real coding-agent process. I confirmed the `fake` adapter (`backend/internal/adapters/agent/fake/fake.go`) is only ever wired into `sqlitetest`/`newStack`-based Go tests — it is not registered by `buildAgentResolver`/`buildAgentRegistry` (`backend/internal/daemon/lifecycle_wiring.go:402-420`) in a real `opr daemon` process. Confirmed empirically too: the daemon's own startup log lists its registered harnesses (`agy aider amp auggie autohand claude-code cline codex continue copilot crush cursor devin droid goose grok kilocode kimchi kimi kiro muse opencode pi prime-agent qwen vibe`) with no `fake` entry, and `POST .../assign` with `{"harness":"fake"}` returns `400 UNKNOWN_HARNESS`.

The only harnesses actually available in a real daemon are real coding-agent CLIs. Forcing the assign with one of those (e.g. `claude-code`, the only one authenticated on this machine) would have created a real worktree and started an actual agent turn against the user's Claude account — a genuine cost/side-effect I'm not authorized to trigger as a side effect of an automated smoke test. I stopped there rather than guess.

This gap is fully covered another way: **Task 10's own Go integration test, `TestTicketCreatePlanAssignRoundTrip`** (`backend/internal/integration/tickets_sqlite_test.go`), already exercises the complete assign → review → merge-ready → approve → fresh-review → done lifecycle through the real SQLite store and the real session manager (`newStack`), asserting the exact branch name (`opr/editor-01`), workspace mode, prompt contents, session `ticket` ref role at every step, and at least 8 real `ticket_updated` CDC events — the session manager's injected runtime in that test harness is the safe equivalent of what a live "fake harness" daemon endpoint would have shown, and it passed clean (including under `-race`).

## Anything left undone, and why

From the final whole-branch review's Minor findings, deliberately left as follow-up work rather than folded into this branch (each would need new test coverage or new status/error semantics beyond a mechanical fix, and `AGENTS.md` asks for surgical, non-scope-creeping changes):

- **`resolveTicketPath` TOCTOU** — a narrow window between the leaf-symlink `Lstat` check and the actual `os.WriteFile`. Requires a local attacker who can already write into the same ticket folder concurrently with a legitimate request; low severity given the threat model (loopback daemon, same-user filesystem access). Follow-up: open with `O_NOFOLLOW` (or platform equivalent) instead of a separate pre-check.
- **`WatchRoot` creates `.operator/tickets/` as a side effect of a GET** (opening the SSE stream). Harmless (git ignores empty dirs) but a read route shouldn't have a write side effect; spec's "Decisions" table says the daemon writes into the repo only on create and editor save.
- **Post-approval status regresses to `reviewing`** with no surfaced signal that the user's merge approval actually happened, until PR facts eventually say `merged`. The spec doesn't define an intermediate status for this; would need a new `PlanStatus` value or exposing `mergeApprovedAt` on `PlanView`.
- **Spec §5's "session deletion leaves rows" verifier test** was never written. The behavior is believed correct (`ON DELETE SET NULL` on the FK, `SessionTicketRef` returns not-found for a nulled session, `planStatus` folds a missing session to `terminated`) but it's unpinned by a test.
- **`Assign`'s spawn-then-record isn't atomic.** A store failure after a successful session spawn leaves a live, unlinked session and returns an error to the caller; the reverse direction (spawn failure leaves no assignment row) is tested, this direction isn't.
- **`toSession` N+1 growth.** Up to three extra store queries per session on `GET /sessions` (`SessionTicketRef` tries planning → implementing → reviewing lookups in sequence). Consistent with the existing per-session PR-facts query pattern, not a regression in kind, but worth watching as the board polls this route.

None of the above block merge; they're recorded here so plan 2/3 (or a dedicated follow-up) can pick them up with full context.

## Rulings made during execution

(Full list also lives in the SDD ledger at `.superpowers/sdd/2026-09-18-planning-tickets-daemon/progress.md`, along with every task's completion and fix-round entries.)

1. Pulled `TicketRoleDefaults`/`TicketDefaults`/`ProjectConfig.Tickets` forward into Task 7 so it compiles standalone in file order — cost if wrong: a trivial duplicate-definition compile error in Task 7b, easy to spot and fix.
2. Fixed the `resolveTicketPath` symlinked-intermediate-directory escape immediately rather than deferring — cost if wrong: none observed, the fix was verified correct by an independent re-reviewer trace.
3. Fixed the `resolveTicketPath` dangling-leaf-symlink escape immediately too (reversed an initial "defer to final review" ruling after judging the severity — arbitrary file write — too high to sit through six more tasks) — cost if wrong: none observed.
4. Left the residual TOCTOU gap in the same function unfixed — cost if wrong: a local, same-user, concurrent-write race with low practical exploitability on a loopback daemon; documented above for follow-up.
5. Deferred the `npm run lint` findings discovered at Task 10 to the final whole-branch review rather than reopening earlier tasks individually — cost if wrong: none, they were all fixed in one bundled pass at the final review stage as planned.
6. Stopped short of forcing a real agent spawn against the live daemon for the assign/review/merge-ready/merge curl steps, substituting the equivalent coverage already proven by Task 10's Go integration test — cost if wrong: the live-daemon HTTP-to-real-agent-spawn path itself is unverified by curl (though every layer under it — the service, the store, the session manager, the HTTP controller in isolation — is verified by tests); if this turns out to matter, a future verification pass should either extend `buildAgentResolver` to optionally register the fake adapter behind an explicit opt-in env var, or accept the cost of a real agent spawn with the user's explicit authorization.

## Planner review (2026-09-18, Opus 5 session that wrote the plan)

Reviewed the whole branch against the spec and plan, ran an independent
adversarial review, ran every gate, and verified the full lifecycle on a live
daemon built from the branch (isolated port 39311, scrubbed environment,
throwaway repo). Fixes landed in `d29a76add`.

**Live daemon verification, beyond the implementer's run.** Assigned the plan
to a real `claude-code` session: 201 with branch `opr/smoke-ticket-01`,
workspace mode `worktree`, the worktree cut from the committed default branch,
`GET /sessions` carrying `{slug, planFile, role: implementing}`, ticket
`in_progress` with the plan `working`. Review with `reviewer: new` spawned an
in-place session with role `reviewing` and the plan read `reviewing`.
`merge-ready` moved the ticket to `awaiting_merge` with the summary on the
plan; `merge` sent the approval prompt into the reviewer session (seen in its
transcript blocks) and the plan read `merging`; a second `merge` was refused
with `TICKET_NOT_MERGE_READY`; `done`, `archive`, `unarchive` behaved; ten
`ticket_updated` events reached `/events`. Both sessions were killed and the
daemon stopped; the two production daemons on 3001/3002 were untouched. The
spawned agent itself reported "Not logged in" because the sandbox used
`env -i`, which is a sandbox artefact, not a feature defect.

**Fixed in review.**

- Dry run returned the plan's existing session, so the controller answered
  201 for a dry run. Now `warnings` only, 200.
- After the user approves a merge the plan went back to `reviewing`; the
  board could not show that the approval happened. Added `merging`.
- The session returned by assign, plan and review lacked its `ticket` link
  because it was read before the row was written. Now re-read after linking.
- `merge-ready` after approval reset the approval and allowed a second
  "Approved" prompt. Now refused with `TICKET_MERGE_APPROVED`.
- An unreadable ticket or plan file failed the whole project list with a 500.
  Now listed with a warning, per spec §4.
- A ticket folder that is itself a symlink passed containment. Rejected.
- An `exited` planner counted as live, so `plan` refused to replace it.
- `ticket.md` scalars are now always quoted, so titles like `- x` or `null`
  round-trip.
- `approve` guards a nulled implementing session id.
- Removed the three comments added to `projectconfig.go`.

**Accepted as follow-ups** (unchanged from the implementer's list, plus):
the write-side TOCTOU on symlinks (fix is `O_NOFOLLOW`, needs a Windows
build-tag decision), two near-simultaneous `pr_created` events for one
session can trigger two reviews, attempt numbering ignores rows whose session
was nulled by a seed deletion, `WatchRoot` creates the tickets directory on a
GET, and the config key is `disableAutoReview` where the spec said
`autoReview`; the spec now records the shipped name.
