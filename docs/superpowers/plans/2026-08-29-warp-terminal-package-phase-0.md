# Warp Terminal Package Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `packages/terminal` as an independently testable Rust/WASM + TypeScript package, prove the same WASM bytes load in Vitest, Vite, and an optimized Tauri binary, paint one DOM block from a real VT parse, enforce package boundaries, and record the xterm performance baseline used by later phases.

**Architecture:** `vt-core` parses PTY bytes with crates.io `vte` into chunked UTF-8 content, row ranges, and run-length style maps. `vt-wasm` owns compact export buffers and exposes pointers and lengths; `@operator/terminal-core` turns those buffers into typed-array views without creating a JavaScript object per cell. `@operator/terminal-renderer-dom` paints one synthetic block with one span per style run, and `@operator/terminal-react` supplies the React mount. A package-owned benchmark harness compares renderers against the same deterministic workloads and records xterm 5.5.0 as the Phase 0 baseline.

**Tech Stack:** Rust 1.96.0, Cargo workspace resolver 2, `vte` 0.15.0, `wasm-bindgen` and `wasm-bindgen-cli` 0.2.127, `unicode-width` 0.2.2, Node.js 22.23.2 locally or 24 in CI, npm 10, TypeScript 5.9.3, `@types/node` 20.19.41, Vite 8.0.16, `@vitejs/plugin-react` 6.0.2, Vitest 4.1.8, jsdom 29.1.1, React 19.2.7, React types 19.2.17, React DOM types 19.2.3, Testing Library React 16.3.2, Playwright 1.60.0, xterm.js 5.5.0 with WebGL addon 0.19.0 and canvas addon 0.7.0, Tauri CLI 2.11.4.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`, Phase 0 only.

## Global Constraints

- Phase 0 is the only phase in scope. Do not add OSC 133/7000 decoding, shell bootstraps, block sum trees, virtualization, selection, find, editor, completions, daemon capture, or `TerminalPane` integration.
- The Phase 0 grid is an append-and-wrap vertical slice. It must correctly handle printable UTF-8, combining characters, CRLF/LF, tab expansion, hard wrapping, and SGR reset plus 16 foreground colors. Cursor-addressed mutation, erase operations, alt screen, and full VT conformance belong to Phase 1.
- Use crates.io `vte = 0.15.0`; do not fork it and do not copy Warp source, comments, tests, fixtures, or assets.
- Internal content offsets are monotonic `u64`. WASM export offsets are checked `u32`; overflow returns a JavaScript error instead of truncating.
- JavaScript receives `Uint8Array` and `Uint32Array` views over WASM linear memory. Do not materialize cells or style runs as JavaScript objects.
- The DOM renderer emits one span per style run, never one span per character and never a canvas fast path.
- `packages/terminal` must not import from `frontend/`, `backend/`, or `packages/shared/`. Operator consumes only `@operator/terminal-react` by package name.
- The generated `ts/core/wasm/` bindings and `.wasm` file are ignored and rebuilt on demand. Commit `packages/terminal/Cargo.lock` and `packages/terminal/package-lock.json`.
- The `wasm-bindgen-cli` version must exactly match the Rust `wasm-bindgen` crate version: `0.2.127`.
- Every code file under `packages/terminal`, excluding generated output, must remain at or below 600 lines.
- Do not add source-code comments. Use names, types, tests, README prose, and this plan to carry intent.
- Keep all Tauri smoke-test state under `~/.operator/terminal-smoke/`; clean the per-run directory in `finally` handling.
- Preserve unrelated worktree changes. Every task commit stages only the files listed by that task.
- Use tabs in JSON and TypeScript where the surrounding Operator files do; use `cargo fmt` for Rust.

## Findings That Shape This Plan

- The root `package.json` has no npm workspaces. The terminal package therefore owns its own npm workspace and lockfile.
- `frontend/src-tauri/Cargo.toml` is standalone and remains outside the new Cargo workspace.
- The current machine has Rust 1.96.0, Node 22.23.2, npm 10.9.8, and Go 1.25.12, but neither `wasm32-unknown-unknown` nor `wasm-bindgen-cli` is installed.
- `frontend/perf/scenarios.json` defines 3 warmups, 10 measured samples, a 120x40 grid, 5,000 rows of scrollback, and 16 MiB for `large-output`. Preserve those values in the package harness.
- No terminal throughput/input baseline is committed today. Phase 0 must generate and commit it; do not invent numbers in a document.
- `tauri build --no-bundle --config <JSON>` is supported by the pinned Tauri CLI. The release smoke can replace only `build.frontendDist`, build an optimized binary, launch it with `OPERATOR_TAURI_TERMINAL_BENCHMARK=1`, and receive a loopback success report from the embedded page.
- `wasm-bindgen` 0.2.127 accepts bytes through `init({ module_or_path: bytes })` and returns an `InitOutput` containing the module memory. The package-level API remains `initTerminalCore(wasmBytes)` so hosts never use auto-fetch.
- Warp documents its custom-theme YAML contract and publishes the bundled `Warp Dark` palette. Phase 0 uses those published values for its default; the YAML loader remains Phase 4 scope.

## Planned File Structure

| Path | Responsibility |
|---|---|
| `packages/terminal/package.json` | Private npm-workspace commands for build, test, checks, smoke, and benchmarks. |
| `packages/terminal/package-lock.json` | Exact npm dependency graph owned by the package. |
| `packages/terminal/Cargo.toml` | Independent Cargo workspace containing `vt-core`, `vt-wasm`, and `marks`. |
| `packages/terminal/Cargo.lock` | Exact Rust dependency graph owned by the package. |
| `packages/terminal/rust-toolchain.toml` | Rust 1.96.0, rustfmt, clippy, and `wasm32-unknown-unknown`. |
| `packages/terminal/README.md` | Package boundary, build prerequisites, commands, and Phase 0 capability statement. |
| `packages/terminal/CHANGELOG.md` | Package-owned `0.1.0` Phase 0 entry. |
| `packages/terminal/.gitignore` | Generated bindings, npm/Cargo output, smoke output, and uncommitted benchmark runs. |
| `packages/terminal/crates/vt-core/` | Parser, flat content, row index, style runs, and unit tests. |
| `packages/terminal/crates/vt-wasm/` | WASM façade and compact memory export buffers. |
| `packages/terminal/crates/marks/` | Empty protocol-crate boundary required by the approved Cargo graph; implementation waits for Phase 1. |
| `packages/terminal/ts/core/` | Explicit WASM initialization, typed memory views, public core types, and Vitest load proof. |
| `packages/terminal/ts/renderer-dom/` | One-block DOM renderer and CSS. |
| `packages/terminal/ts/react/` | React mount that owns a `DomBlockRenderer`. |
| `packages/terminal/scripts/build-wasm.mjs` | Checked, incremental `cargo build` + `wasm-bindgen --target web` pipeline. |
| `packages/terminal/scripts/check-boundaries.mjs` | Import, package-graph, generated-output, and 600-line enforcement. |
| `packages/terminal/scripts/check-boundaries.test.mjs` | Deliberately bad import/edge/length positive controls. |
| `packages/terminal/scripts/smoke-vite.mjs` | Starts Vite, opens Chromium, and proves the real WASM/DOM slice renders. |
| `packages/terminal/scripts/smoke-tauri.mjs` | Builds and launches an optimized Tauri binary embedding the same smoke page. |
| `packages/terminal/smoke/` | Package-name consumer page used by Vite and Tauri. |
| `packages/terminal/bench/` | Renderer adapters, deterministic workloads, runner, schema tests, and baselines. |
| `.github/workflows/terminal.yml` | Package checks plus Vite and optimized Tauri smoke gates. |
| `frontend/package.json` | File dependency and pre-scripts that build the package when needed. |
| `frontend/package-lock.json` | Locked file dependency. |
| `.github/workflows/frontend.yml` | Installs the package toolchain before frontend test/typecheck. |

---

### Task 1: Create the independent package workspaces

**Files:**
- Create: `packages/terminal/package.json`
- Create: `packages/terminal/package-lock.json`
- Create: `packages/terminal/tsconfig.base.json`
- Create: `packages/terminal/Cargo.toml`
- Create: `packages/terminal/Cargo.lock`
- Create: `packages/terminal/rust-toolchain.toml`
- Create: `packages/terminal/.gitignore`
- Create: `packages/terminal/README.md`
- Create: `packages/terminal/CHANGELOG.md`
- Create: `packages/terminal/crates/vt-core/Cargo.toml`
- Create: `packages/terminal/crates/vt-core/src/lib.rs`
- Create: `packages/terminal/crates/vt-wasm/Cargo.toml`
- Create: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Create: `packages/terminal/crates/marks/Cargo.toml`
- Create: `packages/terminal/crates/marks/src/lib.rs`
- Create: `packages/terminal/ts/core/package.json`
- Create: `packages/terminal/ts/core/tsconfig.json`
- Create: `packages/terminal/ts/core/vitest.config.ts`
- Create: `packages/terminal/ts/core/src/index.ts`
- Create: `packages/terminal/ts/renderer-dom/package.json`
- Create: `packages/terminal/ts/renderer-dom/tsconfig.json`
- Create: `packages/terminal/ts/renderer-dom/vitest.config.ts`
- Create: `packages/terminal/ts/renderer-dom/src/index.ts`
- Create: `packages/terminal/ts/react/package.json`
- Create: `packages/terminal/ts/react/tsconfig.json`
- Create: `packages/terminal/ts/react/vitest.config.ts`
- Create: `packages/terminal/ts/react/src/index.ts`

**Interfaces:**
- Produces Cargo packages `vt-core`, `vt-wasm`, and `terminal-marks`, all at `0.1.0`.
- Produces npm packages `@operator/terminal-core`, `@operator/terminal-renderer-dom`, and `@operator/terminal-react`, all at `0.1.0`.
- Deliberately does not create `ts/editor` or `ts/completions`; their package directories land in their own phases.

- [ ] **Step 1: Write the workspace manifests**

Use this Cargo workspace shape:

```toml
[workspace]
members = ["crates/marks", "crates/vt-core", "crates/vt-wasm"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
rust-version = "1.96.0"
license = "MIT"
repository = "https://github.com/OmarAly92/operator"

[workspace.dependencies]
unicode-width = "=0.2.2"
vte = { version = "=0.15.0", default-features = false }
wasm-bindgen = "=0.2.127"
```

`vt-core` depends on `unicode-width` and `vte`. `vt-wasm` has `crate-type = ["cdylib", "rlib"]` and depends on `vt-core` by path plus workspace `wasm-bindgen`. `terminal-marks` has no dependency and its `lib.rs` contains only `#![forbid(unsafe_code)]`.

Use this toolchain file:

```toml
[toolchain]
channel = "1.96.0"
components = ["clippy", "rustfmt"]
profile = "minimal"
targets = ["wasm32-unknown-unknown"]
```

- [ ] **Step 2: Write the npm workspace and package manifests**

The root manifest is private and uses `workspaces: ["ts/*"]`. Pin the versions from the Tech Stack rather than ranges in `devDependencies`, including React, React DOM, their type packages, `@types/node`, jsdom, Testing Library React, Vite, the Vite React plugin, Vitest, TypeScript, Playwright, xterm, the xterm WebGL addon, and the xterm canvas addon. Each child package exports `./dist/index.js` and `./dist/index.d.ts`, has `type: "module"`, `files: ["dist"]`, and an independent `test` script using its own Vitest config. Renderer-dom additionally exports `./styles.css` from `./src/styles.css` and includes that file in `files`; React imports that package subpath. Core uses Vitest's Node environment; renderer-dom and React use jsdom. Create each initial `src/index.ts` with `export {};` so the skeleton has a valid compiler input, then replace those exports in Tasks 5 and 6.

Use file dependencies inside the package graph:

```json
{
	"@operator/terminal-core": "file:../core"
}
```

`@operator/terminal-renderer-dom` consumes only core. `@operator/terminal-react` consumes core and renderer-dom and declares `react` and `react-dom` as peers with `>=18.2 <20`.

- [ ] **Step 3: Write the shared TypeScript compiler contract**

```json
{
	"compilerOptions": {
		"target": "ES2022",
		"module": "ESNext",
		"moduleResolution": "Bundler",
		"lib": ["ES2022", "DOM", "DOM.Iterable"],
		"strict": true,
		"declaration": true,
		"declarationMap": true,
		"sourceMap": true,
		"composite": true,
		"noUnusedLocals": true,
		"noUnusedParameters": true,
		"noImplicitReturns": true,
		"skipLibCheck": true
	}
}
```

Each package sets `rootDir: "src"`, `outDir: "dist"`; React also sets `jsx: "react-jsx"`. Project references are core → renderer-dom → react. Give the root workspace a `build:ts` script running `tsc -b ts/core ts/renderer-dom ts/react` and a temporary `build` alias to `build:ts`; Task 4 replaces `build` with the WASM-first composition. Do not rely on npm's implicit workspace execution order.

- [ ] **Step 4: Document only the current capability**

`README.md` must state:

- Phase 0 is an append-and-wrap parser slice, not a daily-driver terminal.
- the package has no Operator imports;
- Rust 1.96.0, target `wasm32-unknown-unknown`, and CLI `wasm-bindgen 0.2.127` are prerequisites;
- exact commands are `npm ci`, `npm run build`, `npm test`, `npm run check:boundaries`, `npm run smoke:vite`, `npm run smoke:tauri`, and `npm run bench:terminal -- --renderer xterm --scenario <name>`;
- generated WASM bindings are never committed.

`CHANGELOG.md` begins with `## 0.1.0 - 2026-08-29` and lists workspace skeleton, explicit WASM loading, one-block DOM slice, boundary enforcement, and xterm baseline.

- [ ] **Step 5: Install and validate the empty graph**

```bash
npm --prefix packages/terminal install
cargo metadata --manifest-path packages/terminal/Cargo.toml --no-deps --format-version 1
cargo test --manifest-path packages/terminal/Cargo.toml --workspace
npm --prefix packages/terminal exec -- tsc -b --pretty false
```

Expected: npm writes only `packages/terminal/package-lock.json`; Cargo reports exactly three workspace members; Cargo tests and TypeScript compilation exit 0.

- [ ] **Step 6: Commit the independent skeleton**

```bash
git add packages/terminal docs/superpowers/plans/2026-08-29-warp-terminal-package-phase-0.md
git commit -m "chore(terminal): create package workspaces"
```

If the plan was already committed after user review, the extra path is a no-op. If it was still untracked, this prevents the later clean-tree benchmark gate from being blocked by its own execution document.

---

### Task 2: Enforce the package boundary and file-size rules

**Files:**
- Create: `packages/terminal/scripts/check-boundaries.mjs`
- Create: `packages/terminal/scripts/check-boundaries.test.mjs`
- Modify: `packages/terminal/package.json`

**Interfaces:**
- Produces `collectBoundaryErrors(root): Promise<string[]>`.
- Produces CLI `node scripts/check-boundaries.mjs [root]` with exit 0 on no errors and exit 1 after printing one error per line.
- Produces `npm run check:boundaries`.

- [ ] **Step 1: Write failing checker tests**

The Node test creates each fixture under `mkdtemp(join(tmpdir(), "terminal-boundary-"))`, cleans it in `finally`, and covers all four rules:

```js
test("rejects a relative import outside the package", async () => {
	const root = await fixture({ "ts/core/src/index.ts": 'import "../../../../../frontend/src/renderer/main";\n' });
	assert.deepEqual(await collectBoundaryErrors(root), [
		"ts/core/src/index.ts: relative import escapes packages/terminal",
	]);
});

test("rejects forbidden package edges", async () => {
	const root = await fixture({
		"ts/renderer-dom/src/index.ts": 'import "@operator/terminal-editor";\n',
		"ts/editor/src/index.ts": 'import "@operator/terminal-completions";\n',
	});
	assert.deepEqual(await collectBoundaryErrors(root), [
		"ts/editor/src/index.ts: editor must not import completions",
		"ts/renderer-dom/src/index.ts: renderer-dom must not import editor",
	]);
});

test("rejects an oversized source file", async () => {
	const root = await fixture({ "ts/core/src/large.ts": "export {};\n".repeat(601) });
	assert.deepEqual(await collectBoundaryErrors(root), [
		"ts/core/src/large.ts: source file has 601 lines; maximum is 600",
	]);
});

test("rejects Cargo and Go replacements outside the package", async () => {
	const root = await fixture({
		"crates/vt-core/Cargo.toml": '[dependencies]\nleak = { path = "../../../../backend" }\n',
		"go.mod": "module example.test/terminal\n\nreplace example.test/shared => ../../shared\n",
	});
	assert.deepEqual(await collectBoundaryErrors(root), [
		"crates/vt-core/Cargo.toml: Cargo path dependency escapes packages/terminal",
		"go.mod: Go replacement escapes packages/terminal",
	]);
});
```

Add a passing fixture with bare third-party imports and relative imports that stay inside the root.

- [ ] **Step 2: Run the tests and confirm red**

```bash
node --test packages/terminal/scripts/check-boundaries.test.mjs
```

Expected: FAIL because `check-boundaries.mjs` does not exist.

- [ ] **Step 3: Implement the checker**

The checker must:

- walk without following symlinks;
- skip `node_modules`, `target`, `dist`, `smoke/dist`, `bench/results`, `ts/core/wasm`, and files under `.git`;
- scan `.ts`, `.tsx`, `.js`, `.mjs`, `.cjs`, `.rs`, `.go`, `.sh`, `.fish`, and `.ps1` for the 600-line rule;
- parse static `import`, `export ... from`, and dynamic `import()` string literals in JS/TS;
- resolve every relative module specifier with `path.resolve(dirname(file), specifier)` and reject a path for which `path.relative(root, resolved)` begins with `..` or is absolute;
- reject resolved or bare imports naming `frontend`, `backend`, or `packages/shared`;
- reject renderer-dom → editor/completions and editor → completions, whether relative or bare;
- sort errors by repository-relative file, then message;
- reject `path = "..."` Cargo dependencies and `replace` Go module paths that resolve outside the package.

Do not attempt to execute or resolve bare npm packages; graph rules are name based.

- [ ] **Step 4: Run red/green and the real-tree check**

```bash
node --test packages/terminal/scripts/check-boundaries.test.mjs
npm --prefix packages/terminal run check:boundaries
```

Expected: all checker tests pass and the real tree prints nothing.

- [ ] **Step 5: Commit the executable boundary**

```bash
git add packages/terminal/package.json packages/terminal/package-lock.json packages/terminal/scripts
git commit -m "test(terminal): enforce package boundaries"
```

---

### Task 3: Build the flat append-and-wrap `vt-core` slice

**Files:**
- Create: `packages/terminal/crates/vt-core/src/content.rs`
- Create: `packages/terminal/crates/vt-core/src/style.rs`
- Create: `packages/terminal/crates/vt-core/src/attribute_map.rs`
- Create: `packages/terminal/crates/vt-core/src/row_index.rs`
- Create: `packages/terminal/crates/vt-core/src/grid.rs`
- Create: `packages/terminal/crates/vt-core/src/parser.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Create: `packages/terminal/crates/vt-core/tests/terminal_core.rs`

**Interfaces:**
- Produces `TerminalCore::new(columns: usize, scrollback_rows: usize) -> Result<Self, CoreError>`.
- Produces `TerminalCore::feed(&mut self, bytes: &[u8])`.
- Produces `TerminalCore::snapshot(&self) -> GridSnapshot` containing flat bytes, row ranges, run ranges, and style pairs.
- Produces `StyleCode(u32)` where low byte is `0..15` or `255` for default foreground.

- [ ] **Step 1: Write the integration tests first**

```rust
use vt_core::{StyleCode, TerminalCore};

#[test]
fn parses_utf8_crlf_wrap_and_sgr_into_flat_runs() {
    let mut core = TerminalCore::new(16, 100).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m caf\xc3");
    core.feed(b"\xa9\r\nplain\ttext");
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_text(0), "red café");
    assert_eq!(snapshot.row_text(1), "plain   text");
    assert_eq!(snapshot.row_style_pairs(0), &[
        (3, StyleCode::ansi(1)),
        (9, StyleCode::DEFAULT),
    ]);
    assert_eq!(snapshot.row_style_pairs(1), &[(12, StyleCode::DEFAULT)]);
}

