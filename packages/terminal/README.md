# @operator/terminal

A Warp-grade terminal as a reusable package, written as if it could be
published to npm and crates.io. Lives at `packages/terminal/` in this
repository.

## Phase 5 capability

Phase 5 adds navigation on top of the block-aware renderer:

- **Find.** `createFindBar({ core, renderer, host, strings })` returns a
  `FindBar` handle. Cmd/Ctrl+F opens the bar; typing runs an incremental
  find session; Enter walks forward, Shift+Enter walks backward, Escape
  closes and restores focus. The find cursor is rebuilt lazily on every
  step and held only as a `u32` session id in JS; cancellation is
  `core.findCancel(id)`. The bench proves the gate: **29.60ms p95** at
  the chosen `FIND_STEP_BUDGET = 1000`, under the 100ms ceiling, for a
  500k-row scrollback.
- **Sticky command header.** The pinned header is the first child of
  the host, `position: sticky; top: 0`. It names the block the center
  of the viewport is scrolled into. Sticky survives `contain: strict`
  on the host in Chromium; the absolute alternative was tried and
  failed because absolute children of `overflow: auto` containers
  position at the content origin.
- **Block navigation.** Cmd/Ctrl+ArrowUp/Down walks the block list
  (filtered if a filter is active) and scrolls the focused block to
  the center. Inert in the alt screen; the first assertion in
  `block-nav.test.ts`. Lives in `ts/renderer-dom/src/block-nav.ts`,
  not in the line-editor keymap.
- **Filter and bookmark.** `applyFilter(blocks, filter)` is a pure
  function; it never mutates, reorders, evicts, or renumbers
  `BlockId`s. `core.setBlockBookmarked(id, bool)` and
  `core.blockBookmarked(id)` are the bookend API; the host owns
  persistence.
- **Full block action menu.** Up to seven buttons per block:
  copy-command, copy-output, share-output, bookmark, filter-to-command,
  jump, rerun. Every action is a real `<button>` with `aria-label`; the
  rerun action fires a `CustomEvent` that the host's line editor
  consumes (rerun writes bytes to the transport; the user runs the
  command). No action may call a `HostCapabilities` method that can
  execute anything — `HostCapabilities` itself has no such method.
- **Command palette.** `mountPalette({ container, getCommands, isAltScreenActive, strings })`
  opens on Cmd/Ctrl+Shift+P, lists package- and host-defined commands,
  and supports type/arrow/Enter/Escape. Substring filter, not strict
  prefix — `includes`, not `startsWith` — a strict superset. The
  first test in `palette.test.ts` is alt-screen inertness.

## Phase 0 capability

Phase 0 is an append-and-wrap parser slice, not a daily-driver terminal.
It proves the same WASM bytes load in Vitest, Vite, and an optimized
Tauri build, and that a one-block DOM slice can be painted from a real
VT parse. Full VT support, OSC 133 decoding, block sum trees,
virtualization, selection, find, editor, completions, and `TerminalPane`
integration belong to later phases.

## Phase 1a capability

Phase 1a layers the block-aware core on top of the Phase 0 parser. The
core forms blocks from OSC 133 (Tier 1) and the `OSC 7000` extension
(Tier 2), tracks the alt screen so marks observed inside it do not
change the block list, and exposes the block list through the
`CoreSnapshot` export. The package does **not** own input — it does
not spawn the host shell, read from its pty, or claim prompt
suppression. `spawnRecipe` returns the argv and env to launch the
host's shell; the host owns the pty and the read loop.

Phase 0 handles only: printable UTF-8, combining characters, CRLF/LF,
tab expansion to the next 8-column stop, hard wrapping at the column
boundary, and SGR `0`/`30..37`/`39`/`90..97`. Every other CSI, ESC,
DCS, or OSC callback is a no-op. Cursor-addressed mutation, erase
operations, alt screen, scroll regions, and full VT conformance belong
to Phase 1.

The package has no Operator imports. It must not gain them: the
`check:boundaries` script enforces this and fails CI on any leak.

## Prerequisites

- Rust 1.96.0 (the `rust-toolchain.toml` pins it exactly).
- The `wasm32-unknown-unknown` target installed for that toolchain.
- CLI `wasm-bindgen 0.2.127` (the version of the `wasm-bindgen` crate
  must match the CLI version exactly).
- Node.js 22.23.2 locally or 24 in CI.
- npm 10.

The generated `ts/core/wasm/` bindings and the `.wasm` file are never
committed; they are produced on demand by `npm run build:wasm` and live
under `ts/core/wasm/` which is ignored by git.

## Commands

Run all of these from this directory (`packages/terminal/`):

```bash
npm ci
npm run build
npm test
npm run check:boundaries
npm run smoke:vite
npm run smoke:tauri
npm run bench:terminal -- --renderer xterm --scenario <name>
npm run bench:baseline -- --renderer xterm --record
```

`npm run build` and `npm test` build the WASM first, then the TypeScript
project references.

The package-owned browser harness measures `vtebench`, `large-output`,
or `input-latency` with xterm 5.5.0. It activates WebGL first and recovers
to canvas if WebGL activation or its context fails. A run never combines
renderer kinds. Uncommitted results are written under the ignored
`bench/results/` directory.

Baseline recording requires a clean git tree and measures all three
scenarios in one invocation. It writes
`bench/baselines/<platform>-<architecture>-xterm.json`; review and commit
that measured file separately from harness changes.
