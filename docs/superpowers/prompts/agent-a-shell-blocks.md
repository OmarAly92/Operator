You are implementing a written plan in the Operator repository.

Your working directory is a dedicated git worktree on branch `shell-blocks-daemon`. A second agent is working in parallel in `/Users/omaraly/development/AI/Operator-phase-5` on a different plan; stay inside your file scope (below) so the two branches merge cleanly.

## Your task

Execute, task by task:

`docs/superpowers/plans/2026-08-31-shell-blocks-daemon.md`

Read it in full before starting. It is 8 tasks with checkbox steps, and it already contains the verified evidence, the design decisions, the named traps and the accept criteria. Do not re-derive what it establishes.

REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (preferred) or `superpowers:executing-plans`. Invoke the skill before doing anything else.

## Context the plan does not carry

**What this is.** Operator is rebuilding its terminal to be functionally and visually identical to Warp, as a monorepo package at `packages/terminal`. Spec phases 0-4 have all landed. The terminal still does not look like Warp in the running app, and the reason — verified, not guessed — is that spec §13.2 ("the daemon's job") was never wired. Nothing calls `spawnRecipe`, nothing runs `tmux pipe-pane`, nothing imports `packages/terminal/go/marks`. The consumer side (`blockevent` service, its sqlite store, its HTTP controller, `Manager.PublishBlockEvent`) is fully built and tested. **You are building the producer.**

**The spec is the authority:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`. Read §4.1, §7.2, §8, §13.1, §13.2 and §13.3 before Task 1. §13.3 matters most: it already landed, and it decided that *live* blocks come from the renderer's own parse of the stream it already receives — not from the daemon. That is why the plan says Task 2 is the visible win and is small.

**Warp reference checkout:** `/Users/omaraly/development/AI/warp`. If you cite Warp, open the file and cite `file:line` from what you read in this session. Never cite from memory — wrong "verified" claims have already cost this project real time.

## Hard rules, non-negotiable

1. **No comments in code.** The user's global rule. It applies to test files, scaffolding and harnesses too. Explain in commit messages and in the plan, never in code.
2. **All app state resolves under `~/.operator`** (overridable via `OPERATOR_DATA_DIR` / `OPERATOR_RUN_FILE`). Never `~/Library/Application Support` or any OS-default app-data location. Task 1 materializes shell scripts to disk: the data dir must be **injected**, never read from the env var inside a service — that would bypass `OPERATOR_DATA_DIR` overrides in tests.
3. **`packages/terminal` is a product-independent package.** Operator is its first host, not its owner. Spec §4.1 states it: "Operator's daemon is one host; a plain PTY in another project is another." Nothing Operator-shaped may enter the package — no tmux, no session id, no `blockevent`, no mux channel, no `~/.operator` path, no daemon concept. Everything Operator-specific lives in `backend/`. Review gate for every file you touch: *could a second, non-Operator host use this unchanged?*
4. **No file over 600 lines** in `packages/terminal` (`check:boundaries` enforces it).
5. **Do not push.** Commit to `shell-blocks-daemon` only. The user reviews and merges.

## Your file scope

**Yours:** `backend/**`, `packages/terminal/go/**`, `packages/terminal/protocol/**`, `packages/terminal/shell/**`, `packages/terminal/ts/core/src/spawn-recipe.ts` and its test, `frontend/src/renderer/components/BlockTerminal.tsx`, and in the spec **only §13** (§13.1, §13.2) plus one line in §15.

**Not yours — the other agent owns them:** `packages/terminal/crates/**`, `packages/terminal/ts/renderer-dom/**`, `packages/terminal/ts/editor/**`, `packages/terminal/ts/react/**`, `packages/terminal/bench/**`, and spec §6.5 / §14 Phase 5 / §17.4. If you believe you need to change one of those, **stop and report it** rather than doing it.

## Environment

- Fresh worktree: `backend`, `frontend`, `packages/terminal` have no `node_modules`. Install before running tests.
- The other agent may run `npm --prefix packages/terminal run smoke:vite` concurrently. If a port is in use, that is why — retry rather than concluding the harness is broken.
- `bench:gate` is expected **RED** on `input-latency` (a paint throttle in `ac9236563`; spec §9.5 carries it as an open decision). Do not try to fix it. Note if a number moves.

## Green means

`cd backend && go test ./...`, `npm --prefix packages/terminal test`, `npm --prefix frontend test`, `npm --prefix packages/terminal run check:boundaries`.

## Method

- Prove each diagnosis empirically before writing the fix. Run code; do not review it and assume.
- After writing a test, **sabotage the implementation and confirm the test goes red.** A green suite proves nothing about behaviour the tests do not exercise — 281 passing tests recently hid three real bugs in this repository.
- **Task 2's accept criterion is behavioural and it is the one that matters.** Build, run the app, open a shell terminal, type `ls`, and confirm you see a **block with a header** — not a bare grid. If no block appears, **STOP and report**. Tasks 3-8 will not fix it.
- If the plan is wrong about a load-bearing fact, say so with evidence and stop. Do not silently work around it. Its claims were verified on 2026-08-31, but it is not infallible.

## Report back

Which tasks landed; the commit shas on your branch; what you verified **by hand** versus by test; any deviation from the plan and why; and — explicitly — anything you could not do.
