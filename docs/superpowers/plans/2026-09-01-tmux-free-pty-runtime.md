# tmux-free PTY runtime — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace tmux with a per-session `opr pty-host` process on every platform, so the agent's bytes reach the renderer untransformed and the terminal scrolls like Warp.

**Architecture:** Generalize the existing Windows-only `conpty` runtime into a platform-neutral `ptyhost`. The host owns the PTY, fans raw bytes to clients on the hot path, and feeds a **passive** `vt-core` WASM parser beside that path to answer headless queries (`GetOutput`, `CaptureState`). Nothing parses or re-renders between the agent and the screen.

**Tech Stack:** Go 1.x (`creack/pty`, `wazero`), Rust (`vt-core` → `wasm32-unknown-unknown`), existing `frontend/perf` harness.

**Spec:** `docs/superpowers/specs/2026-09-01-tmux-free-pty-runtime-design.md`

## Global Constraints

- **`CGO_ENABLED=0` must keep working.** `packages/build-binaries.sh:33` and four CI workflows cross-compile four platform binaries from one machine. No task may introduce cgo.
- **The hot path stays parse-free.** PTY read → broadcast → client write. Any task that puts the parser between the agent and a client has failed, regardless of tests passing.
- **Warp's loop constants**, adopted verbatim: `READ_BUFFER_SIZE = 0x4_0000` (256KB), `MAX_LOCKED_READ = 0x1_0000` (64KB), client-write coalescing at 60Hz — **under load only**. An isolated write (keystroke echo) flushes immediately; the 16ms window arms only when a flush already happened within the last frame. Task 6 implements this; no other task may assume it exists before then.
- **No new comments beyond what a reader needs** — this repo documents rationale, not mechanics. Match surrounding density.
- **Go tests:** `cd backend && go test ./...`. **Rust:** `cd packages/terminal && cargo test`.
- Existing frame layout is fixed: `[1-byte type][4-byte BE length][payload]` (`conpty/proto.go`). New message types append; existing `0x01`–`0x08` keep their meanings.
- Every task must leave `go build ./...` green on all three GOOS values: `GOOS=darwin`, `GOOS=linux`, `GOOS=windows`.

---

### Task 1: WASM parser throughput spike — DECISION GATE

Everything downstream assumes `vt-core` in `wazero` is fast enough. Find out first. If it is not, the parser decision flips to a Go emulator and Tasks 7–9 change shape.

**Files:**
- Create: `packages/terminal/crates/vt-host/Cargo.toml`
- Create: `packages/terminal/crates/vt-host/src/lib.rs`
- Create: `backend/internal/adapters/runtime/conpty/vtwasm/bench_test.go`
- Modify: `packages/terminal/Cargo.toml` (workspace members)

**Interfaces:**
- Consumes: `vt_core::TerminalCore::{new, feed, snapshot, alt_screen_active, resize}` — note `TerminalCore::new(columns, scrollback_rows)` takes no rows and defaults to 24; rows are only ever set via `resize`, so `vt_new` must resize immediately or every alt-screen render is 24 rows tall
- Produces: a wasm module exporting `vt_new(cols: u32, rows: u32, scrollback: u32) -> u32`, `vt_feed(handle: u32, ptr: u32, len: u32)`, `vt_resize(handle: u32, cols: u32, rows: u32)`, `vt_alt_active(handle: u32) -> u32`, `vt_render(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32` (returns bytes written; `0` = genuinely empty screen; `0xFFFF_FFFF` = bad handle or snapshot failure; `0xFFFF_FFFE` = does not fit in `out_cap` — the three cases must stay distinguishable so the Go side never falls back to raw ring bytes on error), `vt_alloc(len: u32) -> u32`, `vt_free(ptr: u32, len: u32)`

- [x] **Step 1: Create the C-ABI wasm shim crate**

`packages/terminal/crates/vt-host/Cargo.toml`:

```toml
[package]
name = "vt-host"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
vt-core = { path = "../vt-core" }
```

`packages/terminal/crates/vt-host/src/lib.rs`. Note this is a plain C ABI, not `wasm-bindgen` — `wazero` cannot run wasm-bindgen's JS glue:

```rust
use std::cell::RefCell;
use std::collections::HashMap;
use vt_core::TerminalCore;

thread_local! {
    static CORES: RefCell<HashMap<u32, TerminalCore>> = RefCell::new(HashMap::new());
    static NEXT_ID: RefCell<u32> = const { RefCell::new(1) };
}

#[no_mangle]
pub extern "C" fn vt_alloc(len: u32) -> u32 {
    let mut buf = Vec::<u8>::with_capacity(len as usize);
    let ptr = buf.as_mut_ptr() as u32;
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn vt_free(ptr: u32, len: u32) {
    unsafe { drop(Vec::from_raw_parts(ptr as *mut u8, 0, len as usize)) };
}

#[no_mangle]
pub extern "C" fn vt_new(cols: u32, rows: u32, scrollback: u32) -> u32 {
    let Ok(mut core) = TerminalCore::new(cols as usize, scrollback as usize) else {
        return 0;
    };
    core.resize(cols as usize, rows as usize);
    NEXT_ID.with(|n| {
        let mut n = n.borrow_mut();
        let id = *n;
        *n += 1;
        CORES.with(|c| c.borrow_mut().insert(id, core));
        id
    })
}

#[no_mangle]
pub extern "C" fn vt_resize(handle: u32, cols: u32, rows: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.resize(cols as usize, rows as usize);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_feed(handle: u32, ptr: u32, len: u32) {
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.feed(bytes);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_alt_active(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) if core.alt_screen_active() => 1,
        _ => 0,
    })
}

pub const RENDER_ERR: u32 = u32::MAX;
pub const RENDER_TOO_BIG: u32 = u32::MAX - 1;

// Writes the last `lines` rendered rows as UTF-8 into out_ptr, returning the
// byte count written. 0 means a genuinely empty screen; RENDER_ERR means a bad
// handle or snapshot failure; RENDER_TOO_BIG means out_cap is too small. The
// three must stay distinct: the caller treats only RENDER_* as failures, never
// an empty screen. When the alternate screen is active the alt grid is rendered
// instead, matching what `tmux capture-pane` returns for a full-screen app.
#[no_mangle]
pub extern "C" fn vt_render(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else { return RENDER_ERR };
        let Ok(snapshot) = core.snapshot() else { return RENDER_ERR };

        let mut text = String::new();
        if let Some(alt) = &snapshot.alt {
            for (start, end) in &alt.row_ranges {
                text.push_str(
                    std::str::from_utf8(&alt.content[*start as usize..*end as usize]).unwrap_or(""),
                );
                text.push('\n');
            }
        } else {
            let total = snapshot.row_count();
            let first = total.saturating_sub(lines as usize);
            for i in first..total {
                text.push_str(snapshot.row_text(i));
                text.push('\n');
            }
        }

        let bytes = text.as_bytes();
        if bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
        }
        bytes.len() as u32
    })
}
```

Add `"crates/vt-host"` to the workspace `members` in `packages/terminal/Cargo.toml`.

- [x] **Step 2: Build the wasm module**

```bash
cd packages/terminal && cargo build --release -p vt-host --target wasm32-unknown-unknown
ls -la target/wasm32-unknown-unknown/release/vt_host.wasm
```

Expected: the `.wasm` file exists. If the target is missing: `rustup target add wasm32-unknown-unknown`.

- [x] **Step 3: Write the throughput benchmark**

`backend/internal/adapters/runtime/conpty/vtwasm/bench_test.go`:

```go
package vtwasm

import (
	"context"
	"os"
	"testing"
	"time"
)

// BenchmarkFeed16MB is the decision gate for the WASM parser. It feeds the same
// volume as the large-output perf scenario in 64KB slices, which is how the host
// will drive it.
func BenchmarkFeed16MB(b *testing.B) {
	wasmPath := os.Getenv("VT_HOST_WASM")
	if wasmPath == "" {
		b.Skip("set VT_HOST_WASM to the built vt_host.wasm")
	}
	module, err := os.ReadFile(wasmPath)
	if err != nil {
		b.Fatalf("read wasm: %v", err)
	}

	payload := make([]byte, 16<<20)
	for i := range payload {
		payload[i] = byte('a' + i%26)
		if i%80 == 79 {
			payload[i] = '\n'
		}
	}

	b.ResetTimer()
	for range b.N {
		parser, err := New(context.Background(), module, 120, 40, 1000)
		if err != nil {
			b.Fatalf("new parser: %v", err)
		}
		start := time.Now()
		for offset := 0; offset < len(payload); offset += 64 << 10 {
			end := min(offset+64<<10, len(payload))
			if err := parser.Feed(payload[offset:end]); err != nil {
				b.Fatalf("feed: %v", err)
			}
		}
		b.ReportMetric(float64(len(payload))/time.Since(start).Seconds()/(1<<20), "MB/s")
		_ = parser.Close()
	}
}
```

- [x] **Step 4: Write the minimal wazero binding the benchmark needs**

