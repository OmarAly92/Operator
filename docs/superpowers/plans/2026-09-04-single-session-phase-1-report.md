# Single Session Kind, Phase 1 — Final Execution Report

Date: 2026-09-04
Branch: `feat/single-session-phase-1`
Worktree: `.worktrees/single-session-phase-1`
Status: all 16 tasks complete; not pushed or merged

## Outcome

Phase 1 now ships one session kind across the daemon, desktop, CLI, and mobile:

- every new session launches the agent's terminal UI;
- stale clients that send a session `mode` receive `400 SESSION_MODE_REMOVED`;
- desktop always renders the terminal;
- mobile routes every session to its terminal screen, opens covered harnesses in
  blocks view by default, and remembers the blocks/raw choice per session on the
  device;
- session-interface settings, transition routes, client controls, and the CLI
  `--mode` flag are removed;
- migration 0094 clears all pre-release application data except `app_settings`,
  while preserving the Goose ledger and SQLite sequences.

The ACP/chat implementation and legacy schema intentionally remain dormant and
compilable until Phase 4, as required by the design.

## Task 9 resolution

The plan's proposed flat SQL migration was unsafe for real profiles affected by
the historical burned migration versions 40–51: some tables are legitimately
absent there, and SQLite has no `DELETE FROM ... IF EXISTS`. Running the proposed
SQL would abort startup.

Migration 0094 is therefore a registered Goose Go migration. It runs inside the
Goose transaction, defers foreign-key checks until the transaction completes,
checks `sqlite_master` before deleting each known table, and uses only static SQL
statements. Its tests cover:

- a normal version-93 database;
- a burned-version database with physically missing tables;
- parent/child conversation branches with a self-referential `RESTRICT` key;
- foreign-key-safe delete ordering;
- every application table present at version 94, rather than only a copied test
  list;
- preservation of `app_settings`, migration 94's ledger row, and the
  `change_log` sequence.

Existing migration tests that asserted pre-release rows survived migration to
head were updated to assert the deliberate reset while retaining their schema
repair assertions. The append-only migration ledger now discovers both SQL and
registered Go migrations.

## Review fixes

The final audit found and fixed these issues:

1. The original delete order placed `conversation_branches` after referenced
   turns and `usage_sources` after referenced bindings.
2. Deleting a populated self-referential branch table failed its immediate
   `RESTRICT` constraint; migration 0094 now defers checks transactionally.
3. The obsolete Chat-only desktop e2e spec remained after Chat became
   unreachable.
4. Current architecture, status, and published landing documentation still
   described interface selection, Chat sessions, switching, and `--mode`.
5. The landing site had two stale logo import paths that prevented a production
   build; both paths now match the tracked `AOLogo` module.
6. Activity-confirmation polling discarded store and cancellation failures and
   reported success. The normal send path now propagates those failures, with a
   regression test. The legacy mutation path remains intentionally best-effort.

## Verification

All required gates are green on the completed worktree:

- `npm run lint` — all Go tests plus golangci-lint, 0 issues;
- backend `go build ./...`, `go test ./...`, and `go vet ./...`;
- SQLite migration package suite, including normal and burned-history reset
  cases;
- frontend typecheck, e2e typecheck, ESLint, 1,726 Vitest tests across 154 files,
  and the 102-entry desktop parity ledger;
- mobile `flutter analyze` and all 1,272 Flutter tests;
- landing production build, 71 static routes and 46 generated Markdown twins;
- `npm run api` and `npm run sqlc` regeneration;
- `git diff --check`.

Frontend ESLint still reports its existing warning baseline, but exits with zero
errors. No generated API or sqlc drift remains.
