# Shell Blocks — The Daemon's Half (spec §13.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a shell pane emit OSC 133 marks, so blocks, the Warp prompt and the
package's line editor actually appear in the running app.

**Architecture:** Spec §13 splits into two halves. §13.3, the renderer's half, landed
2026-08-30. §13.2, the daemon's half, was never started: nothing calls `spawnRecipe`,
nothing runs `tmux pipe-pane`, and nothing imports `packages/terminal/go/marks`. The
downstream consumer — `blockevent.Service`, its sqlite store, its HTTP controller and
`Manager.PublishBlockEvent` — is fully built. The pipe is welded at both ends with
nothing entering it. This plan builds the producer.

**Tech Stack:** Go (daemon, tmux adapter, a new `packages/terminal/go/bootstrap` module),
TypeScript (one manifest read), shared JSON vectors.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §4.1 (host boundary), §7.2 (mark tiers), §8 (additive-only bootstrap), §13.1 (relationship to plan 7), §13.2 (this plan), §13.3 (what already landed).

---

## Why this plan exists, and what it is worth

Verified on 2026-08-31 in this repository:

| §13.2 step | State | Evidence |
| --- | --- | --- |
| 1. Spawn the shell from a `SpawnRecipe` | **missing** | `grep -rn spawnRecipe backend/ frontend/src packages/desktop` → empty |
| 2. `tmux pipe-pane` into `go/marks` | **missing** | no `pipe-pane` in `backend/`; nothing imports `packages/terminal/go/marks` |
| 3. Record boundaries via `blockevent.Service` | present | `backend/internal/service/blockevent/service.go:36` |
| 4. Suspend capture across alt-screen | **missing** | — |
| 5. Publish on the `blocks` mux channel | present | `backend/internal/terminal/manager.go:558` |

**Task 2 is the visible win, and it is small.** §13.3 already decided that *live* blocks
come from the package's own parse of the stream the renderer is receiving anyway — not
from the daemon. So the moment a shell is spawned with the bootstrap, the renderer starts
seeing marks and blocks appear. Tasks 3–6 add persistence and history, which is what makes
blocks survive a reattach or a daemon restart. Do not reorder: if Task 2 does not produce
a visible block, nothing after it will.

## The reusability constraint (read before writing any code)

`packages/terminal` is a **product-independent package**. Spec §4.1 states it directly:
"Operator's daemon is one host; a plain PTY in another project is another." The user
reaffirmed this on 2026-08-31 when commissioning this plan.

Concretely, for every file you touch:

- Nothing Operator-shaped may enter `packages/terminal` — no tmux, no session id, no
  `blockevent`, no mux channel, no `~/.operator` path, no daemon concept.
- The new Go module under `packages/terminal/go/bootstrap` must be usable by a Go host
  that has never heard of Operator. It takes a shell name and a directory to
  materialize scripts into; it returns argv and env. That is all.
- Everything Operator-specific — tmux invocation, capture lifetime, `blockevent`
  recording, the `blocks` channel — lives in `backend/`.
- Review gate for every task: *could a second, non-Operator host use this unchanged?*

## Global Constraints

- **No comments in code.** The user's global rule, and it applies to test harnesses and
  scaffolding too.
- **All app state under `~/.operator`** (`OPERATOR_DATA_DIR`). Task 1 materializes shell
  scripts to disk; they go under the daemon's data dir, never an OS app-data location.
- **No file over 600 lines** (`packages/terminal` is checked by `check:boundaries`).
- The package must not import from `backend/` or `frontend/`.
- Every task ends green on: `cd backend && go test ./...`,
  `npm --prefix packages/terminal test`, `npm --prefix frontend test`,
  `npm --prefix packages/terminal run check:boundaries`.
- Do **not** expect `bench:gate` to be green. `input-latency` is red from the paint
  throttle in `ac9236563`; spec §9.5 carries that as an open decision. Note if a number
  moves; do not try to fix it here.

---

### Task 1: One recipe, readable from both languages

**Problem this solves.** `spawnRecipe` is TypeScript
(`packages/terminal/ts/core/src/spawn-recipe.ts:22`) and resolves the bootstrap script
path through `import.meta.url`. A Go daemon cannot call it. Reimplementing the argv rules
in Go would be two sources of truth for a contract §4.1 says the package alone owns, and
they would drift on the first shell added.

**Design.** The package publishes a language-neutral manifest. Both languages read it;
neither owns the rules. This mirrors the established `packages/terminal/protocol/vectors/`
pattern, which is already how `crates/marks`, `go/marks` and the TS decoder stay agreed
(`go/marks/marks_test.go:26` globs `../../protocol/vectors/*.json`).