`backend/internal/adapters/runtime/conpty/vtwasm/vtwasm.go`:

```go
// Package vtwasm runs the vt-core terminal parser as a WebAssembly module via
// wazero, keeping the backend free of cgo. The parser is passive: it never sits
// between the agent's PTY and an attached client.
package vtwasm

import (
	"context"
	"fmt"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

type Parser struct {
	runtime wazero.Runtime
	module  api.Module
	handle  uint32
	ctx     context.Context
}

func New(ctx context.Context, wasmModule []byte, cols, rows, scrollback uint32) (*Parser, error) {
	rt := wazero.NewRuntime(ctx)
	mod, err := rt.Instantiate(ctx, wasmModule)
	if err != nil {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: instantiate: %w", err)
	}
	res, err := mod.ExportedFunction("vt_new").Call(ctx, uint64(cols), uint64(rows), uint64(scrollback))
	if err != nil || len(res) == 0 || res[0] == 0 {
		_ = rt.Close(ctx)
		return nil, fmt.Errorf("vtwasm: vt_new failed: %w", err)
	}
	return &Parser{runtime: rt, module: mod, handle: uint32(res[0]), ctx: ctx}, nil
}

func (p *Parser) Feed(bytes []byte) error {
	if len(bytes) == 0 {
		return nil
	}
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, uint64(len(bytes)))
	if err != nil {
		return fmt.Errorf("vtwasm: alloc: %w", err)
	}
	ptr := uint32(res[0])
	defer p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(ptr), uint64(len(bytes)))

	if !p.module.Memory().Write(ptr, bytes) {
		return fmt.Errorf("vtwasm: write %d bytes at %d out of range", len(bytes), ptr)
	}
	_, err = p.module.ExportedFunction("vt_feed").Call(p.ctx, uint64(p.handle), uint64(ptr), uint64(len(bytes)))
	return err
}

func (p *Parser) Close() error { return p.runtime.Close(p.ctx) }
```

Add the dependency: `cd backend && go get github.com/tetratelabs/wazero@latest`

- [x] **Step 5: Run the benchmark and record the number**

```bash
cd backend && VT_HOST_WASM=../packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm \
  go test ./internal/adapters/runtime/conpty/vtwasm/ -bench=Feed16MB -benchtime=1x -run=^$
```

**Gate:** record the MB/s. The `large-output` scenario pushes 16MB.

- **≥ 50 MB/s** — comfortable. Proceed with the WASM design as specced.
- **10–50 MB/s** — workable, since the parser is off the hot path and may lag. Proceed, but note it in the plan's results and re-check under `active-memory`.
- **< 10 MB/s** — STOP. Report to the user; the parser decision flips to a Go emulator held to `packages/terminal/protocol/alt-vectors`, and Tasks 7–9 must be rewritten before continuing.

**RESULT (2026-09-01, initial run): ~1.28–1.29 MB/s across two runs (`-benchtime=1x` and `-benchtime=2x`), on darwin/arm64 (Apple M1 Max). This was in the < 10 MB/s STOP bucket.** Per gate policy: STOPPED and reported to the user.