#[test]
fn hard_wraps_wide_and_combining_text_without_splitting_utf8() {
    let mut core = TerminalCore::new(4, 100).unwrap();
    core.feed("A界e\u{301}B".as_bytes());
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_text(0), "A界e\u{301}");
    assert_eq!(snapshot.row_text(1), "B");
}

#[test]
fn trims_complete_rows_to_the_scrollback_limit() {
    let mut core = TerminalCore::new(20, 2).unwrap();
    core.feed(b"one\ntwo\nthree");
    let snapshot = core.snapshot();

    assert_eq!(snapshot.row_count(), 2);
    assert_eq!(snapshot.row_text(0), "two");
    assert_eq!(snapshot.row_text(1), "three");
}
```

Add unit tests beside each structure for chunk-boundary slicing, adjacent-style coalescing, row front trimming, `columns == 0`, and `scrollback_rows == 0`. Both zero-valued constructor arguments return distinct `CoreError` variants; do not silently substitute defaults.

- [ ] **Step 2: Run the focused tests and confirm red**

```bash
cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core
```

Expected: FAIL because the public API and modules do not exist.

- [ ] **Step 3: Implement monotonic chunked content**

Use owned 4 KiB chunks keyed by monotonic start/end byte offsets:

```rust
pub(crate) struct Content {
    chunks: VecDeque<Chunk>,
    next_offset: u64,
}

