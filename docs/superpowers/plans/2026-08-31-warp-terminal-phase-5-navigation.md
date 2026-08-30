# Warp Terminal Phase 5 — Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the scrollback navigable the way Warp's is — find, filter, bookmark, jump,
a sticky command header, the full block action menu, and a command palette that reaches
every one of them from the keyboard.

**Architecture:** Phase 1 built blocks and Phase 2 built the editor; both are addressable
but not *searchable*. The core already has the two primitives this phase needs —
`crates/vt-core/src/find.rs` (incremental, budgeted, cancellable) and
`crates/vt-core/src/block_selection.rs` — and **neither is exposed through
`vt-wasm`**, so no TypeScript can call them. Phase 5 is therefore one export task
followed by six UI tasks, not seven UI tasks.

**Tech Stack:** Rust (`vt-wasm` bindings), TypeScript (`ts/core`, `ts/renderer-dom`,
`ts/editor`), vitest, `@testing-library/dom`.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §6.4 (selection), §6.5 (find), §9.2 (virtualization), §9.4 (the perf gate), §10 (the editor), §14 Phase 5.

---

## Read this before starting: Phase 5 needs blocks to exist

Phase 5 operates on blocks. As of 2026-08-31 **the running app produces none**, because
spec §13.2 was never wired — see
[`2026-08-31-shell-blocks-daemon.md`](2026-08-31-shell-blocks-daemon.md). A find box over
an empty block list is a search field for a database with no rows, and every accept
criterion below would be vacuously true.

**Do not start this plan until Task 2 of the §13.2 plan is landed and a human has seen a
block in the running app.** The package's own tests and the smoke harness can drive
synthetic blocks, so the *code* here is testable in isolation — but "landed" is not the
same as "works", and this phase is where that distinction has already cost twice.

## The reusability constraint

`packages/terminal` is a **product-independent package** reused across the user's
projects; Operator is its first host, not its owner. Spec §4.1: "Operator's daemon is one
host; a plain PTY in another project is another."

Phase 5 is the phase most likely to violate this, because navigation UI wants product
chrome. Rules:

- Every string goes through `TerminalStrings` (`ts/core/src/types.ts`). No inline English
  in the package, no `react-i18next`.
- Every colour goes through `TerminalTheme`. No Operator design token reaches the package.
- Clipboard, links and notifications go through `HostCapabilities`. The palette must not
  reach for `navigator.clipboard` directly.
- The command palette lists **terminal** commands. It is not Operator's app-wide palette
  and must not know about sessions, projects or panes. If Operator wants its own entries
  in it, that is a host-supplied array, not a package import.
- Review gate for every task: *could a second, non-Operator host use this unchanged?*

## Global Constraints

- **No comments in code.** The user's global rule, test harnesses included.
- **No file over 600 lines** — `check:boundaries`. `dom-block-renderer.ts` is already the
  largest file in the package; do not grow it. New UI gets new files.
- `ts/editor` and `ts/renderer-dom` must not import `ts/completions` (§4.3). The same
  shape applies to whatever new module holds the palette: pick its home so the boundary
  checker stays satisfiable.
- Every task ends green on `npm --prefix packages/terminal test`,
  `npm --prefix frontend test`, `npm --prefix packages/terminal run check:boundaries`,
  and `cargo test` in `packages/terminal`.
- Do **not** expect `bench:gate` to be green. `input-latency` is red from the paint
  throttle in `ac9236563`; spec §9.5 carries that as an open decision. Note if a number
  moves. **Exception:** Task 1 adds a gate of its own and that one must be green.

## Warp references — verify at read time, never from memory

The reference checkout is `/Users/omaraly/development/AI/warp` (§17.1). The spec cites
`app/src/terminal/find/model/async_find.rs` for find (§6.5). The palette, filter, bookmark
and sticky-header counterparts are **not yet located** — find them yourself, cite
`file:line`, and add them to §17.4's citation index. Do not write a Warp citation you did
not open in this session; two earlier tasks in this project shipped a wrong "verified"
claim that way.

---

### Task 1: Expose find through `vt-wasm`, and pin its budget

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/{terminal-core.ts,types.ts,index.ts}`
- Create: `packages/terminal/ts/core/src/find.test.ts`
- Create: `packages/terminal/bench/find.bench.ts` (match the existing bench harness shape)

**The trap, named up front.** `FindCursor<'a>` borrows the grid, the row index and the
content (`crates/vt-core/src/find.rs:47-56`). A borrowing type cannot be handed across the
wasm boundary and held by JavaScript — `wasm_bindgen` will not accept it, and forcing it
through with a raw pointer is how you get a use-after-free the first time the core grows
the scrollback mid-search. Expose a **session handle** instead: an integer id owned by
`WasmTerminalCore`, with `find_open(query, is_regex) -> u32`, `find_step(id, budget)`,
`find_results(id)`, `find_is_complete(id)`, `find_cancel(id)`. The cursor is reconstructed
per call from the live grid, or stored owned — decide with a test that mutates the core
between two `find_step` calls and asserts no crash and no stale match.

