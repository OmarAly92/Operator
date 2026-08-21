# Terminal measurement correctness fix report

## Status

Implemented the terminal correctness fixes from base `751744d15`.

The benchmark still uses the Go PTY to daemon mux WebSocket to production `XtermTerminal` byte path. No terminal bytes, credentials, or terminal contents pass through a Tauri command or enter benchmark evidence.

## Root causes and fixes

### Workload acknowledgement ordering

The mux data listener incremented the render-visible pending workload count before xterm had finished parsing the marker-containing write. A render already queued for unrelated output could therefore acknowledge the workload.

Marker detection now reserves the requested workload immediately, passes the marker chunk through the real terminal write callback, and exposes the pending acknowledgement only after that callback completes. The next render then emits the timestamp-only workload acknowledgement.

### Fixed benchmark geometry

The previous benchmark passed 120 columns and 40 rows only as xterm constructor dimensions. Production FitAddon remained active and could replace that grid based on the benchmark window size.

`XtermTerminal` now has an optional fixed geometry mode used only by the terminal benchmark. Normal call sites retain all existing fitting, settle timers, font readiness, ResizeObserver, window resize, and convergence behavior. The benchmark disables those fits, retains the configured 120×40 live grid, and checks the live terminal dimensions before every warmup and measured workload. A drift fails before input is sent.

### Renderer recovery boundary

The previous context-loss callback acknowledged renderer recovery as soon as CanvasAddon loaded. Recovery now subscribes after the fallback loads and acknowledges only on the first subsequent xterm render.

### Loopback validation

The Tauri runner URL validator accepted URL credentials. `tauriDaemonUrl` now accepts only HTTP(S) URLs whose host is exactly `127.0.0.1`, `localhost`, or `[::1]`, with no username or password. Paths, query strings, and fragments are removed before the URL reaches the harness.

### Real production component coverage

The harness suite no longer mocks `XtermTerminal`. It renders the real production component and mocks only xterm/browser/system boundaries. Coverage observes the mounted xterm surface, mux attachment and cleanup, delayed writes, fixed live geometry, drift failure, renderer transition and recovered frame, reconnect, disposal, split and replayed markers, content-free acknowledgements, and Windows workload construction.

### Native runtime metadata

The terminal page no longer reports `navigator.userAgent` as native metadata. In explicit `OPERATOR_TAURI_TERMINAL_BENCHMARK=1` context, Rust registers `terminal_benchmark_runtime_identity`, which returns the native OS/architecture, Tauri runtime version, and the platform WebView version returned by Tauri/Wry. The benchmark launcher forces that exact context value.

The command is absent in normal and state-audit contexts, invalid context values stop startup, and WebView-version lookup errors propagate. The renderer also rejects empty metadata and does not emit renderer evidence until native metadata succeeds.

### Invalidated result

`frontend/perf/results/darwin-arm64-tauri-large-output.json` was removed. Its timings were produced with the early workload acknowledgement, an unverified live grid, and user-agent metadata. A faithful native rerun was not available for this fix, so retaining the file would preserve false evidence.

## TDD evidence

The first focused harness RED ran before production edits and failed five intended regressions:

- all accepted `tauriDaemonUrl` cases failed because the validator was not exported;
- an unrelated render acknowledged workload completion before the delayed write callback;
- FitAddon changed the claimed 120×40 grid to 80×24;
- a 119×40 live grid still sent the workload;
- context loss acknowledged recovery immediately after CanvasAddon load.

After the minimal TypeScript changes, the harness GREEN passed 19/19 tests. Restored behavior coverage then raised the final harness suite to 20 tests.

The native-runtime RED separately failed because `perf/terminal/runtime.ts`, `native_runtime_identity`, and `terminal_benchmark_context` did not exist. After implementation, the runtime TypeScript tests and Rust tests passed.

## Verification

- Focused Vitest: 72/72 across the harness, native-runtime boundary, and existing production Xterm suite.
- Benchmark contracts: 51/51 Node tests.
- Frontend TypeScript: repository typecheck passed; explicit terminal perf entry/test compile passed.
- Biome: terminal source, tests, Vite config, runner, and production terminal component passed.
- Rust: `cargo fmt --check`, all unit/doc tests, and clippy with warnings denied passed.
- Terminal Vite build: 206 modules transformed successfully. The existing single-chunk size warning remains non-fatal; generated output was moved outside the repository after verification.
- `node --check scripts/benchmark-terminal.mjs` and owned-path diff checks passed.

## Guard review

The production changes are limited to the current benchmark callers and preserve default terminal fitting. Error paths propagate instead of falling back to browser metadata. New test doubles are restricted to third-party xterm addons, browser timing, Tauri invocation, and the mux boundary; the internal production terminal component is real.

## Concerns

- No replacement native performance result is committed.
- Windows/WebView2 and Linux/WebKitGTK native runs, including Linux compositing variants, remain unexecuted.
- Native `vtebench`, installed/signed runtime measurements, resource accounting, input/reconnect distributions, and the visual correctness matrix remain outside this fix.
- The terminal benchmark bundle retains its existing large single-chunk warning because it intentionally loads the production renderer stack.