pub(crate) struct Chunk {
    start: u64,
    bytes: Vec<u8>,
}
```

Required operations are `push_char`, `end_offset`, `copy_range`, and `drop_before`. `push_char` starts a new chunk before a UTF-8 scalar would cross the 4 KiB boundary. `drop_before` removes only chunks whose exclusive end is at or before the new first-row offset; offsets never re-zero.

- [ ] **Step 4: Implement end-keyed run-length attributes**

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StyleCode(u32);

impl StyleCode {
    pub const DEFAULT: Self = Self(255);

    pub const fn ansi(index: u8) -> Self {
        Self(index as u32)
    }

    pub const fn value(self) -> u32 {
        self.0
    }
}

pub(crate) struct AttributeMap<A> {
    ends: BTreeMap<u64, A>,
    tail: A,
}
```

All stored keys are exclusive monotonic byte ends. `set_from(offset, value)` inserts `(offset, previous_value)` when `offset` is after the current run start, coalesces equal values, and changes the tail; it never subtracts one from a byte offset. `runs(start..end)` returns row-relative exclusive end offsets and values, always ending exactly at the row byte length when the row is non-empty. Test style changes at offset zero, a multibyte scalar boundary, and an equal-value no-op so inclusive/exclusive confusion cannot survive the unit suite.

