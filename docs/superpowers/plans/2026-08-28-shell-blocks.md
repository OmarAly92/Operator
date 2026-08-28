# Plan 7 — Shell blocks: the terminal becomes the session surface

Status: written
Date: 2026-08-28
Spec: `docs/superpowers/specs/2026-08-27-session-blocks-design.md`, step 9
Scope: `backend/internal/{terminal,adapters/runtime/tmux,service/shellterm,service/blockevent,domain,ports}`, `frontend/src/renderer`, `packages/mobile`, `testdata/`
Depends on: plans 1-6, all landed. Independent of 8 and 9.

## Why this plan exists, stated plainly

Plans 1 through 6 built an agent-session viewer. Running the desktop app makes that
obvious: the composer under the block list posts to
`/api/v1/sessions/{sessionId}/send` (`CenterPane.tsx:1071`), which types into the
agent's TUI. **You cannot run a command.** `blockevent` has no shell support at all —
the only trace is a comment at `service/blockevent/types.go:15` saying a shell mark's
counter comes "later".

This plan is later. It is what makes Operator a terminal that understands agents
rather than an agent dashboard with a terminal toggle.

## Product decisions already made — do not relitigate

Settled by the user on 2026-08-28:

1. **One session, one tab, one terminal.** The app's tab strip is the *session* list.
   A session has exactly one terminal surface. There are no per-session shell tabs.
2. **The terminal is the session surface**, not a third mode. Raw stays as the toggle
   for when a full-screen TUI owns the pane.
3. **Multi-tab shell terminals are retired.** `ShellTerminalsView.tsx` (180 lines),
   `ShellTerminalTab.tsx` (194), `useShellTerminals.ts` (158), the `CenterPane` tab
   strip, the inline rename gesture, the `/terminals` route and
   `frontend/e2e/shell-terminal-tabs.spec.ts` all go. Task 9 owns that, and it is the
   last task so a revert costs nothing before it.

## Read this before you plan any work

### The spec's mechanism does not work. This is the finding the plan turns on.

The spec says: *"Marks arrive in-band on the PTY… The daemon parses them out of the
terminal stream and republishes on the `blocks` channel."*

**There is no daemon-side terminal stream.** `newAttachment` is constructed inside a
*client connection* (`backend/internal/terminal/manager.go:448`), and
`backend/internal/terminal/doc.go:11` states the model: per-client attach, "one client
process (tmux) or one loopback connection (conpty) per open pane **per connection**."

Two consequences, both fatal to in-band parsing at `attachment.onData`
(`attachment.go:52`, the sink; `copyOut` at `:191` is the pump):

- **Two clients attached → every mark parsed twice → duplicate blocks.** Desktop and
  phone open on the same session routinely; this is the normal case, not the edge.
- **Zero clients attached → no stream exists → no blocks recorded.** Commands you run
  before opening the app would leave no trace. A terminal whose scrollback depends on
  someone watching is not a terminal.

**Use `tmux pipe-pane` instead.** It streams a pane's output server-side to a command,
independent of client attaches, exactly once. The tmux adapter already shells out for
`capture-pane` (`adapters/runtime/tmux/commands.go:121`) and has never used
`pipe-pane`. That is the capture path this plan adds.

**Windows gets no shell blocks.** conpty has no `pipe-pane` equivalent, and inventing
a tee inside the pty-host is a second capture mechanism for one platform. A Windows
session opens in Raw and says shell blocks are unavailable — the same visible-absence
rule the spec already applies to an unrecognized shell. Do not silently degrade.

### What already exists, and what it gives you

| Thing | Where | What it gives this plan |
| --- | --- | --- |
| `ports.RuntimeConfig{Argv, Env}` | `ports/outbound.go:119` | both bootstrap injection vectors |
| `resolveUserLoginShell()` | `service/shellterm/loginshell.go:20` | returns a bare `[$SHELL]`; the argv hook |
| `blockevent.Service.Record` | `service/blockevent/service.go:46` | redaction, truncation, persistence, trimming, publish |
| `blocks` mux channel | `terminal/protocol.go`, `lib/terminal-mux.ts:75` | live delivery both clients already consume |
| `GET /sessions/{id}/blocks` | `controllers/sessions.go:194` | history paging both clients already use |
| Block screens | `components/blocks/`, `feature/blocks/` | rendering, viewport, find, actions |

The pipeline from "a block event exists" to "it is on both screens" is done. This plan
only has to produce shell block events and render bytes.

### `Record` takes the wrong shape and must not be bent

