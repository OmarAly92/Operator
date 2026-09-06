Execute the Phase 4 implementation plan: remove the ACP/Chat subsystem from Operator.

## Start here

Read these two documents in full before doing anything else:

- Plan: `docs/superpowers/plans/2026-09-06-phase-4-delete-acp.md` — 13 tasks, 76 checkboxes
- Spec it implements: `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`, section "Phase 4 — delete ACP" (line 601)

Then read `AGENTS.md` and `CLAUDE.md` at the repo root. `AGENTS.md` covers `backend/` and `frontend/`; `CLAUDE.md` covers `packages/mobile`.

## Execution method

Use **superpowers:subagent-driven-development**. One fresh subagent per task, two-stage review between tasks. Do not batch tasks into one agent — this is a 13-task deletion where the whole safety property is that each commit builds and each task is independently rejectable.

Work in a git worktree via **superpowers:using-git-worktrees**. Branch from `master` at `dc4ed73de`.

Tick each `- [ ]` checkbox in the plan file as its step completes, and commit the plan file's checkbox updates along with the task's own commit.

## Repository state as of dispatch

- Repo: `/Users/omaraly/development/AI/Operator`, branch `master`, HEAD `dc4ed73de`, working tree clean, `origin/master` in sync.
- Go 1.25.12, golangci-lint 2.12.2, Flutter 3.44.5.
- **Mobile test baseline: 1400 tests, all passing.** Verified at HEAD.
- Backend: `go test ./...` green, `npm run lint` reports 0 issues.
- Both live databases are at goose version 100 and have `conversations = 0` and `session_interface_transitions = 0`.

## Hard rules

1. **No comments.** The user's global instruction: never add explanatory comments to code. Deleting a commented block removes its comments with it — that is expected and fine.

2. **`golangci-lint` produces phantom failures from a stale cache.** Nested worktrees under `.worktrees/` and `.claude/worktrees/` leave deleted paths in its cache, and it will report issues in files that do not exist. If that happens, run `golangci-lint cache clean` and re-run. **Only the post-clean result counts.** This has bitten three previous agents in this repo; do not spend time debugging a phantom.

3. **Repo-wide `grep`/`find` from the root is unreliable.** `.worktrees/`, `.claude/worktrees/` and sibling `../Operator-*` checkouts hold stale duplicate copies of tracked files, including old `AGENTS.md` versions. Scope every search to `backend/`, `frontend/src/`, `packages/mobile/lib/`, `packages/mobile/test/`, `.github/` — or exclude those paths explicitly. A grep that "finds a remaining reference" in a worktree path is a false positive.

4. **Use the repo's script wrappers, not raw tools.** `npm run lint` (root) = backend `go test ./...` + golangci-lint. `npm run sqlc`, `npm run api`. From `frontend/`: `npm run typecheck`, `npm run lint`, `npm test`. **`frontend` has no `build` script** — do not invent one.

5. **`flutter analyze` must print exactly `No issues found!`.** Warnings are failures.

6. **Do not refactor while deleting.** No renames, no reformatting, no "while I'm here" improvements. A deletion diff that also moves code is unreviewable. The one exception is Tasks 1 and 2, which are explicitly `git mv` moves — keep those byte-identical apart from import paths.

7. **Fix dangling references by deletion, never by stubbing.** If the compiler complains that a branch is now unreachable, delete the branch — do not leave `if true`, a no-op function, or a parameter that is now always one value.

8. **Never restart the Operator daemon from your shell.** An agent shell leaks `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_MESSAGING_SOCKET`, `ANTHROPIC_BASE_URL` and about thirty other variables into any agent the daemon spawns, and the spawned agent dies within 300ms. Live verification is the user's step — see "Where to stop" below.

## The three seams that will break a naive deletion

Tasks 1–3 exist because `packages/mobile/lib/feature/chat/` contains code that is **live and has nothing to do with chat**. Do not skip or reorder them:

- **`chat/voice/`** (7 files, 862 lines) is the dictation subsystem driving the vendored `speech_to_text` fork. `terminal_composer.dart` imports it. Task 1 moves it to `lib/feature/dictation/`.
- **`chat/logic/keyboard_inset.dart`** (6 lines) is imported by `terminal_body.dart`. Task 2 moves it to `lib/core/utils/`.
- **`blocks/logic/block_actions.dart` and `turn_grouping.dart`** each serve both the live blocks view and the chat timeline, and import chat models for the chat half only. Task 3 cuts the chat half.

Task 3 Step 2 is a **stop-and-report gate**: if the live block widgets turn out to reference conversation types, the seam is not where the plan says it is — stop and report rather than improvising.

## Expectations that look like failures but are not

- **The mobile test count will drop** in Tasks 3 and 4 as chat tests are deleted. That is correct. What matters is that the drop equals the tests you deliberately removed, and that Tasks 1 and 2 (pure moves) change the count by **zero**.
- **`frontend/src/api/schema.ts` still contains conversation types after Task 5.** It is regenerated in Task 6. Do not hand-edit it.
- **`gofmt` may realign a map in `migrate_burned_versions_test.go`** in Task 12 when the version keys change width. That whitespace churn belongs in that commit.

## Task 12 — the irreversible one, and what is actually irreversible

Task 12 writes migration `0101_drop_conversations.sql` and verifies it against a **copy** of a live database in `/tmp`. Writing and testing the migration is safe; you may do it without asking.

What is irreversible is a real daemon later applying it. The down migration is deliberately inert (`SELECT 1`) because the spec records Phase 4 as unrecoverable — do not "improve" it into something that recreates the tables. That would be a false promise of recoverability.

Task 12 Step 1 is a **stop-and-report gate**: if any live database has non-zero rows in `conversations` or `session_interface_transitions`, stop. Do not drop real data.

## Where to stop

Complete Tasks 1 through 13, **with two exceptions**:

- **Task 13 Step 7 (live verification) is the user's step.** It needs the daemon restarted from the desktop app. Leave the checkbox unticked, and say clearly in your report that it is outstanding and why.
- **Do not merge to `master`, do not push, do not open a PR.** Stop on the branch and report. The user reviews first, then decides.

Leave the worktree in place so the review can run against it.

## Deliverable

`docs/superpowers/plans/2026-09-06-phase-4-report.md`, per Task 13 Step 4, containing:

- Measured lines deleted per area (backend, desktop, mobile, build) — real `git diff --shortstat` numbers, not the plan's estimates
- The verbatim output of every gate in Task 13 Step 2
- The Task 12 Step 5 migration verification output
- Every place the plan turned out to be wrong, and what you did instead
- Any checkbox left unticked, and why

**No placeholders.** No "TBD", no "verified" without the output that verifies it. If something could not be done, say so plainly rather than describing what would have happened.

## Review contract

Your work will be reviewed independently and in detail — the reviewer re-runs the gates themselves rather than reading your report, checks that no pre-existing test was weakened or deleted to make the suite pass, and reads the actual diffs of any test file that shows deletions. Three specific things will be checked:

1. That Tasks 1 and 2 are genuinely verbatim moves (`git log --follow` should show the history, and the file contents should differ only in import paths).
2. That the "fix by deletion, never by stubbing" rule held — a search for `if true`, unused parameters, and functions that now just return a constant.
3. That `npm run api` produces an **empty** diff at the end, proving Task 6 actually regenerated the contract rather than deleting routes and leaving the spec stale.

Report honestly. A task you could not finish is a fine outcome; a task reported as finished that was not is the one thing that wastes everyone's time.
