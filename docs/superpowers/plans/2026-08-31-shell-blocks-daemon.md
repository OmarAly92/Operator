# Production Shell Blocks — Daemon Capture, Persistence, and Replay Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> or `superpowers:executing-plans` to implement this plan task by task. Keep the checklist
> current and stop at every review gate.

**Status:** Amended 2026-08-31 after recovery and production-readiness review.

**Goal:** Give Operator shell panes the same user-visible command-block behavior as Warp:
stable command boundaries, command/cwd/branch/exit metadata, exact terminal output,
alternate-screen isolation, bounded durable history, and correct restore after detach or
daemon restart.

**Architecture:** The package-owned bootstrap emits additive OSC 133 and OSC 7000 marks.
On Unix, tmux `pipe-pane` sends the pane stream to a hidden `opr pane-capture` helper. The
helper, not the daemon reader, owns a bounded segmented journal under Operator's data dir,
so rotation never renames a file that `cat` still has open. A daemon capture supervisor
adopts every live shell terminal in the current app run, queries tmux's existing
`#{alternate_on}` and `#{pane_pipe}` state, tails the journal once per pane, assembles
lossless terminal blocks, and upserts complete rows into a dedicated `terminal_blocks`
store. The shell-terminal history API returns the original byte stream and metadata. The
renderer loads and feeds that history before opening the live terminal channel. Explicit
terminal teardown stops `pipe-pane`, waits for the helper's EOF seal, performs a final
drain, and only then destroys the runtime.

**Parity definition:** “Identical to Warp” means observable block behavior: one block per
submitted command, exact displayed bytes and styling, correct exit/cwd/branch metadata,
no alternate-screen repaint history, 100 retained blocks per terminal, 5,000 retained
output lines per block, and stable restoration. It does not mean copying Warp's private
protocol or its invasive shell-hook behavior. Operator keeps its documented OSC 133/7000
contract, additive hooks, daemon/API boundaries, and safety restrictions.

**Tech stack:** Go, Cobra, tmux, SQLite/sqlc, React/TypeScript, Vitest, real PTY/tmux shell
integration tests, and the existing `packages/terminal` Rust/Go/TypeScript conformance
vectors.