- [ ] **Step 5: Implement row indexing and snapshots**

`RowIndex` stores `VecDeque<RowRange>` plus the open row start and display width. `GridSnapshot` owns one contiguous `Vec<u8>`, `Vec<(u32,u32)>` row byte ranges, `Vec<(u32,u32)>` per-row run-index ranges, and `Vec<(u32,StyleCode)>` style pairs. It is acceptable to compact into the snapshot in Rust; it is not acceptable to compact into JavaScript objects.

For a blank row, emit an empty byte range and zero style pairs. `row_text` validates UTF-8 and is test-only/public diagnostics; the WASM renderer uses the flat buffers.

When the scrollback limit drops rows, remove their `RowRange` entries, call `Content::drop_before` with the next row's monotonic start, and drop attribute-map endings before that same start while preserving the value active at the new start. Add a test where the surviving first row begins inside a style run.

- [ ] **Step 6: Implement the `vte::Perform` adapter**

`Parser` persists across `feed` calls. Implement only:

- `print`: append the scalar, use `unicode_width::UnicodeWidthChar`, wrap before a positive-width scalar would exceed `columns`, and keep width-zero combining scalars on the current row;
- `execute`: LF/VT/FF open a new row, CR records no byte, tab inserts spaces through the next multiple-of-eight stop;
- `csi_dispatch` for action `m`: handle `0`, `30..=37`, `39`, and `90..=97`; ignore unsupported codes without emitting text or failing.

All other callbacks are no-ops in Phase 0. State this exact capability in README; do not call it full VT support.

- [ ] **Step 7: Run the core test and quality gates**

```bash
cargo fmt --check --manifest-path packages/terminal/Cargo.toml
cargo clippy --manifest-path packages/terminal/Cargo.toml -p vt-core --all-targets -- -D warnings
cargo test --manifest-path packages/terminal/Cargo.toml -p vt-core
npm --prefix packages/terminal run check:boundaries
```

Expected: all commands exit 0; the integration test proves split-read UTF-8, SGR runs, wrapping, and scrollback trimming.

- [ ] **Step 8: Commit the non-throwaway core slice**

```bash
git add packages/terminal/crates/vt-core packages/terminal/Cargo.lock packages/terminal/README.md
git commit -m "feat(terminal): add flat VT core slice"
```

---

### Task 4: Export compact buffers through `vt-wasm`

**Files:**
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Create: `packages/terminal/crates/vt-wasm/tests/export_layout.rs`
- Create: `packages/terminal/scripts/build-wasm.mjs`
- Modify: `packages/terminal/package.json`
- Modify: `packages/terminal/.gitignore`

**Interfaces:**
- Produces generated class `WasmTerminalCore`.
- Produces `feed(bytes: Uint8Array): void`, `generation(): number`, and pointer/length pairs for content, rows, run ranges, and style pairs.
- Produces `npm run build:wasm` and `npm run build:wasm -- --force`.

- [ ] **Step 1: Write native layout tests**

Test a pure `ExportBuffers::refresh(&GridSnapshot)` helper before adding WASM annotations:

```rust
#[test]
fn flattens_rows_and_runs_as_u32_pairs() {
    let mut core = TerminalCore::new(16, 10).unwrap();
    core.feed(b"\x1b[31mred\x1b[0m ok\nplain");
    let mut buffers = ExportBuffers::default();
    buffers.refresh(&core.snapshot()).unwrap();

    assert_eq!(buffers.content(), b"red okplain");
    assert_eq!(buffers.rows(), &[0, 6, 6, 11]);
    assert_eq!(buffers.run_ranges(), &[0, 2, 2, 3]);
    assert_eq!(buffers.style_pairs(), &[3, 1, 6, 255, 5, 255]);
}
```

Add an overflow unit test against the checked `u64 -> u32` conversion helper.

- [ ] **Step 2: Run the test and confirm red**

```bash
cargo test --manifest-path packages/terminal/Cargo.toml -p vt-wasm
```

Expected: FAIL because `ExportBuffers` does not exist.

- [ ] **Step 3: Implement the pure export buffer**

Keep `ExportBuffers` free of `wasm-bindgen` so native tests cover the layout. Flatten pairs exactly as the test shows. `refresh` clears and reuses capacity. Return `ExportError::OffsetOverflow` on any failed conversion.

- [ ] **Step 4: Wrap it with `wasm-bindgen`**

```rust
#[wasm_bindgen]
pub struct WasmTerminalCore {
    core: TerminalCore,
    export: ExportBuffers,
    generation: u32,
}

#[wasm_bindgen]
impl WasmTerminalCore {
    #[wasm_bindgen(constructor)]
    pub fn new(columns: usize, scrollback_rows: usize) -> Result<Self, JsError>;
    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), JsError>;
    pub fn generation(&self) -> u32;
    pub fn content_ptr(&self) -> *const u8;
    pub fn content_len(&self) -> usize;
    pub fn rows_ptr(&self) -> *const u32;
    pub fn rows_len(&self) -> usize;
    pub fn run_ranges_ptr(&self) -> *const u32;
    pub fn run_ranges_len(&self) -> usize;
    pub fn style_pairs_ptr(&self) -> *const u32;
    pub fn style_pairs_len(&self) -> usize;
}
```

Construct and refresh once in `new`; refresh and wrapping-increment `generation` after each successful feed. Pointers remain valid only until the next mutating call; the TypeScript wrapper takes fresh views every time.

- [ ] **Step 5: Implement the checked WASM build script**

The script must use `spawnSync`/`execFileSync`, never a shell string. It verifies:

- `rustc --version` begins `rustc 1.96.0`;
- `rustup target list --installed` contains `wasm32-unknown-unknown`;
- `wasm-bindgen --version` is exactly `wasm-bindgen 0.2.127`.

It rebuilds when `--force` is present, any expected output is absent, or a Rust source/manifest/lockfile is newer than the oldest output. The commands are:

```bash
cargo build --manifest-path packages/terminal/Cargo.toml -p vt-wasm --target wasm32-unknown-unknown --release --locked
wasm-bindgen packages/terminal/target/wasm32-unknown-unknown/release/vt_wasm.wasm --target web --out-dir packages/terminal/ts/core/wasm --out-name vt_core
```

Expected outputs are `vt_core.js`, `vt_core.d.ts`, `vt_core_bg.wasm`, and `vt_core_bg.wasm.d.ts`. Ignore the entire generated directory while retaining its parent.

At the same time, replace the root package's temporary Task 1 build alias with these compositions:

```json
{
	"scripts": {
		"build:wasm": "node ./scripts/build-wasm.mjs",
		"build:ts": "tsc -b ts/core ts/renderer-dom ts/react",
		"build": "npm run build:wasm && npm run build:ts",
		"test": "npm run build:wasm && npm run test --workspaces --if-present"
	}
}
```

Keep later package-owned scripts alongside these entries. The root `test` command must work after generated output has been deleted.

- [ ] **Step 6: Install the one missing CLI and run the build**

```bash
rustup target add wasm32-unknown-unknown --toolchain 1.96.0
cargo install wasm-bindgen-cli --version 0.2.127 --locked
npm --prefix packages/terminal run build:wasm -- --force
test -s packages/terminal/ts/core/wasm/vt_core_bg.wasm
```

Expected: all four generated outputs exist and remain untracked under `git status --short`.

- [ ] **Step 7: Run Rust and boundary gates**

```bash
cargo fmt --check --manifest-path packages/terminal/Cargo.toml
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
cargo test --manifest-path packages/terminal/Cargo.toml --workspace
npm --prefix packages/terminal run check:boundaries
```

