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