`Service.Record(ctx, sessionID, harness, sig ports.ActivitySignal)` is hook-shaped:
`Event`, `ToolName`, `ToolUseID`, `LatestAssistantUpdate` (`ports/runtime_observations.go:41`).
A shell command is none of those. **Add a second entry point, do not overload
`ActivitySignal`** — a `ToolUseID` that is really a command counter is the kind of lie
that costs a week later.

### The block model renders plain text, and mobile's ANSI decoder was deleted

Neither `BlockCard.tsx` nor `block_card.dart` handles escape sequences — grep for
`\x1b` in both block trees returns nothing. Mobile's `logic/ansi.dart` was **deleted**
in commit `72e18d1b1` as unreachable code during the plan-6 cleanup. Restoring ANSI
rendering is therefore a cost this plan inherits from that cleanup, not new scope.

The spec is unambiguous about why it matters: *"A shell block carries the real bytes
between its marks, not a description of them. Anything less is not what Warp does and
not worth building."*

### Alt screen is tracked nowhere

No `1049`, `alt_screen` or equivalent anywhere in `internal/terminal` or
`XtermTerminal.tsx`. Task 4 adds it, in the same parser pass as the marks, because
block capture must suspend while a full-screen TUI owns the pane.

### Conventions

**Backend** (`AGENTS.md`): `npm run lint` from the repo root is the gate. Never edit
`backend/internal/storage/sqlite/gen/` or `apispec/openapi.yaml` by hand. Anything
touching `queries/` or `migrations/` runs `npm run sqlc`; anything changing REST runs
`npm run api`. Go files in this repo comment their exported surface heavily — match the
neighbours.

**Mobile** (`CLAUDE.md`): Cubit only. Static-only classes are `sealed class X`. No
`freezed`/`json_serializable`; hand-written models, all fields nullable. `drift` is
plan 9's cache exception and does not reach here. No `flutter_screenutil` in feature
code. Inline English copy. `AppSkin` via `context.skin`, `AppTextStyle.style<Size><Weight>`.

**Desktop** (`DESIGN.md`): shadcn primitives from `components/ui/*`; agent-orchestrator's
visual language with the refined-blue accent. **Every new string goes into all eight
locale files** — `en, zh-CN, ja, ko, es, fr, de, pt-BR` — non-empty and with matching
`{{placeholders}}`; `i18n/instance.test.ts:149` and `i18n/renderer-coverage.test.ts`
both enforce it. The terminal palette carve-out applies to Raw mode only.

**Global:** no code comments unless the surrounding file already comments heavily.
App state resolves under `~/.operator` only.

**Two mobile behaviours that must not be "optimized"**: the 12-second Dio timeouts and
the sequential auth probing in `sessions_remote_data_source.dart`. Neither is in this
plan's path.

## Verification gates

```bash
npm run lint
```
```bash
npm run frontend:typecheck
```
```bash
npm --prefix frontend run test
```
```bash
flutter analyze
```
```bash
flutter test
```

`flutter analyze` must print `No issues found!`; both Flutter commands run from
`packages/mobile`. `npm run api` is needed only if a REST surface changes (task 6 may).
Browser e2e (`npm --prefix frontend run test:e2e`) is a task-10 gate.

**Tasks 4 and 5 have no automated gate.** Shell bootstraps and `pipe-pane` are verified
by running real shells; `go test` cannot cover them. Task 5 states the manual script and
you run it.

---

## Task 1 — Shell vocabulary and a shell-shaped record path.

`backend/internal/domain/blockevent.go` gains two kinds beside the existing ten:

```go
BlockEventCommandStart BlockEventKind = "command_start"
BlockEventCommandEnd   BlockEventKind = "command_end"
```

`ParseBlockEventKind` accepts both.

`backend/internal/service/blockevent/service.go` gains a second entry point beside
`Record`:

```go
// ShellCommand is one command's boundary event, minted by the shell bootstrap
// rather than by a hook. Seq is assigned by the store as usual; Ordinal is the
// shell's own per-session counter and becomes the record's SourceID, so a
// command_end correlates with the command_start that opened it.
type ShellCommand struct {
    Ordinal   int
    Command   string
    Cwd       string
    ExitCode  *int
    Output    []byte
    StartedAt time.Time
    EndedAt   time.Time
}

func (s *Service) RecordShell(ctx context.Context, sessionID domain.SessionID, cmd ShellCommand) error
```

`RecordShell` reuses the existing redaction, `maxTextBytes` truncation with the dropped
count preserved, persistence and publish — it must not fork that logic. `SourceID` is
`fmt.Sprintf("sh-%d", cmd.Ordinal)`, mirroring the hook path's `src-<toolUseId>`;
`Harness` is the empty string, because no agent produced it.