- [ ] **Step 8: Commit the WASM boundary**

```bash
git add packages/terminal/crates/vt-wasm packages/terminal/scripts/build-wasm.mjs packages/terminal/package.json packages/terminal/package-lock.json packages/terminal/.gitignore packages/terminal/Cargo.lock
git commit -m "feat(terminal): expose typed WASM buffers"
```

---

### Task 5: Load the exact WASM bytes from TypeScript and Vitest

**Files:**
- Create: `packages/terminal/ts/core/src/types.ts`
- Create: `packages/terminal/ts/core/src/wasm-runtime.ts`
- Create: `packages/terminal/ts/core/src/browser.ts`
- Create: `packages/terminal/ts/core/src/terminal-core.ts`
- Create: `packages/terminal/ts/core/src/index.ts`
- Create: `packages/terminal/ts/core/src/terminal-core.test.ts`
- Create: `packages/terminal/ts/core/src/wasm-url.d.ts`
- Modify: `packages/terminal/ts/core/package.json`
- Modify: `packages/terminal/ts/core/tsconfig.json`
- Modify: `packages/terminal/package.json`

**Interfaces:**
- Produces `initTerminalCore(wasmBytes: BufferSource | WebAssembly.Module): Promise<void>`.
- Produces `initTerminalCoreFromUrl(): Promise<void>` from subpath `@operator/terminal-core/browser`.
- Produces `createTerminalCore(options): TerminalCore` after initialization.
- Produces `TerminalCore.snapshot(): TerminalSnapshot` of typed-array views and `onChange(listener)`.

- [ ] **Step 1: Write the Vitest load proof first**

```ts
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { createTerminalCore, initTerminalCore } from "./index";

beforeAll(async () => {
	const bytes = await readFile(fileURLToPath(new URL("../wasm/vt_core_bg.wasm", import.meta.url)));
	const wasmBytes = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
});

describe("TerminalCore", () => {
	it("reads flat content and style pairs directly from WASM memory", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		core.feed(new TextEncoder().encode("\u001b[31mred\u001b[0m café\r\nplain"));
		const snapshot = core.snapshot();

		expect(snapshot.content).toBeInstanceOf(Uint8Array);
		expect(snapshot.rows).toBeInstanceOf(Uint32Array);
		expect(snapshot.stylePairs).toBeInstanceOf(Uint32Array);
		expect(new TextDecoder().decode(snapshot.content)).toBe("red caféplain");
		expect([...snapshot.rows]).toEqual([0, 9, 9, 14]);
		expect([...snapshot.stylePairs]).toEqual([3, 1, 9, 255, 5, 255]);
	});
});
```

Add tests that construction before initialization throws `terminal core WASM is not initialized`, invalid options preserve the Rust error, listeners fire once per successful feed, and `dispose` frees the generated class and clears listeners.

- [ ] **Step 2: Run the focused test and confirm red**

```bash
npm --prefix packages/terminal run build:wasm
npm --prefix packages/terminal run test --workspace @operator/terminal-core
```

Expected: FAIL because the TypeScript API does not exist.

- [ ] **Step 3: Define the public types from the spec**

`types.ts` defines the shared primitives below and the exact `BlockRenderer` interface from §9.1:

```ts
export type BlockId = string;
export type RowRange = Readonly<{ start: number; end: number }>;
export type FontConfig = Readonly<{
	family: string;
	sizePx: number;
	lineHeight: number;
	weight: number;
	letterSpacingPx: number;
	ligatures: boolean;
}>;
```

`RowRange` is half-open. Validate finite, non-negative values and `end >= start` at public renderer calls. Keep `TerminalTheme` renderer-agnostic and fully resolved so the Phase 4 Warp-YAML loader will not leak parsing concerns into renderers:

```ts
export type TerminalTheme = Readonly<{
	ansi: readonly [string, string, string, string, string, string, string, string, string, string, string, string, string, string, string, string];
	foreground: string;
	background: string;
	cursor: string;
	selection: string;
	blockBackground: string;
	blockBorder: string;
	blockHeaderForeground: string;
}>;
```

Define `TerminalSnapshot` as:

```ts
export type TerminalSnapshot = Readonly<{
	generation: number;
	content: Uint8Array;
	rows: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
}>;
```

No cell or run object type is allowed.

- [ ] **Step 4: Implement explicit initialization**

Import generated symbols from `../wasm/vt_core.js`. Store the returned `InitOutput` and use the non-deprecated object form internally:

```ts
const output = await init({ module_or_path: wasmBytes });
```

Concurrent calls share one promise. A completed initialization is idempotent. A failed initialization clears the promise so a caller may retry with valid bytes.

`browser.ts` imports `../wasm/vt_core_bg.wasm?url`, fetches it, rejects a non-2xx response with the URL and status, converts it to `ArrayBuffer`, and passes the bytes to `initTerminalCore`. It never passes the URL to generated init.

Update the core package manifest at this point so its committed distribution contract is explicit:

```json
{
	"files": ["dist", "wasm"],
	"exports": {
		".": {
			"types": "./dist/index.d.ts",
			"import": "./dist/index.js"
		},
		"./browser": {
			"types": "./dist/browser.d.ts",
			"import": "./dist/browser.js"
		}
	}
}
```

The ignored `wasm/` directory is populated before packing or consumption. Do not export generated bindings directly; only `browser.ts` and the root wrapper may import them.

- [ ] **Step 5: Implement memory views without copies or per-cell objects**

```ts
function u8View(memory: WebAssembly.Memory, pointer: number, length: number): Uint8Array {
	return new Uint8Array(memory.buffer, pointer, length);
}

function u32View(memory: WebAssembly.Memory, pointer: number, length: number): Uint32Array {
	return new Uint32Array(memory.buffer, pointer, length);
}
```

`snapshot()` calls all pointer and length accessors on the generated instance and creates fresh views. It validates even lengths for `rows`, `runRanges`, and `stylePairs`. Do not cache typed views across `feed`, because WASM memory growth can replace `memory.buffer`.

- [ ] **Step 6: Build and run the core package**

```bash
npm --prefix packages/terminal run build --workspace @operator/terminal-core
npm --prefix packages/terminal run test --workspace @operator/terminal-core
npm --prefix packages/terminal run check:boundaries
```

Expected: TypeScript emits declarations to `dist`; Vitest instantiates the generated `--target web` module from bytes read by Node.

- [ ] **Step 7: Commit the explicit core loader**

```bash
git add packages/terminal/ts/core packages/terminal/package.json packages/terminal/package-lock.json
git commit -m "feat(terminal): load core WASM explicitly"
```

---