**Files:**
- Create: `packages/terminal/protocol/recipes.json`
- Create: `packages/terminal/go/bootstrap/{go.mod,bootstrap.go,bootstrap_test.go}`
- Modify: `packages/terminal/ts/core/src/spawn-recipe.ts`
- Modify: `packages/terminal/ts/core/src/spawn-recipe.test.ts`

Manifest shape — argv is a template so neither language encodes quoting rules:

```json
{
  "version": 1,
  "shells": {
    "zsh":  { "script": "zsh.sh",     "argv": ["zsh", "-c", "source {{script}}; exec zsh"] },
    "bash": { "script": "bash.sh",    "argv": ["bash", "-c", "source {{script}}; exec bash"] },
    "fish": { "script": "fish.fish",  "argv": ["fish", "-C", "source {{script}}"] }
  },
  "env": {
    "auto":         { "OPERATOR_TERMINAL_INTEGRATION": "auto" },
    "osc133-only":  { "OPERATOR_TERMINAL_INTEGRATION": "osc133-only" },
    "off":          { "OPERATOR_TERMINAL_INTEGRATION": "off" }
  }
}
```

- [ ] **Step 1: Write the failing tests, both languages, against the same manifest**

TS: assert `spawnRecipe("zsh", {integration:"auto", suppressPrompt:false})` produces argv
whose third element contains the manifest's template with `{{script}}` replaced by an
absolute path ending `shell/zsh.sh`, and that the two `off`/`osc133-only` forms return a
bare `[shell]` argv. The existing six cases in `spawn-recipe.test.ts` already pin this
behaviour — they must keep passing unchanged. That is the point: the manifest is a
refactor, not a behaviour change.

Go: a table test over all three shells asserting `bootstrap.Recipe(shell, dir, opts)`
returns byte-identical argv to the TS side for the same inputs. Encode the expected argv
once, in the manifest's own test fixture, so neither language can drift silently.

- [ ] **Step 2: Sabotage check**

Change `"exec zsh"` to `"exec bash"` in the manifest. Both test suites must go red. If
only one does, the other is not really reading the manifest — fix it before continuing.

- [ ] **Step 3: `go:embed` the scripts, materialize under the host's directory**

The Go package embeds `zsh.sh`, `bash.sh`, `fish.fish` and `recipes.json`, and exposes:

```go
func Recipe(shell string, scriptDir string, opts Options) (argv []string, env map[string]string, err error)
```

`Recipe` writes the script into `scriptDir` (0700, content-addressed filename so a
concurrent daemon or a second host cannot half-write it) and returns argv pointing at it.
`scriptDir` is the caller's choice — that is what keeps this package host-agnostic. The
daemon will pass a path under `OPERATOR_DATA_DIR`; another host passes whatever it likes.

Note the embed path constraint: `go:embed` cannot reach outside its own module directory,
so `go/bootstrap/` needs the scripts copied in at build time or a `go:generate` step. Prefer
a checked-in copy plus a test that fails when it diverges from `shell/` — a generation step
would need a CI stage that does not exist (same reasoning as the committed `*.g.dart` in
`packages/mobile`).

- [ ] **Step 4: Verify** — `npm --prefix packages/terminal test`, `cd packages/terminal/go/bootstrap && go test ./...`

---

### Task 2: Spawn shell terminals with the bootstrap — the visible win

**Files:**
- Modify: `backend/internal/service/shellterm/service.go:226`
- Modify: `backend/internal/service/shellterm/loginshell.go`
- Modify: `backend/internal/service/shellterm/service_test.go`
- Modify: `backend/go.mod` (require the new module; it is a separate module, so a
  `replace` directive pointing at `../packages/terminal/go/bootstrap` — the same shape
  `go/marks` will need in Task 3)

Today `service.go:226` reads `argv := resolveUserLoginShell()` and passes
`ports.RuntimeConfig{Argv: argv}` with `Env` left unset. `RuntimeConfig.Env` already
exists (`backend/internal/ports/outbound.go:123`), is validated by the tmux adapter
(`tmux.go:300`) and is exported into the launch command by `buildLaunchCommand`.

- [ ] **Step 1: Write the failing test**

In `service_test.go`, open a shell terminal against a fake runtime and assert the captured
`RuntimeConfig`:
- `Argv[0]` is the resolved login shell,
- `Argv` carries the bootstrap source form for a known shell,
- `Env["OPERATOR_TERMINAL_INTEGRATION"] == "auto"`.