**Primary spec:**
[`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md),
especially §§7–8 and 13. This plan deliberately corrects the incomplete lifecycle and
storage wording in §13.2; Task 12 makes that correction durable.

---

## Recovered baseline — validate, do not reimplement

The implementation worktree is
`/Users/omaraly/development/AI/Operator-shell-blocks` on branch
`shell-blocks-daemon`. It was clean when this amendment was written. Preserve these
commits:

| Commit | Recovered work | Production disposition |
| --- | --- | --- |
| `828b7d0bb` | language-neutral spawn recipe manifest | keep |
| `c66520990` | spawn argv tests | keep and extend |
| `6b422b86a` | shell-terminal bootstrap wiring | keep and extend |
| `5b6db5678` | first `pipe-pane` sink and mark decoder | retain decoder work; replace file lifecycle |
| `8618dce73` | alternate-screen suppression | retain state-machine behavior |
| `4d2a0914` | rename-based bounding | supersede with Task 5 |
| `1e505bf62` | finish an in-flight block on alternate-screen entry | retain behavior |
| `8d9090656` | warning for the stalled old-inode writer | supersede with Task 5 |

Before new production code, run:

```bash
cd /Users/omaraly/development/AI/Operator-shell-blocks/backend
go test ./internal/terminal ./internal/adapters/runtime/tmux
```

Those focused tests were green during recovery. Their success proves only the recovered
unit behavior; it does not prove capture is started, adopted, stopped, persisted, or
replayed.

---

## Production invariants

These are acceptance rules, not implementation suggestions:

1. Exactly one capture writer and one daemon decoder own a live tmux pane, independent of
   the number of attached clients.
2. Shells in the current `appRunID` survive daemon restart, and capture resumes without a
   new shell or duplicate block rows.
3. A client is never required for capture; commands run with zero clients appear in
   history later.
4. `#{alternate_on}` seeds capture state before the first byte is decoded. OSC
   `?1049h`/`?1049l` updates it thereafter.
5. Alternate-screen bytes are never persisted as command-block output. A command already
   in flight may finish when alternate mode begins, but repaint bytes are excluded.
6. Raw bytes are preserved as `BLOB`; do not reconstruct history from plain text.
7. Rotation is writer-owned. The daemon must never rename or truncate a path still held
   open by `pipe-pane`, `cat`, or the helper.
8. Explicit close order is stop writer, seal, drain, persist, destroy runtime, delete row.
9. Daemon shutdown drains to the latest durable journal cursor before SQLite closes. Any
   bytes arriving after that cursor remain in the journal and are adopted next boot.
10. Reprocessing a segment or complete block is idempotent.
11. Retain the newest 100 blocks per terminal. Retain at most 5,000 output lines and 8 MiB
    of raw bytes per block; store the number of omitted lines/bytes.
12. Journal storage is bounded to eight 1 MiB sealed segments plus one active segment per
    terminal. If an offline daemon falls behind the bound, discard oldest sealed segments,
    record a gap, abandon the partial block, and recover at the next valid prompt boundary.
13. All capture state lives under the configured Operator data dir. Nothing uses an OS
    default app-data path.
14. Windows remains a working raw terminal. Durable shell blocks are reported unavailable
    until a ConPTY-native capture owner exists.
15. `packages/terminal` remains product-independent. No Operator session, tmux, SQLite,
    mux, or data-dir concept enters it.
16. Do not add code comments, per repository instruction.

---

### Task 1: Pin real shell behavior before changing the hooks

**Files:**

- Modify: `packages/terminal/shell/zsh.test.mjs`
- Modify: `packages/terminal/shell/bash.test.mjs`
- Modify: `packages/terminal/shell/fish.test.mjs`
- Modify: `packages/terminal/shell/pty.mjs`
- Create: `packages/terminal/protocol/vectors/real-shell-blocks.json`

The existing tests accept mocked or incomplete streams. They currently miss two observed
failures: zsh captures `$?` after another command and always reports zero, while its block
counter mutates inside a command-substitution subshell and repeatedly emits `1`; bash's
recursive DEBUG trap emits its own hook internals and never produces a stable A/C/D
sequence.

- [ ] Add a PTY assertion helper that parses the actual emitted byte stream and returns
  ordered OSC 133/7000 records without normalizing their order.
- [ ] Add zsh cases for `true`, `false`, a pipeline, multiline input, Ctrl-C, `cd`, and two
  consecutive commands. Assert distinct increasing IDs and the real exit code.
- [ ] Add bash cases for the same lifecycle and assert no hook implementation text appears
  as a command.
- [ ] Add fish cases for success, failure, syntax error, and an empty prompt cycle. Skip
  only when `fish` is absent, and print the executable check in the test result.
- [ ] Add chunk-splitting cases in which every byte can be a PTY read boundary.
- [ ] Write the observed canonical sequences to `real-shell-blocks.json` for reuse by Go
  assembler tests.
- [ ] Run the tests and confirm zsh and bash fail for the known reasons before editing a
  bootstrap script:

```bash
node --test packages/terminal/shell/*.test.mjs
```

- [ ] Sabotage: make the expected second ID equal the first. Confirm the test fails, then
  restore the assertion.
- [ ] Commit: `test(terminal): pin real shell block streams`

### Task 2: Emit one ordered, stable lifecycle from zsh, bash, and fish

**Files:**

- Modify: `packages/terminal/shell/zsh.sh`
- Modify: `packages/terminal/shell/bash.sh`
- Modify: `packages/terminal/shell/fish.fish`
- Modify: checked-in bootstrap copies under `packages/terminal/go/bootstrap/`
- Modify: corresponding tests from Task 1

Use one lifecycle in every shell:

```text
pre-command prompt:
  capture previous exit status before any helper runs
  if a command was executing: OSC7000(id=current, exit=code), OSC133(D;code)
  allocate current ID in the parent shell
  OSC7000(id=current, cwd, branch), OSC133(A)
  render prompt, OSC133(B), input-ready

pre-exec:
  OSC7000(id=current, cmd=exact submitted command), input-released, OSC133(C)
```

- [ ] Generate IDs as `<terminal-handle>-<parent-shell-counter>` using only the protocol's
  `[A-Za-z0-9_-]` ID alphabet. Pass the terminal handle
  in `RuntimeConfig.Env` as `OPERATOR_TERMINAL_ID`; never increment the counter inside zsh
  command substitution or another subshell.
- [ ] In zsh, save `$?` as the first `precmd` operation, before `emulate`, git lookup, or
  formatting. Use `add-zsh-hook` without replacing user hooks.
- [ ] In bash, guard DEBUG recursion, ignore prompt/helper evaluation, preserve and chain
  existing `PROMPT_COMMAND` and DEBUG traps, and capture `BASH_COMMAND` only for a real
  submitted command.
- [ ] In fish, use preexec/postexec/prompt events and the error-prompt path so syntax errors
  close their block. Keep functions idempotent across `exec fish` and nested shells.
- [ ] Emit exit metadata before OSC 133 D so the daemon has all metadata when D finalizes
  the block. Emit next-block metadata before A.
- [ ] Ensure OSC payload escaping is byte-for-byte compatible with `go/marks` and the Rust
  and TypeScript decoders.
- [ ] Update the bootstrap divergence test so package assets and embedded Go copies cannot
  drift.
- [ ] Run:

```bash
node --test packages/terminal/shell/*.test.mjs
cd packages/terminal/go/bootstrap && go test ./...
npm --prefix packages/terminal run check:boundaries
```

- [ ] Sabotage: move zsh's exit capture below `emulate -L zsh`; confirm the `false` test
  reports the regression, then restore it.
- [ ] Commit: `fix(terminal): stabilize shell mark ordering`

### Task 3: Make `go/marks` lossless and cursor-aware

**Files:**

- Modify: `packages/terminal/go/marks/marks.go`
- Modify: `packages/terminal/go/marks/scanner.go`
- Modify: `packages/terminal/go/marks/marks_test.go`
- Modify: shared protocol vectors only if a missing recovery case is discovered

The current callback API returns semantic marks but not the bytes between them. Replace
the daemon-facing API with a lossless stream decoder while keeping mark parsing reusable:

```go
type Token struct {
    Kind TokenKind
    Raw []byte
    Mark Mark
    Start int64
    End int64
}

func (d *Decoder) Feed(chunk []byte) []Token
func (d *Decoder) Flush() []Token
func (d *Decoder) ResetAt(offset int64)
```

`Raw` must concatenate back to the original input exactly, including malformed escape
sequences. `Start` and `End` are absolute offsets within one journal epoch.

- [ ] Add tests proving `bytes.Join(token.Raw)` equals the input for plain UTF-8,
  arbitrary bytes, split OSC, malformed OSC, SGR, and alternate-screen sequences.
- [ ] Add a reset/gap test: begin mid-OSC, call `ResetAt`, feed noise, then a valid A/C/D
  sequence. The decoder must recover without assigning pre-gap bytes to a block.
- [ ] Add `Flush` tests for a terminal ending after ordinary output and ending inside an
  incomplete escape sequence.
- [ ] Preserve every §7.4 semantic recovery rule.
- [ ] Run:

```bash
cd packages/terminal/go/marks && go test ./...
```

- [ ] Sabotage: omit the OSC terminator from `Raw`; confirm round-trip tests fail, then
  restore it.
- [ ] Commit: `feat(terminal): expose lossless mark tokens`

### Task 4: Add a durable terminal-block model instead of overloading agent events

**Files:**

- Create: `backend/internal/domain/terminalblock.go`
- Create: `backend/internal/service/terminalblock/types.go`
- Create: `backend/internal/service/terminalblock/service.go`
- Create: `backend/internal/service/terminalblock/service_test.go`
- Create: `backend/internal/storage/sqlite/migrations/0092_terminal_blocks.sql`
- Create: `backend/internal/storage/sqlite/queries/terminal_blocks.sql`
- Modify: `backend/internal/storage/sqlite/store.go`
- Regenerate: `backend/internal/storage/sqlite/gen/*` with `npm run sqlc`
- Modify: SQLite integration/migration tests beside the existing block-event tests

Do not add shell fields to `block_events`. That table is an append-only agent hook event
log keyed by sequence; a shell block is a completed, idempotently upserted terminal
artifact with raw bytes and different retention.

Create `terminal_blocks` with these columns:

```sql
terminal_id TEXT NOT NULL
source_id TEXT NOT NULL
session_id TEXT NOT NULL DEFAULT ''
command TEXT NOT NULL DEFAULT ''
cwd TEXT NOT NULL DEFAULT ''
git_branch TEXT NOT NULL DEFAULT ''
exit_code INTEGER
raw_output BLOB NOT NULL
started_at TIMESTAMP
finished_at TIMESTAMP NOT NULL
shell_kind TEXT NOT NULL DEFAULT ''
shell_version TEXT NOT NULL DEFAULT ''
truncated_lines INTEGER NOT NULL DEFAULT 0
truncated_bytes INTEGER NOT NULL DEFAULT 0
capture_epoch TEXT NOT NULL
start_offset INTEGER NOT NULL
end_offset INTEGER NOT NULL
created_at TIMESTAMP NOT NULL
PRIMARY KEY (terminal_id, source_id)
```

Add indexes for `(terminal_id, finished_at DESC)` and non-empty `session_id`. The migration
must add SQLite triggers that write `change_log`; service/store methods must not emit
manual CDC rows.

Expose this service boundary:

```go
type Store interface {
    UpsertTerminalBlock(context.Context, Block) error
    ListTerminalBlocks(context.Context, string, int) ([]Block, error)
    TrimTerminalBlocks(context.Context, string, int) error
    DeleteTerminalBlocks(context.Context, string) error
}

func (s *Service) Record(context.Context, Block) error
func (s *Service) History(context.Context, terminalID string, limit int) ([]Block, error)
```

- [ ] Test insert, same-ID replay/upsert, nullable exit code, arbitrary non-UTF-8 output,
  chronological history, per-terminal isolation, deletion, and 100-row retention.
- [ ] Test the 5,000-line and 8 MiB limits. Truncate only at a complete byte boundary,
  retain the newest output, and report omitted line and byte counts.
- [ ] Test migration from a database at migration 0091. Do not modify migrations 0090 or
  0091.
- [ ] Run:

```bash
npm run sqlc
cd backend && go test ./internal/storage/sqlite/... ./internal/service/terminalblock/...
```

- [ ] Sabotage: change the upsert conflict key to `source_id` alone; confirm two terminals
  using the same counter fail the isolation test, then restore it.
- [ ] Commit: `feat(storage): persist terminal blocks`

### Task 5: Replace rename rotation with a writer-owned bounded journal

**Files:**

- Create: `backend/internal/terminalcapture/journal.go`
- Create: `backend/internal/terminalcapture/journal_test.go`
- Create: `backend/internal/terminalcapture/sink.go`
- Create: `backend/internal/terminalcapture/sink_test.go`
- Create: `backend/internal/cli/pane_capture.go`
- Create: `backend/internal/cli/pane_capture_test.go`
- Modify: `backend/internal/cli/root.go`
- Delete after replacement: rename/truncation code in
  `backend/internal/terminal/capture.go` on the implementation branch

Register a hidden internal command matching the existing `opr pty-host` pattern:

```text
opr pane-capture --dir <validated-terminal-journal-dir> --epoch <uuid>
```

The tmux pipe writes directly to this helper's stdin. The helper writes
`<sequence>.open`, rotates itself at 1 MiB, fsyncs, and atomically renames the closed file
to `<sequence>.ready`. It retains eight ready files plus the active file. On stdin EOF it
seals the final non-empty file and writes an atomic epoch manifest containing the final
sequence and byte offset.

- [ ] Reject an output directory outside the configured capture root. Construct the root
  in the daemon and pass the resolved absolute path; do not trust a user-facing CLI path.
- [ ] Use monotonically named segments within a random epoch directory. The reader orders
  by epoch manifest and sequence, never filesystem mtime.
- [ ] Write an atomic `gap.json` before pruning an unread sealed segment. Include the first
  retained sequence so the decoder knows to reset.
- [ ] Never rename or truncate an `.open` file from the reader. Only the writer seals it.
- [ ] Make the helper independent of daemon lifetime. Killing and restarting the daemon
  must not block tmux or stop segment rotation.
- [ ] Test >10 MiB input with no reader: disk use stays within the stated bound, the helper
  keeps consuming stdin, and the newest segment contains the final sentinel.
- [ ] Test a reader concurrently consuming while rotation occurs; concatenated retained
  bytes are ordered with no duplicates.
- [ ] Test EOF with a short last segment and confirm it becomes `.ready` before process
  exit.
- [ ] Run:

```bash
cd backend && go test ./internal/terminalcapture ./internal/cli
```

- [ ] Sabotage: rotate a file from the reader instead of the writer and keep the writer's
  descriptor open. Confirm the integration test detects that new bytes remain on the old
  inode, then restore the segmented design.
- [ ] Commit: `feat(terminal): add bounded capture journal`

### Task 6: Make tmux capture state observable and idempotent

**Files:**

- Modify: `backend/internal/ports/outbound.go`
- Modify: `backend/internal/adapters/runtime/tmux/commands.go`
- Modify: `backend/internal/adapters/runtime/tmux/tmux.go`
- Modify: `backend/internal/adapters/runtime/tmux/tmux_test.go`
- Modify: `backend/internal/adapters/runtime/tmux/tmux_integration_test.go`

Replace the write-only `StartCapture`/`StopCapture` surface with:

```go
type PaneCaptureState struct {
    PipeOpen bool
    AlternateOn bool
}

type PaneCapturer interface {
    CaptureState(context.Context, RuntimeHandle) (PaneCaptureState, error)
    StartCapture(context.Context, RuntimeHandle, []string) error
    StopCapture(context.Context, RuntimeHandle) error
}
```

The adapter must read `#{pane_pipe}` and `#{alternate_on}` in one
`display-message -p -t <target>` call. `StartCapture` must use `pipe-pane -o` and a
shell-escaped argv built from the current executable plus `pane-capture` arguments.

- [ ] Unit-test exact argv and quoting for spaces, quotes, and shell metacharacters.
- [ ] Return a typed unsupported-capability error on ConPTY rather than adding a fake
  capture implementation.
- [ ] Real-tmux test: start a pane, assert pipe false/alternate false, start capture twice,
  assert one pipe, enter alternate screen, assert `AlternateOn`, leave, stop, assert false.
- [ ] Run:

```bash
cd backend && go test ./internal/adapters/runtime/tmux
```

- [ ] Sabotage: remove `-o`; confirm the second-start integration test exposes replacement
  or duplication, then restore it.
- [ ] Commit: `feat(tmux): expose pane capture state`

### Task 7: Assemble exact blocks, alternate-screen gaps, and final drain

**Files:**

- Replace: `backend/internal/terminal/capture.go`
- Replace/extend: `backend/internal/terminal/capture_test.go`
- Create: `backend/internal/terminal/block_assembler.go`
- Create: `backend/internal/terminal/block_assembler_test.go`

The capture worker reads journal cursors and feeds lossless tokens into a state machine.
It owns no lifecycle map; Task 8 owns workers.

Required state:

```go
type CaptureCursor struct {
    Epoch string
    Segment uint64
    Offset int64
}

type BlockAssembler struct {
    TerminalID string
    SessionID string
    AlternateOn bool
}
```

- [ ] Seed `AlternateOn` from Task 6 before calling `Feed` for the first time.
- [ ] Start a block at A, attach exact command metadata to the current ID, begin output at
  C, and finalize only after the matching D and preceding exit metadata.
- [ ] Persist `raw_output` as a self-contained replay stream from the block's first
  OSC7000/A mark through D, including the real prompt, input echo, styling, control bytes,
  and closing marks. Do not synthesize a header or command during replay. When retention
  drops old output, preserve the original prefix/boundary marks and suffix/D bytes around
  the exact retained output tokens so the stream remains parseable.
- [ ] If alternate mode begins during an executing command, allow its boundary metadata
  and D to finish the block while excluding all repaint payload. Ignore new block starts
  until alternate mode leaves.
- [ ] On journal gap, discard the partial block, reset the decoder at the retained cursor,
  and recover on the next A. Never splice bytes from opposite sides of a gap.
- [ ] For Tier 1 streams without OSC 7000 IDs, derive
  `osc133-<epoch>-<A-start-offset>` using the protocol's ID alphabet. Tier 1 restore is stable within the durable journal;
  Tier 2 IDs remain stable across journal epochs and daemon restarts.
- [ ] Checkpoint a cursor only after every finalized block through that cursor commits.
  Re-reading from the prior checkpoint must upsert, not duplicate.
- [ ] Implement `Drain(ctx, final bool)`: read every currently durable byte, call decoder
  `Flush` only when the writer is sealed, persist the last complete block, persist the
  cursor, and return. An unfinished command remains recoverable unless explicit terminal
  close makes completion impossible, in which case store it with `exit_code = NULL` and a
  finished timestamp.
- [ ] Test all protocol recovery rows, initial alternate-on, enter/leave split across
  chunks, in-flight completion, gap recovery, replay from old cursor, and cancellation
  followed by final drain.
- [ ] Run:

```bash
cd backend && go test ./internal/terminal
```

- [ ] Sabotage: return immediately on `ctx.Done()` before `Drain`; confirm the last-block
  shutdown test fails, then restore final drain.
- [ ] Commit: `feat(terminal): assemble durable shell blocks`

### Task 8: Own capture for the whole shell-terminal lifecycle

**Files:**

- Create: `backend/internal/service/terminalcapture/supervisor.go`
- Create: `backend/internal/service/terminalcapture/supervisor_test.go`
- Modify: `backend/internal/service/shellterm/service.go`
- Modify: `backend/internal/service/shellterm/service_test.go`
- Modify: `backend/internal/daemon/shellterm_wiring.go`
- Modify: `backend/internal/daemon/shellterm_wiring_test.go`
- Modify: `backend/internal/daemon/daemon.go`

Use an injected narrow lifecycle interface in `shellterm`; do not make it import tmux or
the terminal manager:

```go
type BlockCaptureLifecycle interface {
    Start(context.Context, ShellTerminalRecord) error
    StopAndDrain(context.Context, string) error
}
```

The supervisor owns the worker map and exposes:

```go
func (s *Supervisor) Start(context.Context, shellterm.ShellTerminalRecord) error
func (s *Supervisor) Adopt(context.Context, []shellterm.ShellTerminalRecord) error
func (s *Supervisor) StopAndDrain(context.Context, string) error
func (s *Supervisor) DrainAndDetach(context.Context) error
```

- [ ] New terminal: create runtime, insert row, start capture, then return. If capture is
  unsupported, return the terminal with a capability field set false. If capture fails on
  a supported runtime, destroy the runtime and delete the row so “blocks available” never
  names an uncaptured pane.
- [ ] Daemon boot: reap prior-app-run terminals first; list current-app-run terminals;
  confirm liveness; then `Adopt`. If `#{pane_pipe}` is already true, resume the existing
  journal without replacing its helper. If false, start a new epoch.
- [ ] Explicit shell close and session teardown: call `StopAndDrain` before runtime
  destruction. If stop/drain fails, preserve the shell row and do not remove its worktree.
- [ ] Daemon shutdown: call `DrainAndDetach` before store close. Leave live current-app-run
  tmux pipes running so a desktop-supervised daemon restart loses no bytes. Save the latest
  committed cursor; remaining journal bytes are adopted next boot.
- [ ] Dead runtime reconciliation: final-drain a sealed journal before deleting the shell
  row. Keep its completed block history until the terminal's explicit history-retention
  policy removes it; do not cascade-delete merely because the PTY exited.
- [ ] Bound every shutdown wait by `cfg.ShutdownTimeout` and join worker errors. Never hold
  the shell session gate while waiting without honoring context cancellation.
- [ ] Unit-test start rollback, idempotent start, adoption with existing pipe, adoption
  without pipe, close ordering, session teardown ordering, failed drain row preservation,
  daemon detach, and unsupported capability.
- [ ] Run:

```bash
cd backend && go test ./internal/service/terminalcapture ./internal/service/shellterm ./internal/daemon
```

- [ ] Sabotage: remove `Adopt` from boot wiring; confirm the daemon-restart test misses a
  command run while the daemon is down, then restore it.
- [ ] Commit: `feat(daemon): supervise shell block capture`

### Task 9: Publish terminal blocks and expose terminal-keyed raw history

**Files:**

- Modify: `backend/internal/terminal/protocol.go`
- Modify: `backend/internal/terminal/manager.go`
- Modify: `backend/internal/terminal/manager_test.go`
- Modify: `backend/internal/httpd/controllers/shell_terminals.go`
- Modify: `backend/internal/httpd/controllers/shell_terminals_test.go`
- Modify: `backend/internal/httpd/controllers/dto.go`
- Modify: `backend/internal/httpd/apispec/specgen/build.go`
- Regenerate: `backend/internal/httpd/apispec/openapi.yaml`
- Regenerate: `frontend/src/api/schema.ts`

Do not put terminal history behind the existing session-block endpoint. A standalone
shell has no session, and the terminal mux is keyed by runtime handle. Add:

```text
GET /api/v1/shell-terminals/{handleId}/blocks?limit=100
```

Response block fields are `terminalId`, `sourceId`, optional `sessionId`, `command`, `cwd`,
`gitBranch`, nullable `exitCode`, base64 `rawOutput`, timestamps, shell kind/version,
truncation counts, and capture cursor fields. Return oldest-to-newest so feeding preserves
stream order.

- [ ] Extend the `blocks` mux payload additively with a discriminator such as
  `blockType: "agent_event" | "terminal_block"`. Keep existing agent subscribers and
  their payloads wire-compatible.
- [ ] Publish a terminal block only after its DB commit. Key terminal-block subscriptions
  by terminal handle, not associated session ID.
- [ ] Authorize history only through the same loopback/LAN middleware already protecting
  the shell-terminal API. Do not expose control routes on LAN.
- [ ] Return 404 for an unknown handle, 400 for invalid limits, and the standard API error
  envelope/request ID for failures.
- [ ] Regenerate rather than hand-edit generated files:

```bash
npm run api
cd backend && go test ./internal/httpd/... ./internal/terminal/...
```

- [ ] Sabotage: key publication by `sessionId`; confirm standalone-shell delivery fails,
  then restore handle-keyed publication.
- [ ] Commit: `feat(api): expose terminal block history`

### Task 10: Restore exact history before opening the live stream

**Files:**

- Create: `frontend/src/renderer/hooks/useShellTerminalBlocks.ts`
- Create: `frontend/src/renderer/hooks/useShellTerminalBlocks.test.tsx`
- Modify: `frontend/src/renderer/hooks/useTerminalSession.ts`
- Modify: `frontend/src/renderer/hooks/useTerminalSession.test.tsx`
- Modify: `frontend/src/renderer/components/TerminalPane.tsx`
- Modify: `frontend/src/renderer/components/TerminalPane.test.tsx`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`
- Modify: `frontend/src/renderer/components/BlockTerminal.test.tsx`
- Modify: `frontend/src/renderer/lib/terminal-mux.ts`

Delete synthetic `encodeHistoryBlock`. History must feed decoded `rawOutput` bytes into a
fresh core in chronological order. Avoid a REST/live race by adding `enabled` to
`useTerminalSession`: for a shell target, fetch history and initialize the block core
first, then open the terminal mux. Bytes arriving after open are live and therefore newer
than the history snapshot.

- [ ] Fetch terminal history only for `terminalTarget.kind === "shell"`. Agent/reviewer
  surfaces retain their existing behavior.
- [ ] Decode base64 without round-tripping through a JavaScript string that can corrupt
  arbitrary bytes.
- [ ] Initialize the core, feed history, set its seen Tier-2 IDs, then enable terminal
  attach. Buffer live bytes only during WASM initialization after this barrier.
- [ ] Remove the current duplicate strategy that strips only an OSC 7000 ID mark while
  retaining the duplicate block bytes. With history-before-open, a completed block belongs
  to exactly one side of the barrier. Keep ID-based upsert behavior only for reconnect of
  an in-flight Tier-2 block.
- [ ] Surface loading and history-fetch errors without blocking raw terminal access. On
  history failure, show the warning and open live transport.
- [ ] Use the API capability field to render `TerminalStrings.shellBlocksUnavailable` on
  Windows; do not infer support from browser platform strings.
- [ ] Test three restored blocks followed by one live block, binary SGR/OSC preservation,
  history failure fallback, terminal switch generation safety, and no duplicate attach.
- [ ] Run:

```bash
npm --prefix frontend test -- BlockTerminal TerminalPane useTerminalSession useShellTerminalBlocks
npm run frontend:typecheck
```

- [ ] Sabotage: enable the terminal mux before the delayed history promise resolves;
  confirm the ordering test fails, then restore the barrier.
- [ ] Commit: `feat(frontend): restore raw shell block history`

### Task 11: Prove lifecycle and Warp-visible parity end to end

**Files:**

- Create: `backend/internal/integration/shell_blocks_tmux_test.go`
- Modify: `frontend/e2e/shell-terminal-tabs.spec.ts`
- Create: `docs/superpowers/evidence/shell-blocks-parity.md`

The Go integration test may use local tmux and installed shells, following the existing
tmux integration pattern. It must not make network calls.

- [ ] Scenario: start daemon services and a zsh pane with zero clients, run three commands,
  attach one client, and assert three historical blocks and no duplicates.
- [ ] Scenario: attach two clients, run one command, and assert one DB row and one published
  terminal-block event.
- [ ] Scenario: stop only the daemon reader, run commands while tmux/helper remain alive,
  construct a new supervisor with the same app-run ID, adopt, and assert all commands.
- [ ] Scenario: start capture while `#{alternate_on}` is true, generate repaint traffic,
  leave alternate mode, run a command, and assert repaint bytes were not stored.
- [ ] Scenario: write beyond journal capacity while the daemon is absent, restart, verify a
  recorded gap and recovery at the next prompt without a corrupt merged block.
- [ ] Scenario: submit a final command and immediately close the shell. Assert its row is
  persisted before runtime deletion.
- [ ] Scenario: graceful daemon shutdown followed by restart within the same app run.
  Assert the last completed block is present exactly once.
- [ ] Browser e2e: run success/failure/cd/styled-output commands, reload, and compare block
  count, text, styling, metadata, and exit indicators before and after reload.
- [ ] Record a parity matrix against the local Warp checkout. Use these references as
  behavioral evidence, not code to copy:
  - `app/assets/bundled/bootstrap/zsh_body.sh` for early exit capture and preexec command;
  - `crates/warp_terminal/src/model/ansi/dcs_hooks.rs` for prompt/preexec/completion
    lifecycle semantics;
  - `app/src/terminal/model/blocks.rs` for completing the active block before allocating
    the next;
  - `crates/persistence/src/schema.rs` for stored command/output metadata;
  - `app/src/persistence/block_list.rs` and `app/src/terminal/model/block.rs` for the
    100-block/5,000-line limits.
- [ ] Run:

```bash
cd backend && go test ./internal/integration -run ShellBlocks -count=1
npm --prefix frontend run test:e2e -- shell-terminal-tabs.spec.ts
```

- [ ] Commit: `test(terminal): prove shell block lifecycle parity`

### Task 12: Amend the spec and close obsolete plan claims

**Files:**

- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`
- Modify: `docs/superpowers/plans/2026-08-28-shell-blocks.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/architecture.md`

- [ ] Rewrite §7.5 to require lossless raw spans and journal cursors, not merely semantic
  mark callbacks.
- [ ] Rewrite §13.2 with the helper journal, tmux state query, supervisor adoption,
  dedicated `terminal_blocks` persistence, terminal-keyed history, and final-drain order.
- [ ] Rewrite §13.3 to say history is raw replay loaded before terminal attach. Remove the
  stale claim that the existing session block-event endpoint returns pre-parsed shell
  blocks.
- [ ] Clarify §13.4: shell-terminal tabs may be retired in phase 7, but their handle-keyed
  capture/history ownership remains the current production bridge and must be migrated,
  not deleted, when one-session/one-terminal lands.
- [ ] Replace the backend half of the 2026-08-28 plan with a pointer to this amended plan so
  no future worker executes both.
- [ ] Document the Windows capability and the two retention limits.
- [ ] Run documentation link/path verification and the docs guard. Correct every stale
  symbol, route, and command before marking this task complete.
- [ ] Commit: `docs(terminal): settle production shell block design`

### Task 13: Full verification and clean-code review

- [ ] Run the narrow suites from every prior task.
- [ ] Run repository gates:

```bash
npm run lint
npm run frontend:typecheck
cd backend && go build ./... && go test ./... && go test -race ./... && go vet ./...
npm --prefix packages/terminal test
npm --prefix packages/terminal run check:boundaries
cd frontend && npm run check:desktop-parity && node --test scripts/no-electron.test.mjs
```

- [ ] Run `superpowers:requesting-code-review`, then `clean-code-guard`, `test-guard`, and
  `docs-guard`. Fix findings within scope and rerun affected gates.
- [ ] Inspect `git diff --check`, generated API/sqlc drift, and `git status --short`. Do not
  include local daemon state, build output, the root worktree's untracked
  `docs/superpowers/prompts/`, or unrelated user changes.
- [ ] Launch the real desktop app with the repository's `opr-desktop-dev` skill, open an
  external preview with `opr preview`, and execute the Task 11 manual parity matrix.
- [ ] Do not claim completion until the last-block close test, daemon-restart adoption test,
  bounded-journal test, real zsh/bash tests, and frontend history-before-live test are all
  green.
- [ ] Commit: `feat(terminal): complete production shell blocks`

---

## Release acceptance

The feature is production-ready only when all of these are demonstrated:

1. zsh, bash, and fish each produce stable IDs, exact commands, correct exit status, cwd,
   branch, and one A/B/C/D lifecycle per submitted command.
2. A command run with zero clients appears after attach; two clients do not duplicate it.
3. Reload and daemon restart restore exact styled bytes once, in order.
4. A pane already in alternate-screen mode at capture start stores no repaint history.
5. Capture remains bounded while the daemon is stopped and tmux continues accepting
   output.
6. Explicit close persists the final block before destroying the PTY.
7. The daemon's graceful shutdown cannot strand committed bytes after SQLite closes;
   uncommitted durable bytes are adopted on restart.
8. Windows presents a working raw terminal and an explicit durable-block capability
   message.
9. Operator matches the Warp-visible parity matrix while preserving Operator's additive
   bootstrap, protocol, data-root, listener, and daemon/API safety boundaries.

Anything less is an intermediate milestone, not completion.
