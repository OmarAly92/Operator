You are implementing a written plan in the Operator repository.

Your working directory is a dedicated git worktree on branch `phase-5-navigation`. A second agent is working in parallel in `/Users/omaraly/development/AI/Operator-shell-blocks` on a different plan; stay inside your file scope (below) so the two branches merge cleanly.

## Your task

Execute, task by task:

`docs/superpowers/plans/2026-08-31-warp-terminal-phase-5-navigation.md`

Read it in full before starting. It is 8 tasks with checkbox steps, and it already contains the verified evidence, the named traps and the accept criteria. Do not re-derive what it establishes.

REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (preferred) or `superpowers:executing-plans`. Invoke the skill before doing anything else.

## Read this first — the plan's stop sign does not apply to you

The plan opens by saying "do not start until §13.2 Task 2 lands and a human has seen a block in the running app." **That gate is about final human verification, not about implementation**, and it is being handled: the other agent is landing §13.2 in parallel right now.

**Proceed with all 8 tasks.** The package's own tests and the Chromium smoke harness drive synthetic blocks, so every task here is implementable and unit-testable without §13.2. What you must NOT do is claim the phase is verified end-to-end in the running app — you cannot check that yet, and you must say so plainly in your report rather than papering over it.

## Context the plan does not carry

**What this is.** Operator is rebuilding its terminal to be functionally and visually identical to Warp, as a monorepo package at `packages/terminal`. Spec phases 0-4 have landed. Phase 5 is navigation: find, filter, bookmark, jump-to-block, a sticky command header, the full block action menu, and a command palette.

**The phase is smaller than it reads.** The core already contains `crates/vt-core/src/find.rs` (incremental, budgeted, cancellable) and `crates/vt-core/src/block_selection.rs`, both written and tested — and **neither is exposed through `vt-wasm`**, so no TypeScript can reach them. Task 1 is that export; Tasks 2-7 are UI on top of it.

**The spec is the authority:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`. Read §4.1 (host boundary), §4.3 (import enforcement), §6.4 (selection), §6.5 (find), §9.2 (virtualization), §9.4 (the perf gate), §10 (the editor) and §14 Phase 5 before Task 1.

**Warp reference checkout:** `/Users/omaraly/development/AI/warp`. The spec cites `app/src/terminal/find/model/async_find.rs` for find. The palette, filter, bookmark and sticky-header counterparts are **not yet located** — find them, cite `file:line` from what you actually opened in this session, and add them to spec §17.4. **Never write a Warp citation you did not read in this session.** Two earlier tasks here shipped a wrong "verified" claim that way.

## The load-bearing trap, stated up front

`FindCursor<'a>` borrows the grid, the row index and the content (`crates/vt-core/src/find.rs:47-56`). A borrowing type cannot cross the wasm boundary and be held by JavaScript — `wasm_bindgen` will not accept it, and forcing it through with a raw pointer gives you a use-after-free the first time the core grows the scrollback mid-search. Expose a **session handle** (an integer id owned by `WasmTerminalCore`) instead. Task 1 specifies the shape and the test that catches this.

## Hard rules, non-negotiable

1. **No comments in code.** The user's global rule. It applies to test files, scaffolding and harnesses too. Explain in commit messages, never in code.
2. **`packages/terminal` is a product-independent package.** Operator is its first host, not its owner. Spec §4.1: "Operator's daemon is one host; a plain PTY in another project is another." **Phase 5 is the phase most likely to violate this**, because navigation UI wants product chrome. Every string goes through `TerminalStrings`; every colour through `TerminalTheme`; clipboard, links and notifications through `HostCapabilities`. The command palette lists **terminal** commands — it is not Operator's app-wide palette and must not know about sessions, projects or panes; host entries are a supplied array, not an import. Review gate for every file: *could a second, non-Operator host use this unchanged?*
3. **`ts/editor` and `ts/renderer-dom` must not import `ts/completions`** (spec §4.3, enforced by `check:boundaries`). This bites in Task 7: the palette wants the Phase 4 scorer at `ts/completions/src/rank.ts` and may not import it. Lift it to a shared module both may import, or use a prefix match. **Do not copy it** — a second copy will drift, and this package has already paid for one duplicated source of truth this month.
4. **No file over 600 lines.** `dom-block-renderer.ts` is already the largest file in the package. Do not grow it; new UI gets new files.
5. **Do not push.** Commit to `phase-5-navigation` only. The user reviews and merges.

## Your file scope

**Yours:** `packages/terminal/crates/**`, `packages/terminal/ts/renderer-dom/**`, `packages/terminal/ts/editor/**`, `packages/terminal/ts/react/**`, `packages/terminal/bench/**`, `packages/terminal/ts/core/src/{terminal-core,types,index}.ts`, `packages/terminal/README.md`, and in the spec **only §6.5, §14 Phase 5 and §17.4**.

**Not yours — the other agent owns them:** `backend/**`, `packages/terminal/go/**`, `packages/terminal/protocol/**`, `packages/terminal/shell/**`, `packages/terminal/ts/core/src/spawn-recipe.ts`, `frontend/src/renderer/components/BlockTerminal.tsx`, and spec §13 / §15. If you believe you need one of those, **stop and report it** rather than doing it.

## Environment

- Fresh worktree: `packages/terminal` and `frontend` have no `node_modules`. Install before running tests.
- The other agent may run `npm --prefix packages/terminal run smoke:vite` concurrently. If a port is in use, that is why — retry rather than concluding the harness is broken.
- `bench:gate` is expected **RED** on `input-latency` (a paint throttle in `ac9236563`; spec §9.5 carries it as an open decision). Do not try to fix it. Note if a number moves. **Exception:** the find bench you add in Task 1 is a gate of its own and must be green.

## Green means

`npm --prefix packages/terminal test`, `npm --prefix frontend test`, `npm --prefix packages/terminal run check:boundaries`, and `cargo test` in `packages/terminal`.

## Method

- Prove each diagnosis empirically before writing the fix. Run code; do not review it and assume.
- After writing a test, **sabotage the implementation and confirm the test goes red.** A green suite proves nothing about behaviour the tests do not exercise — 281 passing tests recently hid three real bugs in this repository.
- **jsdom performs no layout.** It cannot prove a sticky position, an inset, or any computed geometry. Task 3 depends on layout, so prove it in the real-Chromium harness (`npm --prefix packages/terminal run smoke:vite`). A jsdom test that claims to verify layout is worse than no test — that exact mistake already shipped here once.
- Task 1's 500k-row find gate: pick the block budget from the **measurement**, not from taste, and write the measured number into the plan.
- **Alt-screen inertness is a hard requirement, not a nicety.** The user works almost entirely in agent panes, which are alternate-screen TUIs, and stated it directly: "no completions when in agent panes tui." The same rule binds Task 4's block-navigation keys and Task 7's palette — those keys belong to the TUI. Write the alt-screen test **first** in each file so it cannot be quietly deleted later.
- If the plan is wrong about a load-bearing fact, say so with evidence and stop. Do not silently work around it.

## Report back

Which tasks landed; the commit shas on your branch; the measured find numbers; what you verified by test versus by the Chromium smoke harness; the Warp citations you actually opened; any deviation from the plan and why. State explicitly that end-to-end verification in the running app is **not** done, and why.
