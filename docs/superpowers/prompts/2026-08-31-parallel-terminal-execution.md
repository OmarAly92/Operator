# Parallel execution prompts — 2026-08-31

Two plans run concurrently in separate git worktrees, each in a cleared session,
each using subagent-driven execution. Reviewed and merged by the orchestrating
session, not pushed by the agents.

| Agent | Plan | Scope |
| --- | --- | --- |
| A | `2026-08-31-shell-blocks-daemon.md` (§13.2) | `backend/**`, `packages/terminal/{go,protocol,shell}/**`, `spawn-recipe.ts`, `BlockTerminal.tsx`, spec §13 + §15 |
| B | `2026-08-31-warp-terminal-phase-5-navigation.md` | `packages/terminal/{crates,ts/renderer-dom,ts/editor,ts/react,bench}/**`, `ts/core/src/{terminal-core,types,index}.ts`, spec §6.5 / §14 Phase 5 / §17.4 |

## Why these can run in parallel

Mechanical overlap is small: A is backend and Go, B is Rust and renderer TypeScript.
The only shared files are `ts/core/src/{types,index}.ts` (append-shaped) and the spec,
which is split by disjoint section assignment above.

The dependency between them is about **verification**, not implementation. Phase 5's
plan opens with "do not start until §13.2 Task 2 lands" — that gate concerns the final
human check in the running app. Phase 5's code is testable against synthetic blocks in
the package's own tests and the Chromium smoke harness, so agent B is told to proceed
through all 8 tasks and to state plainly that end-to-end verification is not done.

## Shared clauses (both prompts)

- **No comments in code**, test files and scaffolding included.
- **`packages/terminal` is product-independent.** Operator is its first host, not its
  owner (spec §4.1). Review gate on every file: could a second, non-Operator host use
  this unchanged?
- **Do not push.** Commit to the branch; the orchestrating session reviews and merges.
- **Fresh worktree** — no `node_modules`; install before testing.
- **`bench:gate` is expected RED** on `input-latency` (paint throttle in `ac9236563`,
  spec §9.5 open decision). Do not fix it; note if a number moves.
- **Sabotage every test**: write the test, break the implementation, confirm red. A green
  suite proves nothing about behaviour the tests do not exercise — 281 passing tests
  recently hid three real bugs here.
- **Warp citations must be opened in-session**, cited `file:line`. Never from memory.
- **If the plan is wrong about a load-bearing fact, stop and report with evidence.**
  Do not silently work around it.
- Concurrent `smoke:vite` runs may contend for a port; retry rather than concluding the
  harness is broken.

## Agent A — additional clauses

- **All app state under `~/.operator`** (`OPERATOR_DATA_DIR` / `OPERATOR_RUN_FILE`).
  Never an OS-default app-data location. Task 1 materializes shell scripts to disk: the
  data dir is **injected**, never read from the env var inside a service.
- **Task 2's accept criterion is behavioural and it is the one that matters.** Build,
  run the app, open a shell terminal, type `ls`, confirm a block with a header appears —
  not a bare grid. If no block appears, STOP and report; Tasks 3-8 will not fix it.
- Read spec §4.1, §7.2, §8, §13.1, §13.2, §13.3 before Task 1. §13.3 already landed and
  decided that live blocks come from the renderer's own parse, not from the daemon — that
  is why Task 2 is the visible win.

## Agent B — additional clauses

- **The plan's stop sign does not apply** — proceed through all 8 tasks; agent A is
  landing §13.2 in parallel. Do not claim end-to-end verification.
- **The load-bearing trap, stated up front:** `FindCursor<'a>` borrows the grid, the row
  index and the content (`crates/vt-core/src/find.rs:47-56`). A borrowing type cannot
  cross the wasm boundary and be held by JavaScript; forcing it through with a raw
  pointer is a use-after-free the first time the scrollback grows mid-search. Expose a
  session handle owned by `WasmTerminalCore`.
- **`ts/editor` and `ts/renderer-dom` may not import `ts/completions`** (§4.3). This
  bites in Task 7: the palette wants the Phase 4 scorer and may not import it. Lift it to
  a shared module or use a prefix match — do not copy it.
- **jsdom performs no layout.** It cannot prove a sticky position or any computed
  geometry. Task 3 depends on layout: prove it in `smoke:vite`. A jsdom test claiming to
  verify layout is worse than no test — that exact mistake already shipped here once.
- **Alt-screen inertness is a hard requirement.** The user works almost entirely in agent
  panes, which are alternate-screen TUIs: "no completions when in agent panes tui." The
  same rule binds Task 4's navigation keys and Task 7's palette. Write the alt-screen test
  first in each file so it cannot be quietly deleted.
- Pick Task 1's block budget from the **measurement**, not from taste, and write the
  measured number into the plan.

## Report format required of both

Which tasks landed; commit shas; what was verified by hand versus by test; the Warp
citations actually opened; any deviation from the plan and why; and explicitly what is
NOT done.