Results cross as a flat `u32` array like every other export
(`blocks_ptr`/`blocks_len` at `crates/vt-wasm/src/lib.rs:296-300` is the pattern to copy).
Do not invent a second marshalling convention.

- [ ] **Step 1: Write the failing test.** Search a synthetic 5-block scrollback for a
  literal, assert `(BlockId, row, byte_range)` for each hit. Then an unparseable regex
  (`(unclosed`) — `find.rs:29` promises `Err`, never a panic; assert the TS side surfaces
  it as a rejected query and the terminal survives.
- [ ] **Step 2: Write the cancellation test.** Open a find, step once, cancel, step again,
  assert the result set did not grow. `find.rs:112` documents this contract.
- [ ] **Step 3: Write the mutation test** described above. This is the one that catches the
  borrow mistake.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: The gate.** §14 Phase 5's accept criterion is "find across a 500k-row
  scrollback returns first results under 100ms and is cancellable." Add a bench that builds
  a 500k-row scrollback and measures time-to-first-result. It must be green before Task 2.
  Choose the block budget per step from this measurement, not from taste — and write the
  measured number into the plan here when you have it.
- [ ] **Step 6: Sabotage check.** Set the budget to `usize::MAX` so one step scans
  everything. The gate must go red. If it does not, the gate is measuring the wrong thing.

---

### Task 2: The find bar

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/find-bar.{ts,test.ts}`
- Modify: `packages/terminal/ts/renderer-dom/src/{index.ts,styles.css,styles.ts}`
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`

- [ ] **Step 1: Write the failing test** — typing a query highlights matches in the
  rendered rows, `Enter`/`Shift-Enter` walk them, `Escape` closes and clears highlight.
- [ ] **Step 2: Drive it from the budget, not from a debounce.** Warp's find is async
  because the scrollback is large; the loop is step-render-step across frames. A
  `setTimeout` debounce is not the same thing and will make a 500k-row search feel like a
  hang followed by a dump.
- [ ] **Step 3: Respect virtualization (§9.2).** A match in a block that is not currently
  rendered must still be counted and must scroll into view when walked to. The naive
  implementation only highlights what is on screen and silently under-reports the count —
  test for a match below the fold explicitly.
- [ ] **Step 4: Strings and colours** through `TerminalStrings` / `TerminalTheme`.
  `searchHistory` and `searchNoMatches` already exist in `ts/core/src/types.ts`; add what
  is missing there rather than inlining.
- [ ] **Step 5: Verify.**

---

