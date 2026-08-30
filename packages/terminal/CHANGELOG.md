# Changelog

## 0.3.0 - 2026-08-30

Phase 2 replaces shell line editing with the package-owned editor and prompt row.

- Explicit `input-ready` and `input-released` marks drive `Unknown`, `Owned`, and
  `Released` states without an ownership timer.
- The DOM editor provides multi-line editing, syntax highlighting, mark-derived
  history, ghost text, Ctrl-R reverse search, and edit-and-rerun.
- Prompt suppression lands with the prompt row and remains reversible through the
  show-shell-prompt option.
- Additive zsh, bash, and fish bootstraps emit ownership marks; fish keeps its own
  OSC 133 enabled.
- Operator mounts the editor below the block list, sends submitted text with one
  newline, preserves raw passthrough outside `Owned`, and hides the editor in the
  alternate screen.
- The Phase 2 perf gate passes against the xterm baseline: large-output median
  49,063,386 B/s, vtebench median 4.801 workloads/s, input p95 8.60 ms, and the
  50,000-block scroll p95 13.40 ms with 20 live blocks.

## 0.2.0 - 2026-08-29

Phase 1a: the block-aware core, the mark protocol, and the slice of
features that proves the package can hold blocks through a real session.

- **Block-aware core over the row index.** `vt-core` now layers a
  `BlockGrid` and a `BlockTree` (a leaf-with-summary tree, the "sum
  tree") on top of the append-and-wrap parser. Every `feed` reopens
  the same block the row index was already tracking, so blocks are
  never a second source of truth for terminal state.
- **Mark protocol with two decoders against shared vectors.** The
  `terminal-marks` crate owns the Tier 1 (OSC 133) and Tier 2 (OSC
  7000) grammars, with a tolerant recovery table for the OSC 133
  sequence states. A Go decoder at `go/marks/` decodes the same
  feed-only Tier 1 grammar for the daemon side, and both decoders
  pass the same 16 JSON vectors under
  `protocol/vectors/`. The closed event vocabulary and tolerant
  recovery rules are pinned in `protocol/SPEC.md`.
- **Blocks formed from marks and tracked through the alt screen.**
  The block formation logic reads OSC 133 (and the OSC 7000
  extension) and surfaces the block list through the existing
  `CoreSnapshot`. The alt screen is a tracked state: marks
  observed between enter and leave do not change the block list,
  and leaving the alt screen resumes from the last block seen
  outside it.
- **Block-coordinate selection.** Selections are now
  `(block_id, anchor, head)` instead of raw `(row, col)` pairs,
  so a selection that straddles a block boundary resolves
  cleanly after the grid is trimmed.
- **Incremental find engine.** The find engine indexes blocks as
  they are produced and serves the next match in O(log n) per
  step. A small "block i owns row i" fallback covers the case
  where a block is observed before its rows are flushed, which
  is a known timing workaround (see "Known costs" below).
- **Additive-only zsh bootstrap.** The `shell/zsh.sh` bootstrap
  installs precmd / preexec hooks and the OSC 7000 extension
  emission. It sources on top of any user config, never rebinds
  any key, is idempotent under a second source, and never touches
  the user's prompt string. The `spawn-recipe` runtime rejects
  `suppressPrompt: true` so a future caller cannot take prompt
  suppression by accident.
- **Package-level guardrails stay green.** `check:boundaries`
  still rejects any import that escapes `packages/terminal/`,
  the forbidden package edges, any source file over 600 lines,
  and any Cargo or Go replacement that resolves outside the
  package. The CI matrix now runs the Go tests, `go vet`, and
  the zsh bootstrap tests in addition to the existing Rust,
  Vitest, and smoke gates.

### Known costs (carried into Phase 1b, not regressions)

- `BlockGrid::trim_to_first_row` renumbers every surviving block
  in O(n) per trim. A root-level offset on the tree would make
  this O(log n) but the current cost is small: trim runs once
  per `feed`, only after the row cap is reached, and is well
  under the §9.4 perf gate on the workloads Phase 1a measures.
  The decision is recorded here so a later reader does not
  mistake the O(n) for an oversight; it is a deliberate trade
  for a simpler tree shape.
- The find engine's `block_byte_range` falls back to "block i
  owns row i" when `block.row_count == 0`. This is a workaround
  for a Task 7 timing race where a block is observed before its
  first row has been flushed into the row index. The fallback
  only fires for the first match in a fresh block and does not
  change the result, only the byte range the engine reports.
- `BlockTree::push` and `BlockTree::pop_front` each walk the path
  from the affected leaf to the root twice — once via
  `propagate_summary_up` and once via
  `propagate_from_last_leaf_to_root` /
  `propagate_from_first_leaf_to_root`. Both walks do the same
  work, so the second is redundant. A later task can collapse
  the two into one without changing the public API.

## 0.1.0 - 2026-08-29

Phase 0 workspace skeleton.

- Workspace skeleton: independent npm workspace and Cargo workspace at
  `packages/terminal/`, with `@operator/terminal-core`,
  `@operator/terminal-renderer-dom`, and `@operator/terminal-react`
  npm packages and `vt-core`, `vt-wasm`, and `terminal-marks` Cargo
  crates, all at 0.1.0.
- Explicit WASM loading through `init(wasmBytes)` instead of the
  `wasm-bindgen` auto-fetch form, so the same bytes load in Vitest,
  Vite, and an optimized Tauri binary.
- One-block DOM slice painted from a real VT parse, exposed through the
  React mount.
- Boundary enforcement: `check:boundaries` rejects any import that
  escapes `packages/terminal/`, the forbidden package edges
  (`renderer-dom` -> `editor`, `editor` -> `completions`), any source
  file over 600 lines, and any Cargo or Go replacement that resolves
  outside the package.
- xterm 5.5.0 baseline recorded for later phases to beat.

### Fixes found in Phase 0 review

- `RowIndex::trim_to` released the open row's start instead of the first
  retained row's start, so `Content::drop_before` discarded bytes that
  retained rows still referenced. Any output ending in a newline blanked
  the whole scrollback once the row limit was reached.
- Zero-width scalars never advanced the column, so the open row was never
  completed and never trimmed; a stream of combining marks grew the core
  without bound. A cell now accepts at most eight of them.
- `checked_u32_from_u64` was reachable only from its own test while the
  live conversions in `grid.rs` were unchecked `as u32` casts. Snapshot
  offsets are now checked and surface `CoreError::OffsetOverflow`.
- SGR sub-parameters were read as top-level codes, so `48;5;31` -- a
  256-colour background -- repainted the foreground ANSI red. The
  extended-colour introducers now consume their own parameters, and the
  colon form stays self-contained.
- A throwing `onChange` listener escaped `feed` and starved the listeners
  registered after it; failures are now collected and reported together.
- `wasm-bindgen-cli` is cached in CI instead of being compiled from
  source in all four jobs on every run.