**Do not overload `ports.ActivitySignal`.** See the note above.

**Tests:** table tests in `service/blockevent/service_test.go` — ordinal correlation,
redaction over a command that echoes a secret, truncation preserving the dropped count,
a `command_end` with no matching `command_start`, exit code 0 vs non-zero.

**Gate:** `npm run lint`.

## Task 2 — `pipe-pane` capture in the tmux adapter.

`backend/internal/adapters/runtime/tmux/commands.go` gains, beside `capturePaneArgs`:

```go
// pipePaneArgs builds args for `tmux pipe-pane -t <id> -o <shell-command>`.
// -o toggles the pipe only if not already piping, which makes a repeated start
// idempotent. Output is server-side and independent of client attaches, which
// is the whole reason this exists: per-client attach means onData fires once
// per connected client and not at all when none is connected.
func pipePaneArgs(id, command string) []string {
    return []string{"pipe-pane", "-t", id, "-o", command}
}

// pipePaneOffArgs stops the pipe: `tmux pipe-pane -t <id>` with no command.
func pipePaneOffArgs(id string) []string {
    return []string{"pipe-pane", "-t", id}
}
```

Expose it as an **optional runtime capability**, following the precedent
`ports.SupervisedProcessInspector` sets at `ports/outbound.go:140`:

```go
// PaneRecorder is an optional runtime capability: a server-side copy of a
// pane's output that does not depend on any client being attached. A runtime
// that cannot provide one returns ErrRecordingUnsupported and its sessions get
// no shell blocks.
type PaneRecorder interface {
    StartRecording(ctx context.Context, handle RuntimeHandle, sinkPath string) error
    StopRecording(ctx context.Context, handle RuntimeHandle) error
}
```

tmux implements it; conpty does not, and the conpty adapter must not gain a stub that
silently succeeds.

`sinkPath` is a FIFO under the data dir — `~/.operator/run/panes/<handle>.pipe`,
subject to the hard rule that all app state resolves under `~/.operator`
(`OPERATOR_DATA_DIR`). Never `os.TempDir()`.

**Tests:** arg-shape tests beside `capturePaneArgs`'s at `tmux/tmux_test.go:210`; a
fake-runtime test that a runtime without `PaneRecorder` reports unsupported rather than
erroring the session.

**Gate:** `npm run lint`.

## Task 3 — The mark protocol.

**OSC 133**, not a private sequence. It is what iTerm2, WezTerm, VS Code and Warp
already speak, so a user whose shell already emits it works with no bootstrap at all.

| Sequence | Meaning | This plan uses it for |
| --- | --- | --- |
| `ESC ] 133 ; A ST` | prompt start | ends the previous command's output capture |
| `ESC ] 133 ; B ST` | prompt end / input start | — |
| `ESC ] 133 ; C ST` | command start (output begins) | `command_start`, opens capture |
| `ESC ] 133 ; D ; <exit> ST` | command end | `command_end` with exit code |

Two extensions carried as OSC 133 parameters because nothing standard covers them:
`ESC ] 133 ; C ; cmdline=<base64> ; ord=<n> ST`. Base64 because a command line contains
semicolons and `ST`.

`ST` is `BEL` (`\a`) or `ESC \`. **Accept both.** zsh and bash emit different ones
depending on version and this is a common source of "works on my machine".

Write this as a document in the plan's own words in
`backend/internal/terminal/shellmark/doc.go`, since the package is new and the repo
comments new exported surface.

**Gate:** none yet; task 4 makes it executable.

## Task 4 — The parser, in a new `terminal/shellmark` package.

Pure, allocation-conscious, and **fed by the pipe, never by `onData`**.

```go
// Parser consumes pane bytes and emits command boundaries. It is a state
// machine rather than a regexp because a mark can straddle a read boundary and
// because output that merely looks like a mark must not open a block.
type Parser struct{ ... }

func NewParser() *Parser

// Write feeds a chunk. Events are returned in order; the residue of a partial
// sequence is retained for the next call.
func (p *Parser) Write(chunk []byte) []Event