### Task 3: Sticky command header

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/{block-header.ts,viewport.ts}`
- Modify: the matching tests

When a block's output is taller than the viewport, its header pins to the top while the
block scrolls under it — so you always know which command produced what you are reading.

- [ ] **Step 1: Write the failing test** — scroll into the middle of a tall block, assert
  the pinned header names that block; scroll past its end, assert it hands over to the next.
- [ ] **Step 2: The trap.** The renderer uses `contain: strict` on the host and virtualized
  spacers. `position: sticky` does not survive an ancestor with `contain: paint`, and it
  cannot stick to a spacer that is not the block's real parent. Expect to position the
  header explicitly from the viewport's own scroll math rather than reaching for `sticky`;
  if `sticky` does work, prove it in the real-Chromium smoke harness, not in jsdom —
  **jsdom performs no layout and cannot prove a sticky position**, exactly as it could not
  prove the padding inset in the look-parity plan.
- [ ] **Step 3: Verify**, including `npm --prefix packages/terminal run smoke:vite`.

---

### Task 4: Jump-to-block and block-level keyboard navigation

**Files:**
- Modify: `packages/terminal/ts/editor/src/keymap.ts`
- Modify: `packages/terminal/ts/renderer-dom/src/viewport.ts`
- Modify: the matching tests

The renderer already has `scrollToBlock(id, align)` (`ts/core/src/types.ts:103`). This task
gives it keys and a current-block notion.

- [ ] **Step 1: Write the failing test** — previous/next block moves a focus ring and
  scrolls the block into view with the right alignment.
- [ ] **Step 2: The trap, and it is the same one as Phase 4.** The user's own answer on
  2026-08-31: *"Almost always agent panes and no completions when in agent panes tui."*
  Block navigation keys must be **inert whenever the alternate screen is active**, for the
  identical reason — those keys belong to the TUI. Write the alt-screen test first, the way
  Task 1 of the completions-wiring plan does, and make it the first assertion in the file so
  it cannot be quietly deleted later.
- [ ] **Step 3: Verify.**

---

### Task 5: Filter and bookmark

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/block-filter.{ts,test.ts}`
- Modify: `packages/terminal/crates/vt-core/src/block.rs` (a bookmark flag on `Block`)
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`

- [ ] **Step 1: Write the failing test** — filter to failed blocks only, assert the
  viewport renders those and the row space collapses; clear it, assert full restore.
- [ ] **Step 2: Filtering is a view, never an edit.** It must not evict, reorder or
  renumber blocks in the core. A filter that mutates the block grid is the resize
  duplication bug wearing a different hat: assert `BlockId`s are unchanged across a
  filter-and-clear cycle.
- [ ] **Step 3: Bookmarks are core state, so they survive a scroll** — but they are **not**
  persisted by the package. Persistence is a host concern (§4.1); expose them for the host
  to save, and let Phase 6's scrollback persistence own the storage.
- [ ] **Step 4: Verify.**

---

### Task 6: The full block action menu

**Files:**
- Modify: `packages/terminal/ts/renderer-dom/src/block-actions.{ts,test.ts}`

`block-actions.ts` today exports `RERUN_EVENT` and `renderBlockActions`. §12.2's string
table already names the intended set: copy command, copy output, rerun. Complete it —
copy both, share/save output, bookmark, filter-to-this-command, jump.

- [ ] **Step 1: Write the failing test** per action, asserting the `HostCapabilities` call
  or the emitted event, not the DOM shape.
- [ ] **Step 2: Every action is keyboard-reachable** — §14 Phase 5 makes this an accept
  criterion, not a nicety. Test it with keyboard events, not clicks.
- [ ] **Step 3: No action may run a command.** §3.6 is structural: `HostCapabilities` has
  no capability that can execute anything, and "rerun" means *write bytes to the
  transport*, which is the user's own shell doing it. Keep it that way.
- [ ] **Step 4: Verify.**

---

### Task 7: The command palette

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/palette.{ts,test.ts}` (or its own module
  if `check:boundaries` objects — decide before writing)
- Modify: `packages/terminal/ts/editor/src/keymap.ts`
- Modify: `packages/terminal/ts/core/src/types.ts` (the command registry type)

- [ ] **Step 1: Write the failing test** — open, type, arrow, `Enter` runs the command;
  `Escape` closes and returns focus exactly where it was.
- [ ] **Step 2: Reuse the ranking that already exists.** Phase 4 built a scorer in
  `ts/completions/src/rank.ts` and it is the package's fuzzy-match answer. But
  `ts/renderer-dom` **may not import `ts/completions`** (§4.3). Either lift the scorer into
  a shared module both may import, or give the palette a prefix match. Do **not** copy the
  scorer — a second copy will drift, and this package has already paid for one duplicated
  source of truth this month.
- [ ] **Step 3: The command list is host-extensible but package-owned.** The package
  registers its own commands (find, filter, bookmark, jump, the block actions); the host may
  append entries. The package must not know what a host entry does beyond calling its
  callback.
- [ ] **Step 4: Inert in the alternate screen**, same rule as Task 4.
- [ ] **Step 5: Verify.**

---

### Task 8: Record it

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` — §6.5, §14
  Phase 5, §17.4
- Modify: `packages/terminal/README.md`

- [ ] **Step 1:** Mark Phase 5 landed with its deviations stated plainly, in the shape
  Phases 3 and 4 already use. A deviation recorded is cheap; a deviation discovered later
  costs a session.
- [ ] **Step 2:** Add the measured find numbers (time-to-first-result at 500k rows, the
  chosen block budget) to §6.5, so the next person changing the budget knows what it was
  chosen against.
- [ ] **Step 3:** Add the Warp citations you verified to §17.4.

---

## Accept when

1. Find across a **500k-row** scrollback returns first results **under 100ms** and is
   cancellable — measured by the Task 1 bench, in CI, not by feel.
2. A match in a block below the fold is counted and scrolls into view when walked to.
3. Every block action and every palette command is reachable **from the keyboard alone**.
4. Find, filter, bookmark, jump and the palette are all **inert while the alternate screen
   is active**.
5. A filter-and-clear cycle leaves every `BlockId` unchanged.
6. `check:boundaries` is green and `dom-block-renderer.ts` did not grow past 600 lines.
7. The package gained no Operator string, colour, or concept.
8. `smoke:vite` is green — it is the only harness that performs layout, and Task 3 depends
   on layout.