### Task 6: Paint one synthetic block in DOM and React

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/style-code.ts`
- Create: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts`
- Create: `packages/terminal/ts/renderer-dom/src/styles.css`
- Create: `packages/terminal/ts/renderer-dom/src/index.ts`
- Create: `packages/terminal/ts/renderer-dom/src/dom-block-renderer.test.ts`
- Create: `packages/terminal/ts/renderer-dom/src/css.d.ts`
- Create: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Create: `packages/terminal/ts/react/src/index.ts`
- Create: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`

**Interfaces:**
- Produces `DomBlockRenderer implements BlockRenderer`.
- Produces `<TerminalSurface core theme font className?>`.
- Uses synthetic block id `synthetic-0` only in Phase 0.

- [ ] **Step 1: Write DOM tests before the renderer**

```ts
it("renders one block one row node per row and one span per style run", () => {
	const core = coreWith("\u001b[31mred\u001b[0m café\r\nplain");
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);

	expect(host.querySelectorAll('[data-terminal-block-id="synthetic-0"]')).toHaveLength(1);
	expect(host.querySelectorAll("[data-terminal-row]")).toHaveLength(2);
	expect(host.querySelectorAll("[data-terminal-run]")).toHaveLength(3);
	expect(host.textContent).toBe("red caféplain");
});
```

Add tests for feed-triggered invalidation, theme CSS variables, font CSS variables, half-open invalidation ranges, invalid range rejection, `scrollToBlock("synthetic-0")`, unknown block rejection, and disposal unsubscribing/removing DOM.

The React test mounts `TerminalSurface`, feeds the core inside `act`, verifies updated text, unmounts, then verifies later feeds do not touch the detached host.

- [ ] **Step 2: Run renderer and React tests and confirm red**

```bash
npm --prefix packages/terminal run test --workspace @operator/terminal-renderer-dom
npm --prefix packages/terminal run test --workspace @operator/terminal-react
```

Expected: FAIL because both implementations are missing.

- [ ] **Step 3: Implement style decoding and CSS variables**

Map style byte `0..15` to `var(--terminal-ansi-N)` and `255` to `var(--terminal-foreground)`. Reject any other code. Supply this default, sourced from Warp's bundled [`warp_dark.yaml`](https://github.com/warpdotdev/themes/blob/main/warp_bundled/warp_dark.yaml):

```ts
export const warpDarkTheme: TerminalTheme = {
	ansi: [
		"#616161", "#ff8272", "#b4fa72", "#fefdc2",
		"#a5d5fe", "#ff8ffd", "#d0d1fe", "#f1f1f1",
		"#8e8e8e", "#ffc4bd", "#d6fcb9", "#fefdd5",
		"#c1e3fe", "#ffb1fe", "#e5e6fe", "#feffff",
	],
	foreground: "#ffffff",
	background: "#000000",
	cursor: "#00c2ff",
	selection: "rgb(0 194 255 / 0.35)",
	blockBackground: "#000000",
	blockBorder: "#616161",
	blockHeaderForeground: "#f1f1f1",
};
```

Cursor follows Warp's documented rule that an omitted cursor defaults to accent. The selection opacity and resolved block fields are package defaults needed by the typed renderer contract; they are not claimed as YAML fields. Do not implement the Warp YAML loader in Phase 0.

- [ ] **Step 4: Implement the one-pass DOM renderer**

For each row pair in `snapshot.rows`:

1. use the matching pair in `runRanges` to locate `(endOffset, styleCode)` pairs;
2. decode each byte slice with one shared fatal `TextDecoder`;
3. append one `span[data-terminal-run]` per pair;
4. append the row under one `section[data-terminal-block-id="synthetic-0"]`.

The renderer may rebuild the single block on invalidation in Phase 0. It must not create intermediate arrays of cells or runs. `measure()` measures one hidden `M` using the configured font. `setTheme` and `setFont` update CSS variables without remounting.

- [ ] **Step 5: Implement the React lifecycle wrapper**

`TerminalSurface` owns one renderer in a ref, mounts it in `useLayoutEffect`, updates theme/font in separate effects, and disposes on unmount. Import package CSS through the renderer package export, not a relative path across packages.

- [ ] **Step 6: Run the package tests and static gates**

```bash
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
```

Expected: all package tests pass; the DOM assertion proves the node count is proportional to style runs.

- [ ] **Step 7: Commit the first painted block**

```bash
git add packages/terminal/ts/renderer-dom packages/terminal/ts/react packages/terminal/package.json packages/terminal/package-lock.json
git commit -m "feat(terminal): paint one DOM block"
```

---

### Task 7: Prove Vite consumption and wire Operator's file dependency

**Files:**
- Create: `packages/terminal/smoke/index.html`
- Create: `packages/terminal/smoke/main.tsx`
- Create: `packages/terminal/smoke/vite.config.ts`
- Create: `packages/terminal/scripts/smoke-vite.mjs`
- Modify: `packages/terminal/package.json`
- Modify: `packages/terminal/ts/react/src/index.ts`
- Modify: `frontend/package.json`
- Modify: `frontend/package-lock.json`

**Interfaces:**
- Produces `npm --prefix packages/terminal run smoke:vite`.
- Produces frontend dependency `@operator/terminal-react: file:../packages/terminal/ts/react`.
- Produces frontend command `terminal:build` and package-building pre-hooks.

- [ ] **Step 1: Create the package-name smoke consumer**

The smoke page imports only from `@operator/terminal-react`. Re-export `initTerminalCoreFromUrl`, `createTerminalCore`, the default theme, and `TerminalSurface` from that package so the consumer needs one package name.

Feed `\x1b[31mred\x1b[0m café\r\nplain`, render the surface, then after two animation frames set:

```html
<main data-terminal-smoke="ready" data-row-count="2" data-run-count="3"></main>
```

On failure, set `data-terminal-smoke="failed"` and visible error text.

- [ ] **Step 2: Write the Vite smoke runner**

The runner starts Vite programmatically on loopback port 0 with `configFile: smoke/vite.config.ts`, opens Chromium with package-owned Playwright, waits for `[data-terminal-smoke="ready"]`, and asserts:

- text is `red caféplain`;
- two row nodes exist;
- three run spans exist;
- the loaded resource list contains exactly one URL ending in `.wasm`;
- the page has no console error or unhandled page error.

Close browser and Vite in `finally`.

- [ ] **Step 3: Run the Vite proof**

```bash
npm --prefix packages/terminal exec -- playwright install chromium
npm --prefix packages/terminal run smoke:vite
```

Expected: exit 0 with `Vite smoke loaded vt_core_bg.wasm and painted 2 rows / 3 runs.`

- [ ] **Step 4: Add the frontend file dependency and pre-hooks**

Add:

```json
"@operator/terminal-react": "file:../packages/terminal/ts/react"
```

Add `terminal:build` plus `pretypecheck`, `pretest`, `predev:tauri`, `predev:web`, `pretauri:dev`, `pretauri:build`, and `pretauri:release`. Each pre-hook calls `npm run terminal:build`; `terminal:build` calls `npm --prefix ../packages/terminal run build`. The incremental WASM script makes repeated hooks cheap.

Do not import the package into `TerminalPane` or any production renderer file in Phase 0.

- [ ] **Step 5: Install and verify the frontend boundary**

```bash
npm --prefix frontend install
npm run frontend:typecheck
npm --prefix frontend run test
```

Expected: the lockfile records the file dependency, TypeScript passes, and the existing frontend suite passes after its pretest package build.

- [ ] **Step 6: Commit Vite proof and dependency wiring**

```bash
git add packages/terminal/smoke packages/terminal/scripts/smoke-vite.mjs packages/terminal/package.json packages/terminal/package-lock.json frontend/package.json frontend/package-lock.json
git commit -m "test(terminal): prove Vite WASM loading"
```

---

### Task 8: Prove the same smoke page inside an optimized Tauri binary and CI

**Files:**
- Create: `packages/terminal/scripts/smoke-tauri.mjs`
- Modify: `packages/terminal/smoke/main.tsx`
- Modify: `packages/terminal/smoke/vite.config.ts`
- Modify: `packages/terminal/package.json`
- Create: `.github/workflows/terminal.yml`
- Modify: `.github/workflows/frontend.yml`

**Interfaces:**
- Produces `npm --prefix packages/terminal run smoke:tauri`.
- Uses `TERMINAL_SMOKE_REPORT_URL` only at Vite build time; it is never read by Operator production code.
- Produces package CI on Ubuntu and optimized Tauri smoke on macOS.

- [ ] **Step 1: Extend the page with a bounded reporter**

When `import.meta.env.TERMINAL_SMOKE_REPORT_URL` is present, POST exactly. `smoke/vite.config.ts` exposes this one build-time value with Vite's `define`; do not rely on the default `VITE_` env-prefix behavior.

```json
{
	"status": "ready",
	"text": "red caféplain",
	"rows": 2,
	"runs": 3
}
```

The URL is accepted only when protocol is `http:` and hostname is `127.0.0.1`, `localhost`, or `[::1]`. Reporter failure changes the smoke state to failed.

- [ ] **Step 2: Implement the optimized Tauri runner**

The runner:

1. starts a loopback HTTP server on port 0 with a random unguessable report path and a 16 KiB body limit;
2. builds `smoke/dist` with the report URL injected;
3. invokes `npm --prefix frontend run tauri:build -- --no-bundle --ci --config <JSON>` where the merge sets `build.beforeBuildCommand` to empty and `build.frontendDist` to `../../packages/terminal/smoke/dist` relative to `frontend/src-tauri`;
4. launches `frontend/src-tauri/target/release/operator` or `.exe` with absolute `OPERATOR_DATA_DIR` and `OPERATOR_RUN_FILE` under a new `~/.operator/terminal-smoke/<random>` directory plus `OPERATOR_TAURI_TERMINAL_BENCHMARK=1`;
5. waits at most 60 seconds for the exact report and rejects early process exit;
6. terminates the whole process group, closes the server, and removes only its exact per-run state directory in `finally`.

Use `execFile`/`spawn` argument arrays. Never invoke a shell command string and never delete the shared `~/.operator/terminal-smoke` parent.

The report endpoint must answer `OPTIONS` and `POST`, set `Access-Control-Allow-Origin: *`, allow `Content-Type`, reject every other method/path, and accept the payload only once. This is required because the embedded Tauri page and the loopback reporter have different origins; without preflight/CORS handling, a correct WASM load would be reported as a smoke failure. The random path, loopback bind, exact payload validation, one-shot acceptance, and server teardown bound the wildcard to this test process.

- [ ] **Step 3: Run the release smoke locally**

```bash
npm --prefix packages/terminal run smoke:tauri
```

Expected: Tauri performs an optimized `release` build, the embedded page POSTs the exact ready payload, and the command prints `Tauri release smoke loaded vt_core_bg.wasm and painted 2 rows / 3 runs.`

- [ ] **Step 4: Add package CI**

`terminal.yml` has:

- an Ubuntu job installing Node 24, Rust 1.96.0 with the WASM target, `wasm-bindgen-cli 0.2.127`, package npm dependencies, and Playwright Chromium; it runs Cargo fmt/clippy/test, boundary tests/check, TypeScript build/tests, and Vite smoke;
- a macOS 14 job doing the same Rust/WASM setup, `npm ci` in both package and frontend, and `npm --prefix packages/terminal run smoke:tauri`;
- path filters for `packages/terminal/**`, `frontend/package*.json`, `frontend/src-tauri/**`, and the workflow itself.

Update both frontend workflow jobs, because `renderer-smoke` starts `dev:web` and therefore triggers the new `predev:web` hook:

- add `packages/terminal/**` to pull-request path filters;
- include `packages/terminal/package-lock.json` in each Node cache dependency path;
- before `npm ci` in `frontend`, install Rust 1.96.0 with the WASM target, install `wasm-bindgen-cli 0.2.127`, and run `npm ci --prefix ../packages/terminal`;
- in the `test` job, run `npm --prefix ../packages/terminal run check:boundaries` before frontend typecheck;
- in `renderer-smoke`, retain the existing Playwright setup and let `predev:web` perform the incremental package build.

Do not add a third duplicate package build step to either job; the frontend pre-hooks are the single frontend-owned entry point.

- [ ] **Step 5: Run the workflow commands locally**

```bash
cargo fmt --check --manifest-path packages/terminal/Cargo.toml
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
cargo test --manifest-path packages/terminal/Cargo.toml --workspace
node --test packages/terminal/scripts/check-boundaries.test.mjs
npm --prefix packages/terminal run check:boundaries
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
npm --prefix packages/terminal run smoke:vite
npm --prefix packages/terminal run smoke:tauri
```

Expected: every command exits 0 with fresh output.

- [ ] **Step 6: Commit runtime loading proof and CI**

```bash
git add packages/terminal/scripts/smoke-tauri.mjs packages/terminal/smoke packages/terminal/package.json packages/terminal/package-lock.json .github/workflows/terminal.yml .github/workflows/frontend.yml
git commit -m "ci(terminal): prove optimized Tauri WASM loading"
```

---

### Task 9: Move the terminal benchmark gate into the package and record xterm

**Files:**
- Create: `packages/terminal/bench/scenarios.json`
- Create: `packages/terminal/bench/schema.mjs`
- Create: `packages/terminal/bench/schema.test.mjs`
- Create: `packages/terminal/bench/workloads.mjs`
- Create: `packages/terminal/bench/workloads.test.mjs`
- Create: `packages/terminal/bench/adapters/xterm.ts`
- Create: `packages/terminal/bench/harness.ts`
- Create: `packages/terminal/bench/index.html`
- Create: `packages/terminal/bench/main.ts`
- Create: `packages/terminal/bench/vite.config.ts`
- Create: `packages/terminal/bench/runner.mjs`
- Create: `packages/terminal/bench/baselines/darwin-arm64-xterm.json`
- Modify: `packages/terminal/package.json`
- Modify: `packages/terminal/package-lock.json`
- Modify: `packages/terminal/README.md`

**Interfaces:**
- Produces `npm run bench:terminal -- --renderer xterm --scenario vtebench|large-output|input-latency`.
- Produces `npm run bench:baseline -- --renderer xterm --record`.
- Produces result schema `operator.terminal-benchmark.v1`.
- Later phases add a DOM adapter to this harness; do not implement it now.

- [ ] **Step 1: Write schema and workload tests first**

The scenario file preserves:

```json
{
	"vtebench": { "warmups": 3, "samples": 10, "unit": "workloads-per-second", "columns": 120, "rows": 40, "scrollback": 5000, "payloadBytes": 8388608, "seed": 7000 },
	"large-output": { "warmups": 3, "samples": 10, "unit": "bytes-per-second", "columns": 120, "rows": 40, "scrollback": 5000, "outputBytes": 16777216 },
	"input-latency": { "warmups": 3, "samples": 10, "unit": "milliseconds", "columns": 120, "rows": 40, "scrollback": 5000 }
}
```

Tests require deterministic byte-for-byte workload output for a fixed seed, exact configured byte lengths, only finite positive samples, exactly 10 measured samples, nearest-rank p95, no absolute path/PID/environment fields, and hardware/runtime metadata.

- [ ] **Step 2: Run the Node tests and confirm red**

```bash
node --test packages/terminal/bench/schema.test.mjs packages/terminal/bench/workloads.test.mjs
```

Expected: FAIL because the schema and workload modules do not exist.

- [ ] **Step 3: Implement deterministic equal-input workloads**

`large-output` is exactly 16 MiB of printable `x` bytes delivered in 64 KiB chunks.

`vtebench` is an original seeded generator, not copied code: it emits an 8 MiB mix of printable rows, CUP cursor addresses, EL erase-line, SGR foreground/reset, CRLF, and scroll-producing lines against the fixed 120x40 geometry. Record `workload: "vtebench-random-write-v1"`, `seed: 7000`, and a SHA-256 digest in every result. Every renderer must consume the same generated bytes; changing the generator name, seed, or digest invalidates old baselines.

`input-latency` timestamps immediately before dispatching a synthetic printable-key event through the adapter, loops the adapter's input callback directly back as one output byte, and completes only after the renderer's next painted frame.

- [ ] **Step 4: Implement the xterm adapter and browser harness**

The adapter owns xterm 5.5.0 with fixed columns/rows/scrollback and matches Operator's production renderer order: activate `@xterm/addon-webgl` 0.19.0 first, recover to `@xterm/addon-canvas` 0.7.0 on activation failure or context loss, and record the resulting renderer kind with every sample. It exposes:

```ts
export interface BenchmarkRenderer {
	mount(host: HTMLElement, geometry: Geometry): Promise<void>;
	write(bytes: Uint8Array): Promise<void>;
	onInput(listener: (data: string) => void): () => void;
	waitForPaint(): Promise<number>;
	dispose(): void;
}
```

Resolve `write` only from xterm's write callback, then resolve `waitForPaint` from `onRender` followed by one `requestAnimationFrame`. The harness warms up three times, clears the terminal between samples, collects ten samples, and sends only results—not terminal contents—to the runner.

- [ ] **Step 5: Implement the runner and result writer**

The runner accepts only the documented flags, starts Vite on loopback port 0, opens package-owned Chromium, and writes uncommitted runs under `bench/results/`. With `--record`, it writes the platform/architecture baseline path only when:

- git is clean before the run;
- renderer is `xterm`;
- all three scenarios were measured in the same invocation;
- renderer version is exactly `5.5.0`;
- workload digests match the scenario generator;
- each scenario has 3 warmups and 10 samples.

Result fields are `schema`, `recordedAt`, `commit`, `platform`, `architecture`, `cpu`, `logicalCores`, `physicalMemory`, `browserVersion`, `displayScale`, `renderer`, `rendererVersion`, `rendererKind`, and per-scenario configuration/samples/median/p95/unit/workloadDigest. Do not record usernames, paths, process IDs, terminal text, or environment values. A single baseline invocation must use one renderer kind for all samples; a WebGL-to-canvas recovery aborts and must be rerun rather than mixing kinds.

- [ ] **Step 6: Run unit and dry-run benchmarks**

```bash
node --test packages/terminal/bench/schema.test.mjs packages/terminal/bench/workloads.test.mjs
npm --prefix packages/terminal run bench:terminal -- --renderer xterm --scenario input-latency
npm --prefix packages/terminal run bench:terminal -- --renderer xterm --scenario large-output
npm --prefix packages/terminal run bench:terminal -- --renderer xterm --scenario vtebench
```

Expected: each command writes a valid result under ignored `bench/results/` and exits 0.

- [ ] **Step 7: Record the reference-machine xterm baseline**

Commit all code first so the record gate sees a clean tree:

```bash
git add packages/terminal/bench packages/terminal/package.json packages/terminal/package-lock.json packages/terminal/README.md
git commit -m "test(terminal): add package benchmark harness"
npm --prefix packages/terminal run bench:baseline -- --renderer xterm --record
```

Expected on this reference machine: `bench/baselines/darwin-arm64-xterm.json` is created with three complete scenario results and real measured numbers. Open the JSON and verify `rendererVersion`, sample counts, units, workload digests, platform, and architecture before staging it.

- [ ] **Step 8: Validate and commit the measured baseline**

```bash
node packages/terminal/bench/schema.mjs packages/terminal/bench/baselines/darwin-arm64-xterm.json
git diff --check
git add packages/terminal/bench/baselines/darwin-arm64-xterm.json
git commit -m "perf(terminal): record xterm baseline"
```

Expected: schema validation exits 0 and the commit contains measured metadata only.

---

### Task 10: Close Phase 0 with the full acceptance matrix

**Files:**
- Modify only if a verified command exposes a defect: files already owned by Tasks 1-9.

**Interfaces:**
- Produces no new feature. This task verifies the Phase 0 contract and stops before Phase 1.

- [ ] **Step 1: Prove a clean-tree WASM build**

Remove only ignored package build outputs, then rebuild:

```bash
git clean -ndX packages/terminal
git clean -fdX packages/terminal
npm --prefix packages/terminal ci
npm --prefix packages/terminal run build:wasm
test -s packages/terminal/ts/core/wasm/vt_core_bg.wasm
```

Before running the second command, inspect the dry-run output and stop if it names anything outside `packages/terminal/node_modules`, `packages/terminal/target`, child `dist`, generated `ts/core/wasm`, `smoke/dist`, or ignored benchmark results.

- [ ] **Step 2: Run every package gate**

```bash
cargo fmt --check --manifest-path packages/terminal/Cargo.toml
cargo clippy --manifest-path packages/terminal/Cargo.toml --workspace --all-targets -- -D warnings
cargo test --manifest-path packages/terminal/Cargo.toml --workspace --locked
node --test packages/terminal/scripts/check-boundaries.test.mjs
npm --prefix packages/terminal run check:boundaries
npm --prefix packages/terminal run build
npm --prefix packages/terminal test
node --test packages/terminal/bench/schema.test.mjs packages/terminal/bench/workloads.test.mjs
node packages/terminal/bench/schema.mjs packages/terminal/bench/baselines/darwin-arm64-xterm.json
```

Expected: every command exits 0; the intentionally bad boundary fixtures prove the checker fails correctly while the real tree passes.

- [ ] **Step 3: Re-run all three loading environments**

```bash
node -e 'const fs=require("node:fs"),c=require("node:crypto");process.stdout.write(c.createHash("sha256").update(fs.readFileSync("packages/terminal/ts/core/wasm/vt_core_bg.wasm")).digest("hex")+"\n")' | tee /tmp/operator-terminal-wasm-before.sha256
npm --prefix packages/terminal run test --workspace @operator/terminal-core
npm --prefix packages/terminal run smoke:vite
npm --prefix packages/terminal run smoke:tauri
node -e 'const fs=require("node:fs"),c=require("node:crypto");process.stdout.write(c.createHash("sha256").update(fs.readFileSync("packages/terminal/ts/core/wasm/vt_core_bg.wasm")).digest("hex")+"\n")' > /tmp/operator-terminal-wasm-after.sha256
cmp /tmp/operator-terminal-wasm-before.sha256 /tmp/operator-terminal-wasm-after.sha256
rm /tmp/operator-terminal-wasm-before.sha256 /tmp/operator-terminal-wasm-after.sha256
```

Expected: Vitest loads bytes from `fs.readFile`, Vite loads one emitted `.wasm` URL, the optimized Tauri binary posts the exact two-row/three-run result, and the digest comparison proves no environment rebuilt or substituted the module between those proofs. Record the printed pre-run digest in the final report before removing the temporary files.

- [ ] **Step 4: Run the repository acceptance commands**

```bash
npm run frontend:typecheck
npm run lint
git diff --check
git status --short
```

Expected: typecheck and lint exit 0; `git diff --check` is silent; status contains no generated WASM, `target`, `dist`, smoke, benchmark-result, or state files.

- [ ] **Step 5: Audit Phase 0 scope and acceptance**

Run:

```bash
rg -n "OSC 133|OSC 7000|input-ready|input-released|sum.?tree|pipe-pane|TerminalPane|XtermTerminal" packages/terminal --glob '!README.md' --glob '!CHANGELOG.md' --glob '!bench/**'
find packages/terminal -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.mjs' -o -name '*.rs' -o -name '*.go' \) -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/dist/*' -not -path '*/ts/core/wasm/*' -exec awk 'FNR==601 { print FILENAME }' {} +
```

Expected: the first command finds no Phase 1 implementation and the second prints no file. Confirm manually that no frontend source imports the terminal package yet.

- [ ] **Step 6: Stop at the checkpoint**

Do not begin Phase 1. Report:

- the exact commit containing the baseline;
- the three measured xterm medians/p95 values;
- confirmation that Vitest, Vite, and optimized Tauri used the same generated `.wasm` digest;
- each acceptance command and exit status;
- any remaining environmental caveat without weakening a failed gate into a pass.