**Root cause found and fixed (commit `8eb799c46`, landed during the gate review, upstream of this session's continuation):** the STOP number was not WASM overhead. Native `vt-core` measured only 4.6 MB/s on the same bytes — `scroll_up` copied the whole grid cell-by-cell on every newline. The grid is now a ring of rows (`crates/vt-core/src/screen.rs`: `phys_start`/`rotate_region_up`/`materialize`), taking native throughput 4.6 → 57.1 MB/s. Separately, the wasm build was missing `+bulk-memory`, so every memmove was a byte loop; the target features are now pinned in `packages/terminal/.cargo/config.toml` (~2x on top).

**RESULT (2026-09-01, re-run after the fix, reproduced independently by the controller session): 16.19 MB/s** (`BenchmarkFeed16MB-10  5  1024805633 ns/op  16.19 MB/s`, `-benchtime=5x`, plain `cargo build --release -p vt-host --target wasm32-unknown-unknown` from `packages/terminal` with no manual `RUSTFLAGS` — `.cargo/config.toml` applies the pinned target features automatically). Matches the reported 16.5–18.3 MB/s range within run-to-run variance. **This is in the 10–50 MB/s "workable" bucket: proceed with the WASM design as specced.** Per that bucket's rule, parser cost must be re-checked under the `active-memory` scenario when Task 14 runs.

Full benchmark output and command for the original STOP run: `.superpowers/sdd/2026-09-01-tmux-free-pty-runtime/task-1-report.md`. Gate is now **PASSED (workable band)** — plan execution resumes at Task 2.

- [x] **Step 6: Commit**

```bash
git add packages/terminal/crates/vt-host packages/terminal/Cargo.toml backend/internal/adapters/runtime/conpty/vtwasm backend/go.mod backend/go.sum
git commit -m "feat(terminal): vt-core C-ABI wasm shim and wazero throughput spike"
```

---

### Task 2: Rename `conpty` → `ptyhost`

Mechanical, and worth its own commit so later diffs are readable.

**Files:**
- Rename: `backend/internal/adapters/runtime/conpty/` → `backend/internal/adapters/runtime/ptyhost/`
- Modify: `backend/internal/adapters/runtime/runtimeselect/runtimeselect.go`
- Modify: `backend/internal/cli/ptyhost.go`
- Modify: `backend/internal/terminal/doc.go` (mentions conpty)

- [x] **Step 1: Move the package and rewrite the identifier** (fix round 1: `backend/internal/terminal/doc.go` and `attachment.go` prose also updated, commit `0505c3e1f`)

```bash
cd backend/internal/adapters/runtime
git mv conpty ptyhost
cd ptyhost && sed -i '' 's/^package conpty$/package ptyhost/' *.go
sed -i '' 's/[[:<:]]conpty\./ptyhost./g; s/"conpty: /"ptyhost: /g; s/conpty spawn:/ptyhost spawn:/g' *.go
cd ../../../.. && grep -rln "runtime/conpty" --include="*.go" . | xargs sed -i '' 's#runtime/conpty#runtime/ptyhost#g'
grep -rln "conpty\." --include="*.go" internal | xargs sed -i '' 's/[[:<:]]conpty\./ptyhost./g'
```

(BSD sed on macOS: `[[:<:]]` is the word boundary — `\b` silently matches
nothing. `xargs -r` is a GNU flag; BSD xargs skips empty input by default.)

Keep the `conptyConn` type name and `newConPTY` function — those are genuinely ConPTY-specific and stay Windows-tagged.

- [x] **Step 2: Build for all three platforms**

```bash
cd backend && for os in darwin linux windows; do GOOS=$os go build ./... || echo "FAILED $os"; done
```

Expected: no output, three successful builds.

- [x] **Step 3: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/...`
Expected: PASS, same count as before the rename.

- [x] **Step 4: Commit** (commits `c102e9426`, `0505c3e1f`)

```bash
git add -A backend
git commit -m "refactor(runtime): rename conpty package to ptyhost"
```

---

### Task 3: Unix PTY connection behind the `ptyConn` seam

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/host_pty_unix.go`
- Create: `backend/internal/adapters/runtime/ptyhost/host_pty_unix_test.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/host_conpty_other.go` (delete the stub it replaces)

**Interfaces:**
- Consumes: `ptyConn` interface (`host.go:21`) — `io.Reader`, `io.Writer`, `Resize(cols, rows int) error`, `Close() error`, `Done() <-chan struct{}`, `ExitCode() (int, bool)`, `PID() int`
- Produces: `newPTY(cwd, shellCmd string, shellArgs []string) (ptyConn, error)` on unix, satisfying the same seam `newConPTY` satisfies on Windows

- [x] **Step 1: Write the failing test**

`host_pty_unix_test.go`:

```go
//go:build !windows

package ptyhost

import (
	"io"
	"strings"
	"testing"
	"time"
)

func TestNewPTYRunsCommandAndReportsExit(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh", []string{"-c", "printf hello; exit 3"})
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if conn.PID() <= 0 {
		t.Fatalf("PID = %d, want > 0", conn.PID())
	}

	buf := make([]byte, 64)
	n, _ := io.ReadFull(io.LimitReader(conn, 5), buf[:5])
	if got := string(buf[:n]); !strings.Contains(got, "hello") {
		t.Fatalf("read %q, want it to contain \"hello\"", got)
	}

	select {
	case <-conn.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("Done() never closed")
	}
	code, exited := conn.ExitCode()
	if !exited || code != 3 {
		t.Fatalf("ExitCode() = (%d, %v), want (3, true)", code, exited)
	}
}

func TestNewPTYResize(t *testing.T) {
	conn, err := newPTY(t.TempDir(), "/bin/sh", []string{"-c", "sleep 5"})
	if err != nil {
		t.Fatalf("newPTY: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if err := conn.Resize(100, 40); err != nil {
		t.Fatalf("Resize: %v", err)
	}
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestNewPTY -v`
Expected: FAIL — `undefined: newPTY`

- [x] **Step 3: Implement**

`host_pty_unix.go`:

```go
//go:build !windows

// host_pty_unix.go backs the ptyConn seam with a real Unix PTY. It is the
// Darwin/Linux counterpart to host_conpty_windows.go; both are only ever
// constructed inside the detached pty-host process.
package ptyhost

import (
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
)

type unixPTY struct {
	file *os.File
	cmd  *exec.Cmd
	done chan struct{}

	mu       sync.Mutex
	exitCode int
	exited   bool
}

func newPTY(cwd, shellCmd string, shellArgs []string) (ptyConn, error) {
	cmd := exec.Command(shellCmd, shellArgs...)
	cmd.Dir = cwd
	cmd.Env = os.Environ()
	file, err := pty.Start(cmd)
	if err != nil {
		return nil, err
	}
	conn := &unixPTY{file: file, cmd: cmd, done: make(chan struct{})}
	go conn.wait()
	return conn, nil
}

func (p *unixPTY) wait() {
	err := p.cmd.Wait()
	p.mu.Lock()
	p.exited = true
	if exitErr, ok := err.(*exec.ExitError); ok {
		p.exitCode = exitErr.ExitCode()
	}
	p.mu.Unlock()
	close(p.done)
}

func (p *unixPTY) Read(b []byte) (int, error)  { return p.file.Read(b) }
func (p *unixPTY) Write(b []byte) (int, error) { return p.file.Write(b) }

func (p *unixPTY) Resize(cols, rows int) error {
	return pty.Setsize(p.file, &pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)})
}

func (p *unixPTY) Close() error { return p.file.Close() }

func (p *unixPTY) Done() <-chan struct{} { return p.done }

func (p *unixPTY) ExitCode() (int, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.exitCode, p.exited
}

func (p *unixPTY) PID() int {
	if p.cmd.Process == nil {
		return 0
	}
	return p.cmd.Process.Pid
}
```

Then delete `host_conpty_other.go` and change `host_main.go` to call a build-tagged constructor. Add to `host_conpty_windows.go`:

```go
func newPTY(cwd, shellCmd string, shellArgs []string) (ptyConn, error) {
	return newConPTY(cwd, shellCmd, shellArgs)
}
```

and in `host_main.go` replace `newConPTY(cwd, shellCmd, shellArgs)` with `newPTY(cwd, shellCmd, shellArgs)`.

- [x] **Step 4: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -v`
Expected: PASS, including the two new tests.

- [x] **Step 5: Verify all platforms still build**

```bash
cd backend && for os in darwin linux windows; do GOOS=$os go build ./... || echo "FAILED $os"; done
```

- [x] **Step 6: Commit** (commit `6b672e730`)

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "feat(runtime): back the ptyConn seam with a real Unix PTY"
```

---

### Task 4: Unix detached host spawn

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/spawn_unix.go`
- Create: `backend/internal/adapters/runtime/ptyhost/spawn_unix_test.go`
- Delete: `backend/internal/adapters/runtime/ptyhost/spawn_other.go`

**Interfaces:**
- Produces: `defaultSpawnHost(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (addr string, pid int, err error)` — same signature the Windows implementation already has (`spawn_windows.go:64`)

- [x] **Step 1: Write the failing test** (with a `TestMain` re-exec dispatcher added — required so the test binary itself answers to the `pty-host` subcommand)

`spawn_unix_test.go`:

```go
//go:build !windows

package ptyhost

import (
	"context"
	"strings"
	"testing"
)

func TestDefaultSpawnHostDetachesAndReportsAddress(t *testing.T) {
	addr, pid, err := defaultSpawnHost(
		context.Background(),
		"spawn-test",
		t.TempDir(),
		[]string{"/bin/sh", "-c", "sleep 5"},
		nil,
	)
	if err != nil {
		t.Fatalf("defaultSpawnHost: %v", err)
	}
	defer stopHostProcess(pid)

	if pid <= 0 {
		t.Fatalf("pid = %d, want > 0", pid)
	}
	if !strings.HasPrefix(addr, "127.0.0.1:") {
		t.Fatalf("addr = %q, want a 127.0.0.1 address", addr)
	}
}
```

- [x] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestDefaultSpawnHost -v`
Expected: FAIL — `defaultSpawnHost: ptyhost spawn: unsupported on this OS`

- [x] **Step 3: Implement**

`spawn_unix.go`. The child is put in its own session with `Setsid` so it survives the daemon exiting — the Unix equivalent of the Windows detached-process flags:

```go
//go:build !windows

// spawn_unix.go starts the detached `opr pty-host` process on Darwin/Linux and
// reads back the address it bound. Setsid detaches it from the daemon's process
// group so the host outlives the daemon, matching the Windows spawn's intent.
package ptyhost

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const hostReadyTimeout = 10 * time.Second

func defaultSpawnHost(ctx context.Context, sessionID, cwd string, argv []string, env map[string]string) (string, int, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", 0, fmt.Errorf("ptyhost spawn: resolve executable: %w", err)
	}

	args := append([]string{"pty-host", sessionID, cwd}, argv...)
	cmd := exec.Command(exe, args...)
	cmd.Dir = cwd
	cmd.Env = os.Environ()
	for key, value := range env {
		cmd.Env = append(cmd.Env, key+"="+value)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", 0, fmt.Errorf("ptyhost spawn: stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return "", 0, fmt.Errorf("ptyhost spawn: start: %w", err)
	}

	type readyLine struct {
		port int
		err  error
	}
	ready := make(chan readyLine, 1)
	go func() {
		line, err := bufio.NewReader(stdout).ReadString('\n')
		if err != nil {
			ready <- readyLine{err: err}
			return
		}
		fields := strings.Fields(strings.TrimPrefix(strings.TrimSpace(line), "READY:"))
		if len(fields) != 2 {
			ready <- readyLine{err: fmt.Errorf("ptyhost spawn: malformed ready line %q", line)}
			return
		}
		port, err := strconv.Atoi(fields[1])
		ready <- readyLine{port: port, err: err}
	}()

	select {
	case result := <-ready:
		if result.err != nil {
			_ = cmd.Process.Kill()
			return "", 0, result.err
		}
		return fmt.Sprintf("127.0.0.1:%d", result.port), cmd.Process.Pid, nil
	case <-time.After(hostReadyTimeout):
		_ = cmd.Process.Kill()
		return "", 0, fmt.Errorf("ptyhost spawn: host did not report ready in %s", hostReadyTimeout)
	case <-ctx.Done():
		_ = cmd.Process.Kill()
		return "", 0, ctx.Err()
	}
}

func stopHostProcess(pid int) {
	if process, err := os.FindProcess(pid); err == nil {
		_ = process.Signal(syscall.SIGTERM)
	}
}
```

Verify the `READY:<pid> <port>` format against `host_main.go` before running — the parse must match what the host prints (`host_main.go:64` today: `READY:%d %d\n`).

- [x] **Step 4: Re-point the host's stdout/stderr after READY — the detachment is a fiction without this**

The host keeps logging to stderr after startup (`host_main.go:75`, `:90`), and the daemon holds the pipe. Once the daemon exits, the next stderr write gets EPIPE, and the Go runtime kills the process on EPIPE to fd 1/2 with SIGPIPE — so on Unix the "survives daemon restart" property dies the first time the orphaned host logs anything. Windows has no SIGPIPE, which is why conpty never noticed.

In `host_main.go`, immediately after printing the READY line, redirect fds 1 and 2 to a per-session log file (fall back to `os.DevNull` if it cannot be created). Unix needs a real fd-level dup so the runtime's own writes are covered:

`redirect_unix.go` (`//go:build !windows`), using `golang.org/x/sys/unix` (already a dependency) because `syscall.Dup2` does not exist on linux/arm64:

```go
func redirectStdio(f *os.File) {
	_ = unix.Dup2(int(f.Fd()), 1)
	_ = unix.Dup2(int(f.Fd()), 2)
}
```

`redirect_windows.go`: assign `os.Stdout`/`os.Stderr` (no SIGPIPE there; this is for log capture symmetry only).

Add a test: spawn a host, SIGKILL the spawner's pipe end (close it), send the host input that makes it log, and assert the host is still alive.

- [x] **Step 5: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestDefaultSpawnHost -v`
Expected: PASS

- [x] **Step 6: Commit** (commit `8b033b0f4`)

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "feat(runtime): spawn the detached pty-host on unix"
```

---

### Task 5: Select `ptyhost` behind an env override

Makes the runtime reachable on macOS for manual testing, without changing the default.

**Files:**
- Modify: `backend/internal/adapters/runtime/runtimeselect/runtimeselect.go`
- Create: `backend/internal/adapters/runtime/runtimeselect/runtimeselect_test.go`

- [ ] **Step 1: Write the failing test**

```go
package runtimeselect

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost"
)

func TestNewHonoursPtyHostOverride(t *testing.T) {
	t.Setenv("OPERATOR_RUNTIME", "ptyhost")
	if _, ok := New(nil).(*ptyhost.Runtime); !ok {
		t.Fatalf("New() = %T, want *ptyhost.Runtime when OPERATOR_RUNTIME=ptyhost", New(nil))
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/runtimeselect/ -v`
Expected: FAIL — returns `*tmux.Runtime`

- [ ] **Step 3: Implement**

In `runtimeselect.go`, replace the body of `New`:

```go
func New(_ *slog.Logger) Runtime {
	if os.Getenv("OPERATOR_RUNTIME") == "ptyhost" || runtime.GOOS == "windows" {
		return ptyhost.New(ptyhost.Options{})
	}
	return tmux.New(tmux.Options{})
}
```

- [ ] **Step 4: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/...`
Expected: PASS

- [ ] **Step 5: Manual end-to-end check**

```bash
cd frontend && OPERATOR_RUNTIME=ptyhost npm run tauri:dev
```

Start a session, confirm the agent runs and the terminal renders. Scroll it. **This is the first moment the scroll fix is observable** — compare against a tmux-backed run. Expect smooth; if it is not, stop and re-read the hot path before continuing.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/adapters/runtime/runtimeselect
git commit -m "feat(runtime): allow selecting ptyhost with OPERATOR_RUNTIME"
```

---

### Task 6: Rebuild the read loop — greedy drain and load-only coalescing

This is the performance half of the plan. Today's `pumpPTY` (`host.go:180-208`) is one 32KB `Read` → one broadcast per wakeup, with a 4KB per-client buffer (`host.go:282`); nothing in the rename changed that. Warp's constants describe the target shape.

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go`
- Create: `backend/internal/adapters/runtime/ptyhost/pump_test.go`

**Interfaces:**
- Produces: the same `broadcast(frame)` fan-out, now fed batches instead of raw reads; a `flusher` owning the coalescing clock

- [ ] **Step 1: Write the failing tests**

`pump_test.go`, complete. The fake is an `io.Pipe`, which is synchronous — every `Write` blocks until the pump reads it, so the tests are paced by the pump itself, not by sleeps. Construct the `Ring` exactly the way `RunHost` in `host_main.go` does (read it first — do not invent a constructor):

```go
package ptyhost

import (
	"bytes"
	"context"
	"io"
	"net"
	"sort"
	"sync"
	"testing"
	"time"
)

type pipePTY struct {
	r    *io.PipeReader
	w    *io.PipeWriter
	done chan struct{}
}

func newPipePTY() *pipePTY {
	r, w := io.Pipe()
	return &pipePTY{r: r, w: w, done: make(chan struct{})}
}

func (p *pipePTY) Read(b []byte) (int, error)  { return p.r.Read(b) }
func (p *pipePTY) Write(b []byte) (int, error) { return len(b), nil }
func (p *pipePTY) Resize(cols, rows int) error { return nil }
func (p *pipePTY) Close() error                { return p.w.Close() }
func (p *pipePTY) Done() <-chan struct{}       { return p.done }
func (p *pipePTY) ExitCode() (int, bool)       { return 0, false }
func (p *pipePTY) PID() int                    { return 1 }

type frameLog struct {
	mu     sync.Mutex
	frames int
	data   []byte
	status chan struct{}
}

func (l *frameLog) frameCount() int { l.mu.Lock(); defer l.mu.Unlock(); return l.frames }
func (l *frameLog) byteCount() int  { l.mu.Lock(); defer l.mu.Unlock(); return len(l.data) }
func (l *frameLog) received() []byte {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]byte(nil), l.data...)
}