type Event struct {
    Kind     EventKind // CommandStart, CommandEnd, AltScreenEnter, AltScreenExit
    Ordinal  int
    Command  string
    ExitCode int
    Output   []byte
}
```

Four behaviours, each its own test:

1. **Split reads.** The pipe reader uses a 32KB buffer, matching `copyOut`. A mark split
   across two `Write` calls must still be recognized, including a split *inside* the
   base64 command line.
2. **Mimicry.** `echo $'\e]133;D;0\a'` prints a real escape sequence. It is
   indistinguishable from a genuine mark **and that is correct** — the shell wrote it to
   the pane. What must not happen is a `command_end` with no open `command_start`
   fabricating a block; unmatched ends are dropped and counted.
3. **Alt screen.** `ESC [ ? 1049 h` and `ESC [ ? 47 h` / `ESC [ ? 1047 h` enter;
   the `l` forms exit. While in alt screen the parser emits `AltScreenEnter` once,
   captures no output, and emits `AltScreenExit` on leaving. **This is the `claude`
   case**: a full-screen TUI owns the pane, blocks suspend, Raw shows the real screen,
   and blocks resume with the command's `command_end` when it exits.
4. **Output capture bounds.** Output accumulates between `C` and `D`. Cap it at
   `maxTextBytes` (16KB, `service/blockevent/service.go:19`) with the dropped-line count
   preserved, exactly as the hook path does — a `yes` loop must not grow the heap.

**Tests:** `terminal/shellmark/parser_test.go`, table-driven, byte-level. This is the
one part of the plan that is fully testable in Go; it should be the most thoroughly
tested file in the change.

**Gate:** `npm run lint`.

## Task 5 — The shell bootstrap, per shell.

The part with no automated gate. **Never write to the user's dotfiles.** Injection is
environment-only, through `ports.RuntimeConfig.Env`, which `OpenShellTerminal` already
passes at `service/shellterm/service.go:237`.

Ship the snippets as embedded files under `backend/internal/service/shellterm/bootstrap/`
using `go:embed`, materialized into `~/.operator/run/bootstrap/` at daemon start.

- **zsh** — `ZDOTDIR` points at our directory; our `.zshrc` sources the user's real
  `${ZDOTDIR_ORIG}/.zshrc` **first**, then adds `preexec`/`precmd` functions via
  `add-zsh-hook`. Sourcing the user's rc first is what keeps their prompt and aliases.
- **bash** — `--rcfile` is not usable because it suppresses the user's `~/.bashrc`
  for interactive shells, so use `PROMPT_COMMAND` for the `A`/`D` marks and
  `trap DEBUG` for `C`. Guard against `PROMPT_COMMAND` already being set: append, never
  replace.
- **fish** — `XDG_DATA_DIRS` prepended with our directory containing a
  `fish/vendor_conf.d/` snippet using `fish_preexec` / `fish_postexec` events.
- **anything else** — no bootstrap, no marks, and the session says shell blocks are
  unavailable for that shell. Visible absence, never a silently empty list.

The ordinal counter is a shell variable incremented in `preexec`, so it is the shell's
own and is never invented by the daemon — the spec's ids-minted-at-the-source rule.

**Manual verification script**, run by the implementer and pasted into the task's
completion note:

```
for each of zsh, bash, fish:
  open a session, run:  pwd  /  false  /  ls | head -3  /  printf 'a\nb\n'
  assert: four blocks, exit codes 0,1,0,0, output bytes match the raw pane
  run:    claude            → Raw takes over, no partial block
  exit it                   → one block for `claude` with its exit code
  run:    echo $'\e]133;D;0\a'  → one block, no fabricated second block
```

**Gate:** `npm run lint` for the Go side; the script above for the shells.

## Task 6 — Wire capture to the block stream.

A `shellblocks` component owned by the daemon: for each session whose runtime
implements `PaneRecorder`, start recording to the FIFO, read it, feed `shellmark.Parser`,
and call `blockevent.RecordShell` on each event. Lifecycle follows the session: start on
spawn/restore, stop on teardown, and survive a daemon restart by restarting the pipe
(tmux keeps the pane; `pipe-pane -o` makes the restart idempotent).

`AltScreenEnter`/`AltScreenExit` publish a session-state flag on the existing `blocks`
channel so clients can switch to Raw and back without polling. This is the only new
frame type; keep it additive so an older client ignores it.

Composer targeting: the block composer must send to the **shell** by default in a
session whose terminal is a shell, and to the agent when the agent owns the pane.
`POST /sessions/{id}/send` types into the pane either way, so this is a label-and-intent
change on the client, not a new route — confirm that before adding one, and run
`npm run api` only if you actually add one.

**Tests:** a fake `PaneRecorder` plus a scripted byte stream asserting the full path
produces the expected `Record` calls; restart idempotence; teardown stops the pipe.

**Gate:** `npm run lint`.

## Task 7 — Desktop: ANSI in blocks, and shell blocks in the stream.

- `frontend/src/renderer/lib/ansi.ts` — SGR-only parser producing
  `{text, className}[]` spans. Colours map to the terminal palette's CSS variables
  (`DESIGN.md`'s carve-out covers this), not to arbitrary hex. Ignore cursor movement
  and erase sequences rather than trying to emulate them: a block is a transcript, not
  a screen.
- `BlockCard` renders `shell` blocks through it. Everything else stays plain text, so
  agent blocks are untouched.
- Shell blocks arrive as `BlockDetail{type: "shell", command, output, exitCode}`, which
  **already exists** in `session-block.ts` and already has a `blockDisplay` case. The
  assembly change is mapping `command_start`/`command_end` onto it in
  `lib/block-assembly.ts`.
- The `copy_command` / `copy_output` actions from plan 6 start doing something real
  here; they were written for exactly this detail type.
- Alt-screen flag switches the pane to Raw and back.

**Tests:** ANSI parser unit tests; assembly fixture (task 10); a component test that a
failed command shows its exit code and that ANSI is rendered as spans, not as literal
escape text.

**Gate:** typecheck + vitest.

## Task 8 — Mobile: the same, including restoring ANSI.

`packages/mobile/lib/core/ansi/ansi.dart` — the decoder deleted in `72e18d1b1`, brought
back with the same SGR-only scope as desktop and colours from `context.skin`.
`block_card.dart` renders shell blocks through it as `Text.rich` spans. Assembly mapping
mirrors task 7 against the same fixtures. Alt-screen flag switches to the raw pane.

**Gate:** `flutter analyze` and `flutter test`.

## Task 9 — Retire the multi-tab shell terminals.

Per the user's decision. Delete `ShellTerminalsView.tsx`, `ShellTerminalTab.tsx`,
`useShellTerminals.ts`, the `CenterPane` tab strip and its overflow/rename logic, the
`/terminals` route, and `frontend/e2e/shell-terminal-tabs.spec.ts`. Keep
`service/shellterm` — it is what opens the one terminal a session has; only the
*multiplicity* goes.

Run an import-graph reachability pass from the renderer entry point afterwards and
delete what it orphans. The plan-6 cleanup found a shipped regression that way; do not
skip it.

**Gate:** typecheck + vitest, and the e2e suite must not reference the deleted route.

## Task 10 — Fixtures and browser e2e.

`testdata/blocks/shell_stream_basic.json` and `shell_stream_alt_screen.json`, asserted by
**both** clients, same contract discipline as plans 5 and 6. A failing fixture is never
fixed by editing the fixture.

`frontend/e2e/shell-blocks.spec.ts` over the fake blocks socket
(`e2e/support/fake-blocks-mux.ts`, built in plan 6): a command produces a block with its
bytes and exit code; a failing command shows its code; entering alt screen swaps to Raw
and leaving restores blocks.

**Gate:** all five, plus `npm --prefix frontend run test:e2e`.

## Risks

- **The bootstrap is the whole feature and has no gate.** If zsh integration is subtly
  wrong, everything above it is dead weight. Task 5 lands before tasks 7-8 for that
  reason: prove marks reach `RecordShell` on a real shell before building rendering on
  top of them.
- **`pipe-pane` is a second reader of the pane.** It does not perturb the pane, but it
  does mean output is written to a FIFO for every session with a live terminal. Bound the
  reader and drop on backpressure rather than blocking the pane.
- **Marks reaching a client's emulator.** OSC 133 is unknown to xterm.js and renders
  nothing, so the in-band marks are harmless to clients today. Verify it rather than
  assuming; if an emulator ever echoes them, the fix is stripping in the client, not a
  private sequence.
- **Windows silently getting nothing.** The plan requires visible absence. A Windows
  session that shows an empty block list instead of "shell blocks are unavailable on
  Windows" is a defect, not a limitation.
- **Scope.** This is Go + two clients + three shell dialects, and it retires a shipped
  surface. It is larger than plan 6. If the bar has to move, cut task 10 first and task
  9 second; never cut task 5.

## Spec changes this plan requires

- Rewrite *Shell blocks* in the spec: the per-client attach finding, `pipe-pane` as the
  capture mechanism, and Windows exclusion. The current text specifies a mechanism that
  cannot work.
- Record the product decision that a session has exactly one terminal and that the
  terminal is the session surface, which supersedes the *Input* section's framing of
  Blocks and Raw as peer modes.
- Mark row 7 `written` in *Implementation plans*.