- [ ] **Step 2: Map the login shell to a `ShellKind`**

`resolveUserLoginShell` returns an absolute path (`/bin/zsh`, `/opt/homebrew/bin/fish`).
`bootstrap.Recipe` takes a kind. Add `shellKindFor(path string) (string, bool)` matching
on the **basename only**, and when it does not match one of the three, fall back to today's
bare argv with `integration: "osc133-only"` — §4.1 requires that tier to be a first-class
tested path, not a degraded one. A user on `nu` or `elvish` gets a working terminal with
Tier 1 marks, not a broken one.

- [ ] **Step 3: Wire it, with the script dir under `OPERATOR_DATA_DIR`**

The service needs the daemon's data dir. Inject it — do not read the env var inside the
service, which would make it untestable and would bypass `OPERATOR_DATA_DIR` overrides in
tests. `daemon.startShellTerminals` (`backend/internal/daemon/shellterm_wiring.go`) is the
construction site.

- [ ] **Step 4: Prove it by hand, not by test**

This is the accept criterion that Phase 4 lacked and paid for. Build, run the app, open a
shell terminal, run `ls`, and confirm you see a **block** with a header — not a bare grid.
Attach the screenshot to the task. If there is no visible block, stop: something between
here and §13.3 is broken and Tasks 3–7 will not fix it.

- [ ] **Step 5: Verify** — `cd backend && go test ./...`

---

### Task 3: Capture the pane with `tmux pipe-pane`, decode with `go/marks`

**Why pipe-pane and not `attachment.onData`.** §13.1 settles this and it is not reopened:
`newAttachment` is per-client (`backend/internal/terminal/manager.go:448`,
`backend/internal/terminal/doc.go:11`), so parsing at `onData` produces duplicate blocks
with two clients attached and **no** blocks with zero attached. Capture must be
server-side and independent of who is watching.

**Files:**
- Create: `backend/internal/terminal/capture.go`, `capture_test.go`
- Modify: `backend/internal/adapters/runtime/tmux/commands.go` (a `pipePaneArgs` builder,
  matching the existing `setStatusOffArgs` house style)
- Modify: `backend/internal/adapters/runtime/tmux/tmux.go` (a `StartCapture`/`StopCapture`
  pair on the runtime, behind a new optional port so conpty can decline)
- Modify: `backend/go.mod` (`replace` for `packages/terminal/go/marks`)

- [ ] **Step 1: Write the failing test**

Feed a recorded byte stream containing OSC 133 A/C/D and one OSC 7000 extension mark
through the capture reader with a fake `blockevent` recorder, and assert the recorder saw
one complete block with the right command text, cwd and exit code. Reuse a fixture from
`packages/terminal/protocol/vectors/` rather than hand-writing bytes.

- [ ] **Step 2: Decide the sink, and write it down in the file**

`tmux pipe-pane -o 'cat >> <path>'` writes to a file; the daemon tails it. A FIFO is the
obvious alternative and is worse: a FIFO blocks the pane's writer when nothing is reading,
so a daemon restart would **freeze the user's shell**. Use a file under the data dir, tail
it, and truncate on block boundaries. State this reasoning in the commit message — the next
person will otherwise "simplify" it to a FIFO.

- [ ] **Step 3: Bound it**

A capture file that only grows is a disk leak on a long-lived pane. Cap it, and drop the
oldest bytes rather than the newest — a truncated *old* block is a missing history entry, a
truncated *new* one is a corrupt live block.

- [ ] **Step 4: Verify** — `cd backend && go test ./...`

---

### Task 4: Suspend capture across alt-screen

**Files:**
- Modify: `backend/internal/terminal/capture.go`, `capture_test.go`

§13.2 step 4. An agent TUI repaints its whole screen many times a second; capturing that
into block storage is both meaningless and a disk-fill. The decoder must track
`?1049h`/`?1049l` and suspend recording between them.

**The trap, named.** Spec §11 records that in a tmux-hosted pane the agent is *already*
in the alternate screen because tmux put it there — so the enter you are looking for may
have happened before capture started. Handle "capture starts while already in alt-screen"
explicitly, and write a test for exactly that ordering. This is the same fact that made an
earlier version of this design wrong.

- [ ] **Step 1: Write the failing test** — both orderings: enter-then-capture, and
  capture-then-enter.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify** — `cd backend && go test ./...`

---

### Task 5: A second entry point on `blockevent` — not an `ActivitySignal` overload