func startPumpHost(t *testing.T) (*pipePTY, net.Conn, *frameLog) {
	t.Helper()
	pty := newPipePTY()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		_ = Serve(ctx, ServeConfig{SessionID: "pump-test", Listener: ln, PTY: pty, Ring: /* as RunHost builds it */})
	}()
	conn, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { cancel(); _ = conn.Close(); close(pty.done) })

	log := &frameLog{status: make(chan struct{}, 1)}
	parser := NewMessageParser(func(msgType byte, payload []byte) {
		switch msgType {
		case MsgTerminalData:
			log.mu.Lock()
			log.frames++
			log.data = append(log.data, payload...)
			log.mu.Unlock()
		case MsgStatusRes:
			select {
			case log.status <- struct{}{}:
			default:
			}
		}
	})
	go func() {
		buf := make([]byte, 64*1024)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				parser.Feed(buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()
	return pty, conn, log
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met before timeout")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestPumpCoalescesUnderLoad(t *testing.T) {
	pty, _, log := startPumpHost(t)

	payload := bytes.Repeat([]byte("0123456789abcdef"), 2048)
	const writes = 128
	start := time.Now()
	for range writes {
		if _, err := pty.w.Write(payload); err != nil {
			t.Fatalf("write: %v", err)
		}
	}
	waitFor(t, 5*time.Second, func() bool { return log.byteCount() == writes*len(payload) })
	elapsed := time.Since(start)

	if !bytes.Equal(log.received(), bytes.Repeat(payload, writes)) {
		t.Fatal("client bytes differ from PTY bytes")
	}
	ceiling := int(elapsed/flushInterval) + 2
	if got := log.frameCount(); got > ceiling {
		t.Fatalf("frames = %d over %v, want <= %d: coalescing is not engaging", got, elapsed, ceiling)
	}
}

func TestPumpFlushesImmediatelyWhenIdle(t *testing.T) {
	pty, _, log := startPumpHost(t)

	var latencies []time.Duration
	for range 20 {
		time.Sleep(3 * flushInterval)
		before := log.byteCount()
		start := time.Now()
		if _, err := pty.w.Write([]byte("x")); err != nil {
			t.Fatalf("write: %v", err)
		}
		waitFor(t, time.Second, func() bool { return log.byteCount() > before })
		latencies = append(latencies, time.Since(start))
	}
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	if median := latencies[len(latencies)/2]; median >= 8*time.Millisecond {
		t.Fatalf("idle echo median = %v, want < 8ms: a coalescer that always waits a frame fails this", median)
	}
}

func TestPumpDoesNotStarveControlMessages(t *testing.T) {
	pty, conn, log := startPumpHost(t)

	stopFlood := make(chan struct{})
	defer close(stopFlood)
	go func() {
		payload := bytes.Repeat([]byte("y\n"), 16*1024)
		for {
			select {
			case <-stopFlood:
				return
			default:
				if _, err := pty.w.Write(payload); err != nil {
					return
				}
			}
		}
	}()

	time.Sleep(100 * time.Millisecond)
	req, err := EncodeMessage(MsgStatusReq, nil)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if _, err := conn.Write(req); err != nil {
		t.Fatalf("send status req: %v", err)
	}
	select {
	case <-log.status:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("MsgStatusRes starved by the firehose")
	}
}
```

- [ ] **Step 2: Implement — replace `pumpPTY` with this structure**

In `host.go`. The current `pumpPTY` body (one `Read` → one broadcast) is replaced entirely; its exit tail (wait for `Done`, `FlushPartial`, dead-status broadcast, keep-alive) moves to `finishPump` unchanged:

```go
const (
	readBufferSize = 0x4_0000
	flushInterval  = time.Second / 60
)

// pumpPTY turns the PTY stream into coalesced client frames. A reader
// goroutine blocks on PTY.Read; this loop drains everything already available
// before deciding to flush. Idle traffic flushes immediately — the timer only
// arms when a flush already happened inside the current interval — so
// sustained load batches at 60Hz while a lone keystroke echo never waits.
func (h *host) pumpPTY() {
	chunks := make(chan []byte, 64)
	go h.readPTY(chunks)

	var pending []byte
	var lastFlush time.Time
	timer := time.NewTimer(time.Hour)
	if !timer.Stop() {
		<-timer.C
	}
	timerArmed := false

	flush := func() {
		if len(pending) == 0 {
			return
		}
		h.deliver(pending)
		pending = nil
		lastFlush = time.Now()
	}

	for {
		select {
		case chunk, ok := <-chunks:
			if !ok {
				flush()
				h.finishPump()
				return
			}
			pending = append(pending, chunk...)
		drain:
			for len(pending) < readBufferSize {
				select {
				case more, ok := <-chunks:
					if !ok {
						flush()
						h.finishPump()
						return
					}
					pending = append(pending, more...)
				default:
					break drain
				}
			}
			if len(pending) >= readBufferSize || time.Since(lastFlush) >= flushInterval {
				if timerArmed && !timer.Stop() {
					<-timer.C
				}
				timerArmed = false
				flush()
			} else if !timerArmed {
				timer.Reset(flushInterval - time.Since(lastFlush))
				timerArmed = true
			}
		case <-timer.C:
			timerArmed = false
			flush()
		}
	}
}

func (h *host) readPTY(chunks chan<- []byte) {
	defer close(chunks)
	buf := make([]byte, readBufferSize)
	for {
		n, err := h.cfg.PTY.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			chunks <- chunk
		}
		if err != nil {
			return
		}
	}
}

