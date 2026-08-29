# @operator/terminal

A Warp-grade terminal as a reusable package, written as if it could be
published to npm and crates.io. Lives at `packages/terminal/` in this
repository.

## Phase 0 capability

Phase 0 is an append-and-wrap parser slice, not a daily-driver terminal.
It proves the same WASM bytes load in Vitest, Vite, and an optimized
Tauri build, and that a one-block DOM slice can be painted from a real
VT parse. Full VT support, OSC 133 decoding, block sum trees,
virtualization, selection, find, editor, completions, and `TerminalPane`
integration belong to later phases.

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