**Files:**
- Modify: `backend/internal/domain/blockevent.go`
- Modify: `backend/internal/service/blockevent/{types.go,service.go}`
- Modify: `backend/internal/service/blockevent/service_test.go`

§13.1 is explicit and this is the task where it is easy to get wrong:
`Service.Record` takes `ports.ActivitySignal`
(`backend/internal/service/blockevent/service.go:46`), which is hook-shaped.
`backend/internal/ports/runtime_observations.go` is built around tool-use hooks, and
stuffing a shell command counter into a `ToolUseID` "is a lie that costs a week."

- [ ] **Step 1: Write the failing test** for a new
  `RecordShellBlock(ctx, sessionID, ShellBlock)` method.
- [ ] **Step 2: Add the kinds.** `BlockEventKind` (`domain/blockevent.go:13-22`) is a closed
  vocabulary and `ParseBlockEventKind` gates it. Add `shell_command_start` and
  `shell_command_end`, and extend the parse test — an unlisted kind silently becomes
  `unknown` and the block disappears with no error.
- [ ] **Step 3: `SourceID` is the mark's block id**, never invented here. `types.go:14-17`
  already documents this exact future: "a shell mark's counter later." Deduplication on
  reconnect depends on it.
- [ ] **Step 4: Redaction still applies.** A shell command line can contain a token. Route
  it through `redact` like every other path, and test one.
- [ ] **Step 5: Verify** — `cd backend && go test ./...`

---

### Task 6: History converges with the live parse on the same `BlockId`

**Files:**
- Modify: `backend/internal/httpd/controllers/sessions.go` (history for shell blocks)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`
- Modify: the matching frontend test

§13.3: live blocks come from the package's own parse; history comes from the REST
endpoint. **Both must produce the same `BlockId`** — that is why block id continuity is a
Tier-2 field (§7.2). If they disagree, a reattach shows every block twice, which is the
same class of bug the vt-core resize duplication was.

- [ ] **Step 1: Write the failing test** — feed history for blocks 1–3, then live marks for
  blocks 3–4, and assert four blocks, not five, with block 3 appearing once.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify by hand** — open a shell pane, run three commands, reload the app,
  confirm the three blocks come back once each.

---

### Task 7: Windows says so, out loud

**Files:**
- Modify: `backend/internal/service/shellterm/service.go`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`

§13.1: "Windows gets no shell blocks and says so." conpty has no `pipe-pane` equivalent
in this design. `TerminalStrings.shellBlocksUnavailable`
(`packages/terminal/ts/core/src/types.ts`) already exists for this message — use it rather
than inventing copy.

- [ ] **Step 1:** On Windows, spawn with `integration: "osc133-only"` and surface the
  string. A silently plain terminal reads as a bug; a stated limitation does not.
- [ ] **Step 2: Verify** — `cd backend && go test ./...`, `npm --prefix frontend test`

---

### Task 8: Record it, and settle plan 7

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` §13.2
- Modify: `docs/superpowers/plans/2026-08-28-shell-blocks.md`

- [ ] **Step 1:** Mark §13.2 landed, with the same "what landed and the rules it settled"
  shape §13.3 already uses. Record the three decisions this plan made that the spec did not
  anticipate: the shared recipe manifest, the file-not-FIFO capture sink, and the
  osc133-only fallback for unrecognized shells.
- [ ] **Step 2:** Execute §13.1's outstanding action — rewrite
  `2026-08-28-shell-blocks.md` as the backend-only plan it should have been, rather than
  leaving a plan on disk whose frontend half is superseded.
- [ ] **Step 3:** Add a line to §15 (Common wrong turns): *a package that ships with no
  caller is not shipped.* Three subsystems have now failed this way — `spawnRecipe`,
  `createCompletionProvider`, `listDirectory`.

---

## Accept when

**Behavioural, deliberately — this is the criterion Phase 4's plan lacked:**

1. A human opens a shell terminal in the running app, types `ls`, and sees a block with a
   header, a command line and an exit status.
2. The pane still works on a shell with no bootstrap (`nu`, `elvish`) — plain, Tier 1, no
   crash, no empty block list.
3. Two clients attached to the same pane see each block **once**.
4. Zero clients attached, then one attaches: the blocks that ran while nobody watched are
   in history.
5. An agent pane records nothing to block storage and its capture file does not grow.
6. `cd backend && go test ./...`, `npm --prefix packages/terminal test`,
   `npm --prefix frontend test` and `check:boundaries` are green.
7. `packages/terminal` contains no new reference to tmux, sessions, `blockevent`, or
   `~/.operator`.
