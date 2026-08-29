# Changelog

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