// deliver is the single choke point later tasks extend: Task 7 appends the
// parser feed and Task 10 the capture tee — both strictly after the broadcast.
func (h *host) deliver(batch []byte) {
	h.cfg.Ring.Append(batch)
	if frame, err := EncodeMessage(MsgTerminalData, batch); err == nil {
		h.broadcast(frame)
	}
}

func (h *host) finishPump() {
	<-h.cfg.PTY.Done()
	h.cfg.Ring.FlushPartial()
	code, _ := h.cfg.PTY.ExitCode()
	h.broadcast(statusFrame(false, h.cfg.PTY.PID(), &code))
}
```

Two properties to preserve, both load-bearing: `pending` is handed to `deliver` and then set to nil, never reused — the ring and the encoder may retain it. And the `len(pending) >= readBufferSize` clause is the backpressure bound: a firehose forces a flush at the watermark instead of growing `pending` without limit while the timer is armed.

Also bump `handleConn`'s read buffer (`host.go:282`) from 4096 to 64KB so a large paste is not sliced into 4KB feeds.

- [ ] **Step 3: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestPump -v`
Expected: PASS

- [ ] **Step 4: Re-run the manual scroll check from Task 5**

Same as Task 5 Step 5 — the loop change must feel identical or better, never worse.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "perf(runtime): greedy PTY drain with load-only 60Hz coalescing"
```

---

### Task 7: Passive parser in the host

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go`
- Create: `backend/internal/adapters/runtime/ptyhost/vtwasm/embed.go`
- Create: `backend/internal/adapters/runtime/ptyhost/host_parser_test.go`
- Move: `backend/internal/adapters/runtime/conpty/vtwasm/` → `ptyhost/vtwasm/` (from Task 1)

**Interfaces:**
- Consumes: `vtwasm.New(ctx, module []byte, cols, scrollback uint32) (*Parser, error)`, `(*Parser).Feed([]byte) error`
- Produces: `(*Parser).RenderTail(lines int) (string, error)`, `(*Parser).AltActive() (bool, error)`; `ServeConfig.Parser *vtwasm.Parser` (optional — nil disables parsing)

- [ ] **Step 1: Embed the wasm module**

```bash
mkdir -p backend/internal/adapters/runtime/ptyhost/vtwasm/assets
cp packages/terminal/target/wasm32-unknown-unknown/release/vt_host.wasm \
   backend/internal/adapters/runtime/ptyhost/vtwasm/assets/
```

`vtwasm/embed.go`:

```go
package vtwasm

import _ "embed"

//go:embed assets/vt_host.wasm
var Module []byte
```

Add a build step to `packages/build-binaries.sh` that rebuilds the wasm before the Go build, so the committed artifact cannot drift silently. This also means the four release CI workflows need `rustup` + the `wasm32-unknown-unknown` target installed before the Go build — one wasm artifact serves all four platform binaries, so cross-compilation survives, but the workflow files must change and that change lands with this task.

- [ ] **Step 2: Write the failing test**

`host_parser_test.go`:

```go
package ptyhost

import (
	"context"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

func TestParserRendersCursorAddressedOutput(t *testing.T) {
	parser, err := vtwasm.New(context.Background(), vtwasm.Module, 80, 24, 100)
	if err != nil {
		t.Fatalf("new parser: %v", err)
	}
	defer func() { _ = parser.Close() }()

	// Write "AAAA", then jump home and overwrite with "B". A raw byte ring
	// returns both; a real screen returns "BAAA". This is the exact difference
	// between tmux capture-pane and the old conpty ring.
	if err := parser.Feed([]byte("AAAA\x1b[1;1HB")); err != nil {
		t.Fatalf("feed: %v", err)
	}
	text, err := parser.RenderTail(5)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(text, "BAAA") {
		t.Fatalf("RenderTail = %q, want it to contain \"BAAA\"", text)
	}
	if strings.Contains(text, "\x1b[") {
		t.Fatalf("RenderTail = %q, want no escape sequences", text)
	}
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestParserRenders -v`
Expected: FAIL — `parser.RenderTail undefined`

- [ ] **Step 4: Implement `RenderTail` and `AltActive`**

Append to `vtwasm/vtwasm.go`:

```go
const (
	renderBufferBytes = 1 << 20
	renderErr         = ^uint32(0)
	renderTooBig      = ^uint32(0) - 1
)

// RenderTail returns ("", nil) for a genuinely empty screen. Errors are errors:
// the caller must never treat one as "fall back to the raw ring", or the
// platform-divergence bug this parser exists to kill comes back through the
// side door.
func (p *Parser) RenderTail(lines int) (string, error) {
	res, err := p.module.ExportedFunction("vt_alloc").Call(p.ctx, renderBufferBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: alloc render buffer: %w", err)
	}
	out := uint32(res[0])
	defer p.module.ExportedFunction("vt_free").Call(p.ctx, uint64(out), renderBufferBytes)

	res, err = p.module.ExportedFunction("vt_render").
		Call(p.ctx, uint64(p.handle), uint64(lines), uint64(out), renderBufferBytes)
	if err != nil {
		return "", fmt.Errorf("vtwasm: render: %w", err)
	}
	switch written := uint32(res[0]); written {
	case 0:
		return "", nil
	case renderErr:
		return "", fmt.Errorf("vtwasm: render failed for handle %d", p.handle)
	case renderTooBig:
		return "", fmt.Errorf("vtwasm: rendered screen exceeds %d bytes", renderBufferBytes)
	default:
		bytes, ok := p.module.Memory().Read(out, written)
		if !ok {
			return "", fmt.Errorf("vtwasm: read %d bytes at %d out of range", written, out)
		}
		return string(bytes), nil
	}
}

func (p *Parser) Resize(cols, rows uint32) error {
	_, err := p.module.ExportedFunction("vt_resize").
		Call(p.ctx, uint64(p.handle), uint64(cols), uint64(rows))
	return err
}

func (p *Parser) AltActive() (bool, error) {
	res, err := p.module.ExportedFunction("vt_alt_active").Call(p.ctx, uint64(p.handle))
	if err != nil {
		return false, fmt.Errorf("vtwasm: alt_active: %w", err)
	}
	return res[0] == 1, nil
}
```

- [ ] **Step 5: Feed the parser from the host's pump, off the hot path**

