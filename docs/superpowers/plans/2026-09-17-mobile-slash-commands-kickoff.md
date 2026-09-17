# Kickoff prompt — mobile slash commands

Paste everything below the line into a fresh Claude Code session opened at
`/Users/omaraly/development/AI/Operator`.

---

Implement the plan at `docs/superpowers/plans/2026-09-17-mobile-slash-commands.md`
using **superpowers:subagent-driven-development**, in an **isolated git
worktree**. The plan argues from
`docs/superpowers/specs/2026-09-17-mobile-slash-commands-design.md`; read both
end to end before dispatching anything, and give every implementer subagent
both paths plus its task's full text.

## Worktree first

Use `superpowers:using-git-worktrees`. The worktree must be **outside** this
checkout: `.worktrees/` and `.claude/worktrees/` inside the repo poison
repo-wide search (see `CLAUDE.md`, "Nested worktrees poison repo-wide search").

The worktree already exists at `/Users/omaraly/development/AI/Operator-slash-commands`
on branch `feat/mobile-slash-commands`; `cd` there, confirm `git status` is
clean and `git log --oneline -1` shows the docs commit that added Tasks
10–11, and do not create another. Never commit to `master`. Toolchains are
already bootstrapped there; if `go test ./...` complains about modules, run:

```bash
cd ../Operator-slash-commands/packages/mobile && flutter pub get
cd ../../frontend && npm ci
```

(`frontend` is needed only for Task 5's `npm run api:ts`; Go needs nothing.)

## Execution rules

- Tasks 1–9 are done and verified on `feat/mobile-slash-commands` (worktree
  `../Operator-slash-commands`). This round is **Tasks 10 and 11 only**, on
  that same branch and worktree: one fresh implementer subagent per task, in
  order. Task 11 Step 6 is the reviewing session's; stop after Step 5 and
  report.
- Each task is TDD as written: the failing test first, watch it fail, then
  the implementation, then the gate, then one commit. Do not batch tasks into
  one commit and do not skip the "verify it fails" step.
- Between tasks run the two-stage review the skill prescribes (spec
  compliance, then code quality) with fresh reviewer subagents. A task is not
  done until its reviewer passes it.
- Gates, run from the worktree, must be clean before each commit:
  - Go: `cd backend && gofmt -l internal && go vet ./... && go test ./...`
  - Mobile: `cd packages/mobile && flutter analyze` (must print
    `No issues found!`) and `flutter test`.
  - Task 5 additionally: `go generate ./internal/httpd/apispec/` and
    `cd frontend && npm run api:ts`, committing both `openapi.yaml` and
    `frontend/src/api/schema.ts` (CI diffs the latter, `.github/workflows/go.yml:97`).
- Commit trailer: the `Co-Authored-By` line your own attribution reminder
  gives. Do not copy a model name from any document.

## Repo rules the subagents must be told

- **No comments in code.** The user's global rule. The only exception is a
  load-bearing comment that already exists in a file the task edits and that
  the change makes wrong; update it rather than leaving it stale. The plan
  marks the one such spot (the `harnessNudgeSafe` comment in `manager.go`).
- `AGENTS.md` governs `backend/` and `frontend/`; the `packages/mobile`
  section of `CLAUDE.md` governs the phone. Read the mobile section: Cubit
  only, hand-written models with all fields nullable, one params class per
  method, `EndPoints` static methods for parameterised paths, no
  `flutter_screenutil` in feature code, `context.skin` and `AppTextStyle.*`
  for looks, inline English copy.
- The mobile cubit fetches in its constructor (package convention; the plan
  explains why the tests `skip: 1`). Do not move the fetch to the router.
- The daemon's `slashcommands` catalogue is plain data; do not "improve" the
  descriptions or add commands beyond the table in the spec.
- Where the plan says "check the real name" it has already been verified:
  `domain.HarnessClaudeCode`, `domain.SessionMetadata`, `fakeMessenger.msgs
  []string`, `AppText(maxLines:, overflow:)`, `AppInkWell(onTap:)`,
  `skin.textFaint`, `GlobalResponse(data:)` all exist as named.
- Two things in the spec are marked **not known** (whether custom commands
  fire the submit hook; whether `/doctor` and `/export` open a dialog).
  They are settled by Task 9, not by guessing; implement exactly what the
  plan says.
- Never run `npm run tauri:dev`, the daemon, or a Flutter app from a
  subagent. Tests only.

## What to report at the end

A short report containing, in order:

1. The worktree path and branch, and `git log --oneline development..HEAD`.
2. For each task: commit hash, the gate output's last line, and the
   reviewer's verdict in one line.
3. Anything a reviewer flagged that you chose not to change, with the reason.
4. Anything the plan turned out to be wrong about (a name that did not
   exist, a test that could not be written as given), and what you did instead.
5. The exact commands the reviewing session should run to re-verify
   (`go test ./...`, `flutter test`, and the codegen drift check).

Do not merge, rebase, or push. The reviewing session takes the branch from
here.