In `host.go`, add `Parser *vtwasm.Parser` to `ServeConfig`, and call `h.feedParser(batch)` at the end of `deliver` (Task 6's choke point) — **after** the broadcast, in bounded slices:

```go
const maxParserSliceBytes = 0x1_0000 // Warp's MAX_LOCKED_READ

// feedParser hands the batch to the passive parser in bounded slices. It runs
// after the client broadcast, never before: a slow or failing parser must not
// delay a single byte reaching the screen. Errors are dropped for the same
// reason -- a broken parser degrades GetOutput, it does not break the terminal.
func (h *host) feedParser(batch []byte) {
	if h.cfg.Parser == nil {
		return
	}
	for offset := 0; offset < len(batch); offset += maxParserSliceBytes {
		end := min(offset+maxParserSliceBytes, len(batch))
		_ = h.cfg.Parser.Feed(batch[offset:end])
	}
}
```

- [ ] **Step 6: Keep the parser the same size as the PTY, and actually construct it**

Two wirings without which every earlier step is dead code:

- In `RunHost` (`host_main.go`), construct the parser with the session's initial cols/rows and put it in `ServeConfig`. `nil` stays legal for tests, but the shipped host always has one.
- Wherever `applyLargestLocked` resizes the PTY (initial attach, client resize, client drop), mirror the same cols/rows into `Parser.Resize`. `vt-core` defaults to 24 rows and only learns its height from `resize` — skip this and a 120x40 TUI renders through a 24-row grid, and Gate 1 fails in ways that look like parser bugs.

Add a test: resize to 100x40, feed a full-screen frame, assert `RenderTail` yields 40 rows.

- [ ] **Step 7: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost packages/build-binaries.sh
git commit -m "feat(runtime): passive vt-core parser inside the pty-host"
```

---

### Task 8: `GetOutput` answers from the rendered grid

**Files:**
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go` (`MsgGetOutputReq` handler, line ~320)
- Modify: `backend/internal/adapters/runtime/ptyhost/host_test.go`

- [ ] **Step 1: Write the failing test**

```go
func TestGetOutputReturnsRenderedScreen(t *testing.T) {
	host, client := newTestHostWithParser(t)
	defer host.Shutdown()

	host.feedPTY("AAAA\x1b[1;1HB")

	text := client.getOutput(50)
	if !strings.Contains(text, "BAAA") {
		t.Fatalf("GetOutput = %q, want the rendered screen \"BAAA\"", text)
	}
	if strings.Contains(text, "\x1b[") {
		t.Fatalf("GetOutput = %q, want no escape sequences", text)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestGetOutputReturnsRendered -v`
Expected: FAIL — returns the raw ring text including `\x1b[1;1H`

- [ ] **Step 3: Implement**

In the `MsgGetOutputReq` case in `host.go`, the ring is the fallback **only when no parser exists** — never on an empty render (a blank screen is a valid screen) and never on a render error (raw ring bytes are exactly the wrong-semantics answer this task deletes; log and return empty instead):

```go
	case MsgGetOutputReq:
		lines := 50
		var req GetOutputReq
		if err := json.Unmarshal(payload, &req); err == nil && req.Lines > 0 {
			lines = req.Lines
		}
		var text string
		if h.cfg.Parser != nil {
			rendered, err := h.cfg.Parser.RenderTail(lines)
			if err != nil {
				h.logf("render for GetOutput: %v", err)
			}
			text = rendered
		} else {
			text = h.cfg.Ring.Tail(lines)
		}
		if frame, err := EncodeMessage(MsgGetOutputRes, []byte(text)); err == nil {
			h.sendTo(conn, frame)
		}
```

- [ ] **Step 4: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "feat(runtime): answer GetOutput from the rendered grid"
```

---

### Task 9: `GetStyledOutput`

Closes the `StyledTerminalOutputReader` gap. `composerIsEmpty` (`agent_switching.go:1493`) fails closed without it, which silently weakens a safety check.

**Files:**
- Modify: `packages/terminal/crates/vt-host/src/lib.rs` (add `vt_render_styled`)
- Modify: `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go`
- Modify: `backend/internal/adapters/runtime/ptyhost/proto.go` (`MsgStyledOutputReq/Res`)
- Modify: `backend/internal/adapters/runtime/ptyhost/host.go`, `client.go`, `runtime.go`

**Interfaces:**
- Produces: `(*Runtime).GetStyledOutput(ctx, handle, lines) (string, error)` satisfying `ports.StyledTerminalOutputReader` (`ports/outbound.go:93`)

- [ ] **Step 1: Write the failing test**

```go
func TestGetStyledOutputPreservesSGR(t *testing.T) {
	host, client := newTestHostWithParser(t)
	defer host.Shutdown()

	host.feedPTY("\x1b[31mred\x1b[0m plain")

	text := client.getStyledOutput(50)
	if !strings.Contains(text, "\x1b[31m") {
		t.Fatalf("GetStyledOutput = %q, want the SGR sequence preserved", text)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestGetStyledOutput -v`
Expected: FAIL — `client.getStyledOutput undefined`

- [ ] **Step 3: Add `vt_render_styled` to the shim**

The snapshot carries `run_ranges` and `style_pairs` alongside `content`; re-emit SGR at each run boundary. Add to `vt-host/src/lib.rs`, mirroring `vt_render` but walking the style pairs and writing `\x1b[<code>m` before each run, then `\x1b[0m` at each row end. `StyleCode` lives in `crates/vt-core/src/style.rs` (re-exported from `lib.rs`) — read its encoding there first. Note `AltSnapshot` has no methods; index `content` by `row_ranges` directly, exactly as `vt_render` already does. Rebuild the wasm and re-copy it into `vtwasm/assets/`.

- [ ] **Step 4: Wire the protocol and the runtime method**

Add `MsgStyledOutputReq byte = 0x09` and `MsgStyledOutputRes byte = 0x0A` to `proto.go`; handle the request in `host.go` exactly as `MsgGetOutputReq` but calling `RenderStyledTail`; add `clientGetStyledOutput` to `client.go` mirroring `clientGetOutput` (`client.go:96`); add `(*Runtime).GetStyledOutput` mirroring `GetOutput` (`runtime.go:280`).

- [ ] **Step 5: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost packages/terminal/crates/vt-host
git commit -m "feat(runtime): styled pane output from the pty-host parser"
```

---

### Task 10: Pane capture

**Files:**
- Delete: `backend/internal/adapters/runtime/ptyhost/capture_unsupported.go`
- Create: `backend/internal/adapters/runtime/ptyhost/capture.go`
- Create: `backend/internal/adapters/runtime/ptyhost/capture_test.go`
- Modify: `proto.go`, `host.go`, `client.go`

**Interfaces:**
- Produces: `CaptureState`, `StartCapture`, `StopCapture` satisfying `ports.PaneCapturer` (`ports/outbound.go:188`); `PaneCaptureState{PipeOpen, AlternateOn bool}`

- [ ] **Step 1: Write the failing test**

```go
func TestStartCaptureTeesOutputToArgv(t *testing.T) {
	host, client := newTestHostWithParser(t)
	defer host.Shutdown()

	sink := filepath.Join(t.TempDir(), "capture.log")
	if err := client.startCapture([]string{"/bin/sh", "-c", "cat > " + sink}); err != nil {
		t.Fatalf("startCapture: %v", err)
	}
	host.feedPTY("captured bytes\n")

	waitForFileContaining(t, sink, "captured bytes")

	state := client.captureState()
	if !state.PipeOpen {
		t.Fatal("PipeOpen = false, want true while capture is armed")
	}
	if err := client.stopCapture(); err != nil {
		t.Fatalf("stopCapture: %v", err)
	}
	if client.captureState().PipeOpen {
		t.Fatal("PipeOpen = true after StopCapture, want false")
	}
}

func TestCaptureStateReportsAlternateScreen(t *testing.T) {
	host, client := newTestHostWithParser(t)
	defer host.Shutdown()

	host.feedPTY("\x1b[?1049h")
	if !client.captureState().AlternateOn {
		t.Fatal("AlternateOn = false after entering the alternate screen")
	}
}
```

The first test shells out to `/bin/sh`, so give it a `//go:build !windows` tag (or a `runtime.GOOS` skip); `capture.go` itself is cross-platform.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestStartCapture -v`
Expected: FAIL — `client.startCapture undefined`

- [ ] **Step 3: Implement the capture sink**

`capture.go` — the sink subscribes to the same raw broadcast the clients get, which is how Warp's recorder works (`local_tty/recorder.rs`), rather than tapping the parser:

```go
// capture.go implements pane capture without tmux's pipe-pane: the host spawns
// the capture argv and tees raw PTY output into its stdin. The tee subscribes to
// the same broadcast the clients read, so capture can never alter what a client
// sees.
package ptyhost

import (
	"io"
	"os/exec"
	"sync"
)

type captureSink struct {
	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser
}

func (c *captureSink) start(argv []string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd != nil {
		return nil
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		_ = stdin.Close()
		return err
	}
	c.cmd, c.stdin = cmd, stdin
	return nil
}

func (c *captureSink) write(batch []byte) {
	c.mu.Lock()
	stdin := c.stdin
	c.mu.Unlock()
	if stdin == nil {
		return
	}
	_, _ = stdin.Write(batch)
}

func (c *captureSink) stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cmd == nil {
		return nil
	}
	_ = c.stdin.Close()
	err := c.cmd.Wait()
	c.cmd, c.stdin = nil, nil
	return err
}

func (c *captureSink) open() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.cmd != nil
}
```

Add message types `MsgCaptureStartReq = 0x0B`, `MsgCaptureStopReq = 0x0C`, `MsgCaptureStateReq = 0x0D`, `MsgCaptureStateRes = 0x0E`; call `sink.write(batch)` at the end of `deliver` (after the broadcast, beside the parser feed); answer `MsgCaptureStateReq` with `{PipeOpen: sink.open(), AlternateOn: parser.AltActive()}`.

- [ ] **Step 4: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "feat(runtime): pane capture without pipe-pane"
```

---

### Task 11: Restart-in-place

**Files:**
- Create: `backend/internal/adapters/runtime/ptyhost/respawn.go`
- Create: `backend/internal/adapters/runtime/ptyhost/respawn_test.go`
- Modify: `proto.go`, `host.go`, `client.go`, `runtime.go`

**Interfaces:**
- Produces: `(*Runtime).Restart(ctx, handle, cfg) (ports.RuntimeHandle, error)` satisfying `ports.RuntimeRestarter` (`ports/outbound.go:111`), consumed at `manager.go:1768`

- [ ] **Step 1: Write the failing test**

```go
func TestRestartReplacesProcessAndKeepsHandle(t *testing.T) {
	runtime, handle := newTestRuntimeSession(t)
	before := pidOf(t, runtime, handle)

	after, err := runtime.Restart(context.Background(), handle, restartConfig(t))
	if err != nil {
		t.Fatalf("Restart: %v", err)
	}
	if after.ID != handle.ID {
		t.Fatalf("handle changed: %q -> %q, want it preserved", handle.ID, after.ID)
	}
	if pidOf(t, runtime, after) == before {
		t.Fatal("child pid unchanged, want a replacement process")
	}
	if alive, _ := runtime.IsAlive(context.Background(), after); !alive {
		t.Fatal("IsAlive = false after Restart")
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/ -run TestRestartReplaces -v`
Expected: FAIL — `runtime.Restart undefined`

- [ ] **Step 3: Implement**

Add `MsgRespawnReq = 0x0F` / `MsgRespawnRes = 0x10`.

**Prerequisite refactor — the PTY becomes mutable state.** Today every path reads `h.cfg.PTY` directly, which is safe only because it never changes. Respawn changes it, so first: add a `pty ptyConn` field to `host` guarded by `h.mu`, initialized from `ServeConfig.PTY`, read everywhere through a `h.currentPTY()` accessor. Grep for every `h.cfg.PTY` in the package and convert it — a missed one is a torn read against the swap. Also add `pumpDone chan struct{}`, created before each `go h.pumpPTY()` and closed when `pumpPTY` returns, and a `respawnMu sync.Mutex` so two respawn requests serialize instead of racing the swap.

**The host-side sequence, in this exact order** (a helper called from the `MsgRespawnReq` case; every early return replies `MsgRespawnRes{ok:false, error}` first):

1. `respawnMu.Lock()`, deferred unlock.
2. Parse the payload `{cwd, shell, launchCmd, launchId}`; reject malformed.
3. `old := h.currentPTY()`; `_ = old.Close()`; wait for `<-old.Done()` with a 5s timeout — on timeout, reply failure and stop (the child is wedged; killing harder is a follow-up, not an improvisation).
4. Wait `<-h.pumpDone`. The pump exits once its reader hits EOF and `Done` closes; after this point nothing is reading the old PTY or writing frames. (Clients see the pump's dead-status broadcast, then the alive one from step 9 — that ordering is fine and observable.)
5. `h.cfg.Ring.Reset()` — a new method on `Ring`, added in this task, that clears the stored lines and the partial line under the ring's own lock. `respawn-pane -k` starts from a blank pane; a ring still holding the dead agent's bytes replays them ahead of the new agent's output on the next attach.
6. Close the old parser; create a fresh one (the new process starts from a blank screen) sized to `h.curCols`/`h.curRows`, falling back to the session's initial size while both are 0.
7. `pty, err := newPTY(cwd, shell, args)` — on error, reply failure and leave the host alive with no child: a later respawn can retry, and `IsAlive`/status report dead, which is true.
8. Under `h.mu`: set `h.pty = pty`, reset `h.curCols, h.curRows = 0, 0`, then `applyLargestLocked()` so the replacement immediately takes the largest attached client's grid instead of its default.
9. `h.pumpDone = make(chan struct{})`; start `go h.pumpPTY()`. Reply `MsgRespawnRes{ok:true, pid}`, then broadcast an alive `statusFrame` so every attached client learns the new pid without polling.

If `ptyregistry` records the child pid, update the entry here too.

The listener, registry entry and client set are untouched throughout — that is the entire point of respawn versus destroy-and-create. `(*Runtime).Restart` sends the message, waits for the response with a 10s timeout, and returns the same handle; the test's `pidOf` helper reads the pid from a status request.

- [ ] **Step 4: Run the tests**

Run: `cd backend && go test ./internal/adapters/runtime/ptyhost/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/adapters/runtime/ptyhost
git commit -m "feat(runtime): restart-in-place without respawn-pane"
```

---

### Task 12: `opr attach` debugging CLI

Replaces the `tmux attach` escape hatch, which is otherwise lost.

**Files:**
- Create: `backend/internal/cli/attach.go`
- Create: `backend/internal/cli/attach_test.go`
- Modify: `backend/internal/cli/root.go`

- [ ] **Step 1: Write the failing test**

```go
func TestAttachCommandRejectsUnknownSession(t *testing.T) {
	cmd := newAttachCommand()
	cmd.SetArgs([]string{"no-such-session"})
	err := cmd.Execute()
	if err == nil || !strings.Contains(err.Error(), "no-such-session") {
		t.Fatalf("Execute() error = %v, want it to name the missing session", err)
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/cli/ -run TestAttachCommand -v`
Expected: FAIL — `undefined: newAttachCommand`

- [ ] **Step 3: Implement**

`attach.go`: resolve the session via `ptyregistry.List()`, dial its address, put stdin in raw mode with `term.MakeRaw`, then `io.Copy` both directions using the `MsgTerminalInput` / `MsgTerminalData` framing from `proto.go`. Restore the terminal on exit. Register it hidden in `root.go` alongside `newPtyHostCommand`.

- [ ] **Step 4: Run the tests, then try it by hand**

```bash
cd backend && go test ./internal/cli/ -v
go run . attach default-project-5
```

Expected: the live agent screen, keystrokes reaching it, `Ctrl-C` detaching cleanly.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/cli
git commit -m "feat(cli): opr attach for debugging a live session"
```

---

### Task 13: Differential parity harness — GATE 1

The oracle is tmux, and it only exists to be asked while it is still in the tree. This task must land before Task 15 deletes it.

**Files:**
- Create: `backend/internal/adapters/runtime/parity/parity_test.go`
- Create: `backend/internal/adapters/runtime/parity/corpus.go`

- [ ] **Step 1: Write the differential test**

The design principle: **replay recorded bytes, never live apps.** A live `htop` paints differently per run; a recorded byte stream is bit-identical on both sides, so any diff is a parser gap, not timing. And **both sides must feed through a real PTY**: a PTY's termios mangles the stream (ONLCR turns `\n` into `\r\n`), tmux's panes get that mangling, and feeding one side raw while the other goes through a PTY manufactures false diffs. The delivery vehicle on both sides is the same: a pane running `cat <fifo>`, with the test writing the vector bytes into the FIFO.

```go
//go:build parity

// Package parity diffs ptyhost's rendered output against tmux capture-pane on
// identical byte streams. tmux is the oracle; this test is the reason the tmux
// adapter cannot be deleted until it passes.
package parity

import "testing"

type Scenario struct {
	Name       string
	Bytes      []byte
	Cols, Rows int
	// ResizeAt > 0 splits the stream: feed Bytes[:ResizeAt], resize both
	// runners to NewCols x NewRows, wait for quiescence, feed the rest.
	ResizeAt         int
	NewCols, NewRows int
}

func TestRenderedOutputMatchesTmux(t *testing.T) {
	requireTmux(t)
	for _, sc := range Corpus() {
		t.Run(sc.Name, func(t *testing.T) {
			tmuxRows := runUnderTmux(t, sc)
			hostRows := runUnderPtyHost(t, sc)
			diffRows(t, tmuxRows, hostRows)
		})
	}
}
```

`corpus.go` loads three sources into `[]Scenario`:

- `packages/terminal/protocol/alt-vectors/*.json` — decode `inputBase64` as `Bytes`, take `rows`/`cols` from the file (`htop-frame`, `vim-open`, `less-page`, `less-back`).
- `packages/terminal/protocol/redraw-vectors/agent-cli-idle.json` — its `bytes` field is a JSON int array; `columns`/`rows` are in the file.
- Synthesized literals, written inline: a plain prompt (`"$ echo hi\r\nhi\r\n$ "`), cursor addressing (`"AAAA\x1b[1;1HB"`), alternate-screen enter/draw/leave (`"\x1b[?1049h\x1b[2J\x1b[1;1Hframe\x1b[?1049l"`), a scroll-region scroll (`"\x1b[2;10r\x1b[10;1H"` + 20 numbered lines), wide characters (`"日本語テスト"`), and one `ResizeAt` case reusing the cursor-addressing bytes.

`runUnderTmux(t, sc)`:

1. `mkfifo` in `t.TempDir()`; start an isolated server so a developer's real tmux is untouched: `tmux -L parity-<pid> -f /dev/null new-session -d -s <name> -x <cols> -y <rows> "cat < <fifo>"`.
2. Open the FIFO write-only — the open itself blocks until `cat` has the read end, which is the start-up synchronization; no sleep.
3. Write `Bytes` (split at `ResizeAt` if set, with `tmux resize-window -t <name> -x -y` between halves and a quiescence wait after the first half). Keep the FIFO open: closing it ends `cat`, which kills the pane and the session before capture.
4. Wait for quiescence, then `tmux capture-pane -t <name> -p`, split into rows. Kill the session, close the FIFO.

`runUnderPtyHost(t, sc)` — the same shape through the production path, so `GetOutput` itself is what's being validated: `mkfifo`; spawn a session whose argv is `{"/bin/sh", "-c", "cat < <fifo>"}` via the runtime; send one resize to `Cols`x`Rows` (this sizes the PTY *and* the parser — Task 7 Step 6); open the FIFO, write the bytes the same way; wait for quiescence; `GetOutput(rows)`; split into rows.

`waitQuiescent(capture func() string)` — shared by both runners: poll every 50ms until three consecutive captures are identical, 10s timeout. Both sides settle by the same rule or the comparison is a race.

`diffRows` — compare row-by-row and report the first differing row with both versions, not two full-screen dumps. `normalize` may strip **only** trailing whitespace per row and trailing all-blank rows. It must never collapse interior whitespace, drop non-blank rows, or touch non-space characters — every relaxation here is a parser bug being legalized, and a `normalize` that grows during this task is the test deleting itself.

`requireTmux(t)` — `t.Skip` when `tmux` is not in `PATH` (CI images without it run the build, not the oracle).

- [ ] **Step 2: Run it and fix what it finds**

Run: `cd backend && go test -tags parity ./internal/adapters/runtime/parity/ -v`
Expected: initially FAIL on some scenarios. Each failure is a real parser gap — fix `vt-host`/`vt-core`, do not relax `normalize`.

- [ ] **Step 3: Exercise every decision site against both runtimes**

Add a test that runs each consumer of terminal text against identical agent output under both runtimes, asserting identical decisions: the activity observer (`observe/activity/observer.go:126`), the handoff probe (`agent_switching.go:295`) and its styled composer check (`agent_switching.go:1493`), the delivery readiness check (`message_delivery.go:76`), the review launcher (`launcher.go:463`), the stale-idle transition proof (`interface_transition.go:567`), and the spawn prompt-readiness poll (`manager.go:3616`). Also run the capture supervisor (`service/terminalcapture/supervisor.go`) once against ptyhost — it has only ever exercised its `ErrCaptureUnsupported` branch on Windows, and this is the first time capture works everywhere.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/adapters/runtime/parity
git commit -m "test(runtime): differential parity harness against tmux"
```

---

### Task 14: `scroll-latency` perf scenario — GATE 2

**Files:**
- Modify: `frontend/perf/scenarios.json`
- Modify: `frontend/scripts/benchmark-terminal.mjs` (four parallel registries, see Step 2)
- Modify: `frontend/scripts/benchmark-result.mjs` (env allowlist, see Step 1)
- Modify: `frontend/perf/terminal/harness.tsx` (the measurement lives here, **not** `runtime.ts` — that file is a 9-line runtime-identity helper)

- [ ] **Step 1: Let the harness select the runtime — without this, every A/B below silently compares tmux to tmux**

The harness strips all `OPERATOR_*` variables from the child environment (`benchmark-result.mjs:60-107`, `BINDING_ENVIRONMENT_PREFIXES` + `sanitizedBindingEnvironment`), so an `OPERATOR_RUNTIME=ptyhost` prefix on the bench command evaporates before it reaches the daemon, with no error. Add `OPERATOR_RUNTIME` to the `controlled` object in `spawnTauriHarness` (`benchmark-terminal.mjs:514-521`), passing the parent value through when set. The stripping exists for evidence-integrity — check `resolveEvidenceScope` and confirm the passthrough doesn't downgrade runs to non-binding. The electron shell attaches to an already-running daemon (`OPERATOR_BENCH_DAEMON_URL`), so runtime selection there belongs to whoever started the daemon; use `--shell tauri` for these A/Bs.

- [ ] **Step 2: Add the scenario definition and register it everywhere the harness checks**

In `scenarios.json`, alongside `input-latency` (note `alternateScreen` is a new field — Step 3 is what reads it):

```json
  "scroll-latency": {
    "kind": "terminal",
    "warmups": 3,
    "samples": 20,
    "unit": "milliseconds",
    "completionMark": "operator:terminal-ready",
    "transport": "daemon-terminal-mux",
    "columns": 120,
    "rows": 40,
    "scrollback": 5000,
    "alternateScreen": true
  }
```

Registration is not one Set — `benchmark-terminal.mjs` has parallel registries that each throw on an unknown scenario: `terminalScenarios` (:29), `primaryAcknowledgementNames` (:41), `scenarioMeasurementPlan()` (:70), `terminalThroughputSample()` (:81), plus the `--help` text. On the harness side, add the new acknowledgement to `acknowledgementMarks` and the ack union type in `harness.tsx` (:29, :55).

- [ ] **Step 3: Implement the measurement in `harness.tsx`**

Copy the existing input-latency pattern — it is already a true send-input → xterm-render-callback delta (`harness.tsx:344-349` sends, `:207-223` acknowledges off the render event). For scroll: start a deterministic alt-screen responder in the pane (a tiny script that enters the alternate screen with `\x1b[?1049h`, enables SGR mouse reporting, and rewrites one line on every wheel report it reads — deterministic, unlike `less`), then per sample send one SGR wheel report (`\x1b[<64;1;1M`) and acknowledge on the next render callback that changes the grid. Report p50 and p95.

- [ ] **Step 4: Run it against both runtimes**

```bash
cd frontend && npm run bench:terminal -- --shell tauri --scenario scroll-latency
OPERATOR_RUNTIME=ptyhost npm run bench:terminal -- --shell tauri --scenario scroll-latency
```

**Gate:** ptyhost must beat tmux decisively on p50 and p95. This is the number that represents the original complaint; if it does not improve, the premise of the whole plan is wrong and that must be reported rather than worked around.

- [ ] **Step 5: Run the full suite against both runtimes**

```bash
cd frontend && for s in vtebench large-output input-latency reconnect cpu-time active-memory; do
  npm run bench:terminal -- --shell tauri --scenario $s
  OPERATOR_RUNTIME=ptyhost npm run bench:terminal -- --shell tauri --scenario $s
done
```

Expected: `input-latency`, `reconnect`, `cpu-time`, `active-memory` no worse; `vtebench` and `large-output` improved. A `large-output` regression means the parser reached the hot path — find it before continuing. The `reconnect` numbers also answer the spec's open question about a rendered ring snapshot.

- [ ] **Step 6: Commit**

```bash
git add frontend/perf frontend/scripts/benchmark-terminal.mjs frontend/scripts/benchmark-result.mjs
git commit -m "test(perf): scroll-latency scenario for wheel-to-frame timing"
```

---

### Task 15: Flip the default and delete tmux

Only after Tasks 13 and 14 both pass.

**Files:**
- Modify: `backend/internal/adapters/runtime/runtimeselect/runtimeselect.go`
- Delete: `backend/internal/adapters/runtime/tmux/`
- Delete: `backend/internal/adapters/runtime/ptyexec/` if nothing else uses it
- Modify: `AGENTS.md`, `CLAUDE.md`, `docs/`, packaging scripts mentioning tmux

- [ ] **Step 1: Flip the default**

```go
func New(_ *slog.Logger) Runtime {
	return ptyhost.New(ptyhost.Options{})
}
```

Delete the `OPERATOR_RUNTIME` override and its test — with tmux gone there is nothing to select.

- [ ] **Step 2: Delete the adapter**

```bash
git rm -r backend/internal/adapters/runtime/tmux
grep -rn "ptyexec" backend --include="*.go" | grep -v "runtime/ptyexec"   # empty means it can go too
```

- [ ] **Step 3: Verify nothing references tmux**

```bash
grep -rni "tmux" backend frontend/src packages --include="*.go" --include="*.ts" --include="*.tsx" | grep -v node_modules
```

Expected: no hits outside `docs/` history and the spec's problem statement.

- [ ] **Step 4: Full test suite on every platform**

```bash
cd backend && go test ./... && for os in darwin linux windows; do GOOS=$os go build ./...; done
cd ../frontend && npm test
```

- [ ] **Step 5: Update the docs**

`AGENTS.md` and `CLAUDE.md` describe tmux as the session runtime. Replace with the pty-host model. Remove any tmux install requirement from setup docs and packaging.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(runtime)!: replace tmux with the pty-host on every platform"
```

---

## Self-review notes

**Spec coverage.** Every spec section maps to a task: goals 1–2 → Tasks 2–6 (Task 6 is the read-loop rebuild — the performance half of goal 1); goal 3 → Tasks 7–9; goal 4 → Tasks 10–12 plus `applyLargestLocked`, which already exists and needs no task; goal 5 → the global constraint, Task 1's no-cgo binding, and Task 7's CI-toolchain note. Both spec gates → Tasks 13 and 14. The spec's WASM risk → Task 1's explicit decision gate; its SIGPIPE risk → Task 4 Step 4. Both spec open questions (always-on vs on-demand parsing, raw vs rendered ring) are answered by Task 1's benchmark and Task 14's `reconnect` numbers respectively; neither blocks earlier tasks.

**Naming consistency.** `newPTY` is the seam constructor on both platforms (Task 3), with `newConPTY` retained as the Windows implementation behind it. `Parser.Feed` / `RenderTail` / `AltActive` / `Resize` / `Close` are used identically in Tasks 7, 8, 9 and 10. `defaultSpawnHost` keeps the exact signature the Windows implementation already has.

**Known thin spots**, called out rather than hidden: Task 9's `vt_render_styled` describes the SGR re-emission strategy rather than giving the full Rust body, because the run/style-pair walk depends on `StyleCode`'s encoding, which the implementer should read first at `crates/vt-core/src/style.rs`. Task 12's `attach.go` is described structurally for the same reason — it is mechanical given the framing in `proto.go`. The three tasks that were previously thin relative to their difficulty are now specified in full: Task 6 carries complete test bodies and the replacement `pumpPTY`, Task 11 a nine-step ordered respawn sequence with its prerequisite mutable-PTY refactor, and Task 13 the byte-replay harness design including the FIFO delivery trick, the both-sides-through-a-PTY termios rule, the quiescence protocol, and the `normalize` contract.
