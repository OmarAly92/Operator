# Warp Terminal Phase 2 Implementation Plan — the input editor and prompt ownership

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shell's readline with our own DOM editor and draw the prompt row ourselves, so the command text in a block is exact rather than scraped and the pane finally feels like Warp.

**Architecture:** The shell states line-editor ownership explicitly through two new Tier-2 marks; `vt-core` turns those into a three-state machine that the editor reads. The editor is a new `ts/editor` package that talks only to `ts/core`, shares the renderer's cell metrics and theme so the input row is visually continuous with the blocks above it, and is read-only whenever a program owns the tty. Prompt suppression and the editor land in the same change, because either one alone is a broken terminal.

**Tech Stack:** TypeScript 5 / React 19 / Vitest / Playwright, Rust 1.96.0 (`vt-core`, `vt-wasm`, `marks`), Go 1.25.7, zsh / bash / fish.

**Spec:** `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`

**Companion plans:** `docs/superpowers/plans/2026-08-29-warp-terminal-phase-1a.md`, `docs/superpowers/plans/2026-08-29-warp-terminal-phase-1b.md`

---

## Global Constraints

Copied verbatim from the spec and from what Phases 0, 1a and 1b landed. Every task's requirements implicitly include this section.

- **No source file over 600 lines.** `npm --prefix packages/terminal run check:boundaries` enforces it.
- **No import may escape `packages/terminal/`.** The package MUST NOT import from `frontend/`, `backend/`, or `packages/shared/`. `frontend/` imports the package **by package name only** — `@operator/terminal-react` — never by relative path.
- **`editor` MUST NOT import `completions`; `renderer-dom` MUST NOT import `editor`.** `scripts/check-boundaries.mjs` already encodes both rules and already maps `@operator/terminal-editor` → `ts/editor`. Do not weaken it.
- **No timer anywhere decides line-editor ownership.** This is the phase's headline acceptance criterion (spec §3.5, §10.2). A `setTimeout`, a `Duration`, a debounce or a "settle" delay in the ownership path is a plan violation, not a style preference.
- **Tier 2 is strictly additive.** Every Tier-2 mark is ignorable. There MUST NOT be a code path where a Tier-2 mark is required to close a block (spec §7.2).
- **The editor MUST NOT synthesize readline editing sequences.** On submit it sends command text plus a newline through the transport and nothing else (spec §10.3).
- **The package MUST NOT read the user's `.zsh_history`** or any other shell history file. History is sourced from marks and persisted through the host's optional `HistoryStore` (spec §10.4).
- **The bootstrap is additive-only.** No removing, reordering or stashing the user's hooks; no adding or removing any `bindkey` / `bind` binding; no third-party prompt framework referenced by name; no command executed in the user's session for our own purposes; no inspection of ssh argv (spec §8).
- **fish MUST work without disabling its OSC 133.** Launching fish with `-f no-mark-prompt`, or any equivalent, is the exact Warp mistake this package exists to avoid (spec §3.2).
- **`BLOCK_RECORD_WORDS` is 14** and word 4 packs `state | source << 8 | has_exit << 16`; word 5 is the raw two's-complement `i32`. Do not change the block record layout in this phase.
- **`XtermTerminal.tsx` stays.** It is the alt-screen surface. In alt screen the editor is hidden and xterm owns input.
- **Every new user-facing string that reaches Operator goes into all eight locale files** under `frontend/src/renderer/i18n/` — `en, zh-CN, ja, ko, es, fr, de, pt-BR` — non-empty and key-matched. Strings inside the package arrive through `TerminalStrings`; no `react-i18next` inside the package.
- **Windows gets no shell blocks and no editor.** A Windows session opens the raw grid and says shell blocks are unavailable.

---

## File Structure

**New package — `packages/terminal/ts/editor/`**

| File | Responsibility |
| --- | --- |
| `package.json`, `tsconfig.json`, `vitest.config.ts` | package identity, `@operator/terminal-editor` |
| `src/index.ts` | public exports only |
| `src/buffer.ts` | `EditorBuffer` — pure text/cursor model, no DOM |
| `src/keymap.ts` | pure key event → `EditorCommand` mapping |
| `src/highlight.ts` | pure command-line tokenizer |
| `src/history.ts` | `HistoryModel` — dedup, prefix search, ghost suggestion |
| `src/reverse-search.ts` | Ctrl-R search state machine, pure |
| `src/line-editor.ts` | the DOM view; owns the element, reads `LineEditorState` |
| `src/prompt-row.ts` | the Warp prompt row DOM |
| `src/styles.css`, `src/styles.ts` | package styles, generated the same way `renderer-dom` does it |

**Modified**

| File | Change |
| --- | --- |
| `packages/terminal/protocol/SPEC.md` | `input-ready` / `input-released` move from reserved to live |
| `packages/terminal/protocol/vectors/*.json` | new conformance vectors |
| `packages/terminal/crates/marks/src/event.rs` | two new `MarkEvent` variants |
| `packages/terminal/go/marks/marks.go` | the same two events |
| `packages/terminal/crates/vt-core/src/line_editor.rs` | **new** — the three-state machine |
| `packages/terminal/crates/vt-core/src/lib.rs` | drive the machine from mark events |
| `packages/terminal/crates/vt-core/src/grid.rs` | one snapshot word for the state |
| `packages/terminal/ts/core/src/terminal-core.ts` | `lineEditorState()` accessor |
| `packages/terminal/ts/core/src/spawn-recipe.ts` | remove the `suppressPrompt` guard; add bash + fish |
| `packages/terminal/shell/zsh.sh` | line-editor marks + optional prompt suppression |
| `packages/terminal/shell/bash.sh` | **new** |
| `packages/terminal/shell/fish.fish` | **new** |
| `packages/terminal/ts/react/src/TerminalSurface.tsx` | mount the editor below the block list |
| `frontend/src/renderer/components/BlockTerminal.tsx` | route keystrokes; rerun prefill |

---

## Task 1: Freeze the input contract

Phase 1a's Task 1 froze the block record and unblocked everything downstream. This is the same move for the line-editor signal: both decoders and the protocol document change together, in one commit, before any consumer exists.

**Files:**
- Modify: `packages/terminal/protocol/SPEC.md` (§4.4 and §8)
- Create: `packages/terminal/protocol/vectors/input-ready.json`
- Create: `packages/terminal/protocol/vectors/input-released.json`
- Create: `packages/terminal/protocol/vectors/input-marks-interleaved.json`
- Modify: `packages/terminal/crates/marks/src/event.rs`
- Modify: `packages/terminal/crates/marks/src/scanner.rs`
- Modify: `packages/terminal/go/marks/marks.go`
- Test: `packages/terminal/crates/marks/tests/vectors.rs` (existing runner picks up new vectors)
- Test: `packages/terminal/go/marks/marks_test.go` (same)

**Interfaces:**
- Consumes: `MarkEvent`, `MarkTier`, `ExtensionFields` from Phase 1a.
- Produces: `MarkEvent::InputReady` and `MarkEvent::InputReleased` (Rust); `EventInputReady` / `EventInputReleased` (Go). Task 2 consumes these.

- [ ] **Step 1: Write the failing Rust vector test fixture**

Create `packages/terminal/protocol/vectors/input-ready.json`:

```json
{
  "name": "input-ready",
  "description": "A Tier-2 mark carrying input-ready produces an InputReady event and nothing else.",
  "input": "]7000;v=1;input-ready=1",
  "events": [
    { "kind": "input_ready" }
  ]
}
```

Create `packages/terminal/protocol/vectors/input-released.json`:

```json
{
  "name": "input-released",
  "description": "A Tier-2 mark carrying input-released produces an InputReleased event.",
  "input": "]7000;v=1;input-released=1",
  "events": [
    { "kind": "input_released" }
  ]
}
```

Create `packages/terminal/protocol/vectors/input-marks-interleaved.json`. This is the one that matters: the mark must survive being adjacent to a block lifecycle and must not disturb it.

```json
{
  "name": "input-marks-interleaved",
  "description": "Line-editor marks interleave with the block lifecycle without opening, closing or altering a block.",
  "input": "]7000;v=1;input-ready=1]133;A]7000;v=1;cmd=ls]7000;v=1;input-released=1]133;Cout\n]133;D;0]7000;v=1;input-ready=1",
  "events": [
    { "kind": "input_ready" },
    { "kind": "prompt_start", "tier": "osc133" },
    { "kind": "extension", "pairs": [["v", "1"], ["cmd", "ls"]] },
    { "kind": "input_released" },
    { "kind": "output_start", "tier": "osc133" },
    { "kind": "command_end", "tier": "osc133", "exit_code": 0 },
    { "kind": "input_ready" }
  ]
}
```

- [ ] **Step 2: Run both vector runners to verify they fail**

```bash
cd packages/terminal && cargo test -p marks --test vectors
```

Expected: FAIL — unknown event kind `input_ready`.

```bash
cd packages/terminal/go/marks && go test ./...
```

Expected: FAIL — the same, from the Go runner.

- [ ] **Step 3: Add the two Rust variants**

In `packages/terminal/crates/marks/src/event.rs`, extend the enum. These carry no tier: they are Tier-2 only by construction, and a tier field would imply an OSC 133 spelling that does not exist.

```rust
pub enum MarkEvent {
    PromptStart { tier: MarkTier },
    CommandStart { tier: MarkTier },
    OutputStart { tier: MarkTier },
    CommandEnd { tier: MarkTier, exit_code: Option<i32> },
    CwdChanged { path: String },
    Extension(ExtensionFields),
    InputReady,
    InputReleased,
    AltScreenEnter,
    AltScreenLeave,
}
```

- [ ] **Step 4: Emit them from the scanner**

In `packages/terminal/crates/marks/src/scanner.rs`, where an `OSC 7000` payload is turned into `MarkEvent::Extension`, split the two reserved keys out **before** building the extension event, and keep every other key on the extension event.

```rust
fn extension_events(fields: ExtensionFields) -> Vec<MarkEvent> {
    let mut out = Vec::new();
    let mut remaining = ExtensionFields::default();
    let mut ready = false;
    let mut released = false;
    for (key, value) in fields.pairs {
        match key.as_str() {
            "input-ready" => ready = true,
            "input-released" => released = true,
            _ => remaining.pairs.push((key, value)),
        }
    }
    if !remaining.pairs.is_empty() {
        out.push(MarkEvent::Extension(remaining));
    }
    // Released wins when a malformed mark carries both: the safe state is
    // "a program owns the tty", never "we may type into it".
    if released {
        out.push(MarkEvent::InputReleased);
    } else if ready {
        out.push(MarkEvent::InputReady);
    }
    out
}
```

Wire it where the scanner currently pushes a single `MarkEvent::Extension`, pushing each returned event with the same byte offset.

- [ ] **Step 5: Run the Rust vectors**

```bash
cd packages/terminal && cargo test -p marks
```

Expected: PASS, including the three new vectors.

- [ ] **Step 6: Mirror it in Go**

In `packages/terminal/go/marks/marks.go`, add the two event kinds and the same split, with the same released-wins precedence:

```go
const (
	EventInputReady    = "input_ready"
	EventInputReleased = "input_released"
)

func extensionEvents(pairs [][2]string) []Event {
	var out []Event
	remaining := make([][2]string, 0, len(pairs))
	ready, released := false, false
	for _, kv := range pairs {
		switch kv[0] {
		case "input-ready":
			ready = true
		case "input-released":
			released = true
		default:
			remaining = append(remaining, kv)
		}
	}
	if len(remaining) > 0 {
		out = append(out, Event{Kind: EventExtension, Pairs: remaining})
	}
	if released {
		out = append(out, Event{Kind: EventInputReleased})
	} else if ready {
		out = append(out, Event{Kind: EventInputReady})
	}
	return out
}
```

- [ ] **Step 7: Run the Go vectors**

```bash
cd packages/terminal/go/marks && go test ./...
```

Expected: PASS.

- [ ] **Step 8: Update the protocol document**

In `packages/terminal/protocol/SPEC.md`, replace §4.4 "Reserved keys — MUST NOT be emitted by Phase 1a" with a live section:

```markdown
### 4.4 Line-editor ownership keys

| Key | Meaning | Value |
| --- | --- | --- |
| `input-ready` | the shell's line editor is idle and accepting input | `1` |
| `input-released` | a program has taken over the tty | `1` |

These are the explicit signal that replaces Warp's 50ms activation timer
(spec §3.5, §10.2). A decoder MUST surface them as the `input_ready` and
`input_released` events in §8. A mark carrying both MUST be surfaced as
`input_released` only: the safe state is "a program owns the tty".

They remain strictly additive. A decoder that ignores them still produces
correct blocks, and no block lifecycle transition depends on either key.
```

In §8, remove the paragraph beginning "`input-ready` and `input-released` are NOT events in this list" and add both to the event list.

- [ ] **Step 9: Run every decoder gate and commit**

```bash
cd packages/terminal && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
cd packages/terminal/go/marks && go test ./...
```

```bash
git add packages/terminal/protocol packages/terminal/crates/marks packages/terminal/go/marks
git commit -m "feat(terminal): make the line-editor marks a decoded event in both decoders"
```

---

## Task 2: `LineEditorState` in the core

**Files:**
- Create: `packages/terminal/crates/vt-core/src/line_editor.rs`
- Create: `packages/terminal/crates/vt-core/tests/line_editor_state.rs`
- Modify: `packages/terminal/crates/vt-core/src/lib.rs`
- Modify: `packages/terminal/crates/vt-core/src/grid.rs`
- Modify: `packages/terminal/crates/vt-wasm/src/lib.rs`
- Modify: `packages/terminal/ts/core/src/terminal-core.ts`
- Modify: `packages/terminal/ts/core/src/types.ts`
- Test: `packages/terminal/ts/core/src/terminal-core.test.ts`

**Interfaces:**
- Consumes: `MarkEvent::InputReady`, `MarkEvent::InputReleased` from Task 1.
- Produces: `LineEditorState` (Rust enum, 0 = `Unknown`, 1 = `Owned`, 2 = `Released`), surfaced as `TerminalSnapshot.lineEditorState: number` and `core.lineEditorState(): LineEditorState` where `LineEditorState = "unknown" | "owned" | "released"`. Tasks 6, 9, 10 and 11 consume this.

- [ ] **Step 1: Write the failing Rust test**

Create `packages/terminal/crates/vt-core/tests/line_editor_state.rs`:

```rust
use vt_core::{LineEditorState, TerminalCore};

fn core() -> TerminalCore {
    TerminalCore::new(80, 100)
}

#[test]
fn starts_unknown_because_no_shell_has_spoken_yet() {
    assert_eq!(core().line_editor_state(), LineEditorState::Unknown);
}

#[test]
fn input_ready_takes_ownership_and_input_released_gives_it_back() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
    c.feed(b"\x1b]7000;v=1;input-released=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn entering_the_alt_screen_releases_ownership_even_while_owned() {
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
}

#[test]
fn leaving_the_alt_screen_does_not_invent_ownership() {
    // The shell says when it is ready. Guessing here is the 50ms timer
    // (spec 3.5) wearing a different hat.
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b[?1049l");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn a_forged_input_ready_inside_the_alt_screen_is_ignored() {
    // A full-screen program can print bytes that look like our mark. Acting
    // on one hands the editor a writable line into a running program.
    let mut c = core();
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    c.feed(b"\x1b[?1049h");
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b[?1049l");
    assert_eq!(c.line_editor_state(), LineEditorState::Released);
    c.feed(b"\x1b]7000;v=1;input-ready=1\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Owned);
}

#[test]
fn a_tier_one_only_session_stays_unknown_forever() {
    let mut c = core();
    c.feed(b"\x1b]133;A\x07ls\x1b]133;C\x07out\n\x1b]133;D;0\x07");
    assert_eq!(c.line_editor_state(), LineEditorState::Unknown);
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && cargo test -p vt-core --test line_editor_state
```

Expected: FAIL — `LineEditorState` not found.

- [ ] **Step 3: Write the state machine**

Create `packages/terminal/crates/vt-core/src/line_editor.rs`:

```rust
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum LineEditorState {
    #[default]
    Unknown,
    Owned,
    Released,
}

impl LineEditorState {
    pub fn wire(self) -> u32 {
        match self {
            LineEditorState::Unknown => 0,
            LineEditorState::Owned => 1,
            LineEditorState::Released => 2,
        }
    }
}

#[derive(Default)]
pub struct LineEditorTracker {
    state: LineEditorState,
}

impl LineEditorTracker {
    pub fn state(&self) -> LineEditorState {
        self.state
    }

    pub fn on_input_ready(&mut self) {
        self.state = LineEditorState::Owned;
    }

    pub fn on_input_released(&mut self) {
        self.state = LineEditorState::Released;
    }

    pub fn on_alt_screen_enter(&mut self) {
        self.state = LineEditorState::Released;
    }
}
```

There is deliberately no `on_alt_screen_leave`. Leaving the alt screen tells us a program stopped drawing; it does not tell us the shell's line editor is idle. Only `input-ready` says that.

- [ ] **Step 4: Drive it from the event loop**

In `packages/terminal/crates/vt-core/src/lib.rs`, add `mod line_editor;` and `pub use line_editor::LineEditorState;`, hold a `LineEditorTracker` on `TerminalCore`, and extend the feed loop.

**Placement is the whole point of this step.** The dispatch goes **after** the alt-screen suppression `continue`, not before it:

```rust
if self.alt_screen.is_active() && !matches!(event, MarkEvent::AltScreenLeave) {
    continue;
}
match event {
    MarkEvent::InputReady => self.line_editor.on_input_ready(),
    MarkEvent::InputReleased => self.line_editor.on_input_released(),
    MarkEvent::AltScreenEnter => self.line_editor.on_alt_screen_enter(),
    _ => {}
}
apply_event(&mut self.parser, &mut self.alt_screen, event);
```

Phase 1 already drops mark events while the alternate screen is active, and the reason is written into `alt_screen.rs`: *a TUI can draw something that looks like a mark sequence without it being one.* That reasoning applies with more force to ownership than to blocks. A forged `input-ready` from a full-screen program does not corrupt a block — it hands the editor a writable line and lets it submit into a running program, which is the one thing §10.2 says must never happen.

Trace the four cases to see the ordering is right:

| Event | Alt screen at that moment | Result |
| --- | --- | --- |
| `AltScreenEnter` | inactive | passes the guard → `Released`, then `apply_event` activates the alt screen |
| `InputReady` | active | guard fires → **ignored**, stays `Released` |
| `AltScreenLeave` | active | guard allows it → falls to `_` → `apply_event` deactivates; ownership deliberately unchanged |
| `InputReady` | inactive | → `Owned` |

Add the accessor:

```rust
pub fn line_editor_state(&self) -> LineEditorState {
    self.line_editor.state()
}
```

- [ ] **Step 5: Run the Rust test**

```bash
cd packages/terminal && cargo test -p vt-core --test line_editor_state
```

Expected: PASS, all five.

- [ ] **Step 6: Put the state on the snapshot**

In `packages/terminal/crates/vt-core/src/grid.rs`, `build_snapshot` gains a `line_editor_state: u32` field on `GridSnapshot`, set from `LineEditorState::wire()`. In `crates/vt-wasm/src/lib.rs` expose it as a getter on the snapshot object.

In `packages/terminal/ts/core/src/types.ts`:

```ts
export type LineEditorState = "unknown" | "owned" | "released";

export type TerminalSnapshot = Readonly<{
	generation: number;
	content: Uint8Array;
	rows: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
	blocks: Uint32Array;
	blockText: Uint8Array;
	lineEditorState: number;
}>;
```

In `packages/terminal/ts/core/src/terminal-core.ts`:

```ts
const LINE_EDITOR_STATES: readonly LineEditorState[] = ["unknown", "owned", "released"];

lineEditorState(): LineEditorState {
	return LINE_EDITOR_STATES[this.snapshot().lineEditorState] ?? "unknown";
}
```

- [ ] **Step 7: Write and run the TypeScript test**

Add to `packages/terminal/ts/core/src/terminal-core.test.ts`:

```ts
it("reports line-editor ownership exactly as the shell states it", () => {
	const core = createTerminalCore({ columns: 80, scrollback: 100 });
	expect(core.lineEditorState()).toBe("unknown");
	core.feed(new TextEncoder().encode("\x1b]7000;v=1;input-ready=1\x07"));
	expect(core.lineEditorState()).toBe("owned");
	core.feed(new TextEncoder().encode("\x1b]7000;v=1;input-released=1\x07"));
	expect(core.lineEditorState()).toBe("released");
	core.dispose();
});
```

```bash
cd packages/terminal && npm run build:wasm && npm run test -w @operator/terminal-core
```

Expected: PASS.

- [ ] **Step 8: Prove no timer decides ownership, and commit**

This is a spec acceptance criterion, so it gets a real check rather than a promise. Add `packages/terminal/scripts/check-no-ownership-timer.mjs`.

**Do not hardcode the full file list.** `ts/editor/` does not exist until Task 5, and a list that has to be extended by hand in a later task is a list that goes stale — which is the exact defect that stopped the first run of this plan. The scanned set is derived instead:

- **Core set, always scanned, must all exist:** `crates/vt-core/src/line_editor.rs`, `crates/vt-core/src/lib.rs`. If any core file is missing, **fail** — a checker that silently scans nothing and prints success is worse than no checker.
- **Derived set:** every file under `ts/editor/src/` whose text matches `/\blineEditorState\b|\bLineEditorState\b/`. Before Task 5 this directory does not exist and the derived set is empty, which is correct and not an error. From Task 6 onward `line-editor.ts` reads ownership, so it joins the set with no plan step required.

Scoping to files that actually reference ownership is deliberate: a cursor-blink `setInterval` or a ghost-text debounce elsewhere in the editor is legitimate, and flagging those would train everyone to ignore the checker.

Forbidden patterns in the scanned set: `setTimeout`, `setInterval`, `requestIdleCallback`, `requestAnimationFrame`, `Duration::from_millis`, `Duration::from_secs`, `thread::sleep`, `tokio::time`. Report the offending file, line number and matched text.

The script MUST print the number of files it scanned, so a run that covered nothing is visible rather than green. Add it to the `check:boundaries` npm script chain.

```bash
cd packages/terminal && node ./scripts/check-no-ownership-timer.mjs
```

Expected: `no ownership timers found (2 files scanned)` — the two core Rust files. The count is the assertion; a run reporting 0 files is a failure even though it found no timers.

```bash
git add packages/terminal/crates packages/terminal/ts/core packages/terminal/scripts
git commit -m "feat(terminal): track line-editor ownership from marks, never from a timer"
```

---

## Task 3: `zsh.sh` states ownership

**Files:**
- Modify: `packages/terminal/shell/zsh.sh`
- Test: `packages/terminal/shell/zsh.test.mjs`

**Interfaces:**
- Consumes: the mark encoding from Task 1.
- Produces: a zsh session emitting `input-ready` when the line editor starts and `input-released` before a command runs. Task 10 adds suppression to the same file.

- [ ] **Step 1: Add a PTY harness, because the existing one cannot see this**

`zsh.test.mjs` spawns `zsh -f -c`, which is **non-interactive**. zle never initializes there, so `zle -N` and `add-zle-hook-widget` silently do nothing and `line-init` never fires. A test written against that harness passes whether or not the hook is registered — deleting the entire `add-zle-hook-widget` block leaves every assertion green. That is not a hypothetical: it is what the first implementation of this task shipped.

`preexec` is fine non-interactively (a test can iterate `$preexec_functions`). **`line-init` is not.** It needs a real PTY.

Add `packages/terminal/shell/pty.mjs`, used by this task and Task 4. tmux is the PTY source — it is already a dependency of the daemon, and `pipe-pane` captures raw bytes including OSC sequences, which `capture-pane` would strip:

```js
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export function haveTmux() {
	try {
		execFileSync("tmux", ["-V"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
}

/**
 * Run `command` in a real interactive PTY, send each line of `keys`, and
 * return every raw byte the pane produced.
 */
export function runInPty(command, keys, { settleMs = 1000 } = {}) {
	const dir = mkdtempSync(join(tmpdir(), "opr-pty-"));
	const raw = join(dir, "pane.raw");
	const session = `opr_pty_${process.pid}_${Math.random().toString(36).slice(2, 8)}`;
	const tmux = (...args) => execFileSync("tmux", args, { encoding: "latin1" });
	try {
		tmux("new-session", "-d", "-s", session, "-x", "120", "-y", "40", command);
		tmux("pipe-pane", "-t", session, "-o", `cat >> ${raw}`);
		sleep(settleMs);
		for (const line of keys) {
			tmux("send-keys", "-t", session, line, "Enter");
			sleep(settleMs);
		}
		return readFileSync(raw, "latin1");
	} finally {
		try { tmux("kill-session", "-t", session); } catch {}
		rmSync(dir, { recursive: true, force: true });
	}
}

function sleep(ms) {
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
```

Skip the PTY tests with a clear reason when `haveTmux()` is false, the same way the file already skips when zsh is absent. A skipped test says so; a vacuous one does not.

- [ ] **Step 2: Write the failing shell test**

Add to `packages/terminal/shell/zsh.test.mjs`. The `line-init` assertion MUST go through `runInPty`; only the `preexec` and `bindkey` assertions may use the existing non-interactive harness.

```js
test("fires input-ready from the real zle line-init hook", { skip: ptySkip }, () => {
	const out = runInPty("zsh -f -i", [`source ${bootstrap}`, "echo hi"]);
	// Verified on macOS zsh 5.9: 2 and 1 with the hook registered, 0 and 1
	// without it. The released count is what proves the pane really ran a
	// command, so a ready count of 0 cannot be blamed on a dead harness.
	assert.ok(count(out, "input-ready=1") >= 1, "zle line-init never fired");
	assert.ok(count(out, "input-released=1") >= 1, "preexec never fired");
	assert.ok(
		out.indexOf("input-ready=1") < out.indexOf("input-released=1"),
		"ready must precede released for the first command",
	);
});

test("does not add or remove any bindkey binding", async () => {
	const before = await runZshCapture("bindkey -L | sort");
	const after = await runZshWithBootstrap("bindkey -L | sort");
	assert.equal(after, before);
});

test("leaves the user's own zle-line-init widget installed and callable", async () => {
	const out = await runZshWithUserWidget();
	assert.match(out, /user-widget-ran/);
});
```

- [ ] **Step 3: Run it to verify it fails**

```bash
cd packages/terminal && node --test shell/zsh.test.mjs
```

Expected: FAIL — `zle line-init never fired`.

**Then prove the test can fail for the right reason.** After Step 4 makes it pass, delete the `add-zle-hook-widget` block, re-run, and confirm this specific test fails while the others still pass. Restore it. A test for a hook registration that passes with the registration deleted is worth less than no test, because it certifies the opposite of what it claims.

- [ ] **Step 4: Add the additive zle hooks**

In `packages/terminal/shell/zsh.sh`, inside the existing guard function. `add-zle-hook-widget` is the additive API; assigning `zle-line-init` directly would clobber a user widget and violate spec §8.

```sh
	__operator_terminal_input_ready() {
		emulate -L zsh
		print -nr -- $'\e]7000;v=1;input-ready=1\a'
	}

	__operator_terminal_input_released() {
		emulate -L zsh
		print -nr -- $'\e]7000;v=1;input-released=1\a'
	}

	if autoload -Uz add-zle-hook-widget 2>/dev/null; then
		zle -N __operator_terminal_input_ready
		add-zle-hook-widget line-init __operator_terminal_input_ready
	fi

	add-zsh-hook preexec __operator_terminal_input_released
```

`add-zle-hook-widget` is absent on very old zsh. The `if` is the Tier-1 degrade path required by spec §8: no hook, no line-editor marks, blocks still work, and the editor stays read-only in `Unknown`.

- [ ] **Step 5: Run the shell tests**

```bash
cd packages/terminal && node --test shell/zsh.test.mjs
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal/shell/zsh.sh packages/terminal/shell/zsh.test.mjs
git commit -m "feat(terminal): emit line-editor ownership marks from the zsh bootstrap"
```

---

## Task 4: `bash.sh` and `fish.fish`

**Files:**
- Create: `packages/terminal/shell/bash.sh`
- Create: `packages/terminal/shell/bash.test.mjs`
- Create: `packages/terminal/shell/fish.fish`
- Create: `packages/terminal/shell/fish.test.mjs`
- Modify: `packages/terminal/ts/core/src/spawn-recipe.ts`
- Modify: `packages/terminal/ts/core/src/types.ts`

**Interfaces:**
- Consumes: the mark encoding from Task 1.
- Produces: `ShellKind = "zsh" | "bash" | "fish"`; `spawnRecipe(shell, options)` accepts all three.

- [ ] **Step 1: Write the failing fish regression test**

This is the spec §3.2 test and it is the reason fish is in this phase at all. Warp's answer to fish was to launch it with `-f no-mark-prompt`, turning standard OSC 133 off. Ours must work with it on.

Create `packages/terminal/shell/fish.test.mjs`. fish's `--on-event fish_prompt` has the same problem zsh's `line-init` does — it only fires in an interactive shell — so the prompt and ownership assertions go through `runInPty` from `shell/pty.mjs` (Task 3 Step 1). `fish_preexec` and `fish_postexec` can be emitted by calling the functions directly, but a test that only does that proves the function body, not the wiring.

```js
test("produces correct blocks with fish's own OSC 133 left enabled", async () => {
	const out = await runFish(["echo one", "echo two"]);
	// fish emits A without a matching B. The recovery table (spec 7.4)
	// closes the first block on the second A; nothing here may disable
	// fish's own marks to avoid that.
	const events = decodeWithGoMarks(out);
	const blocks = blocksFrom(events);
	assert.equal(blocks.length, 2);
	assert.equal(blocks[0].command, "echo one");
	assert.equal(blocks[1].command, "echo two");
});

test("never launches fish with a mark-disabling flag", async () => {
	const recipe = spawnRecipe("fish", { integration: "auto", suppressPrompt: false });
	assert.ok(!recipe.argv.includes("no-mark-prompt"));
	assert.ok(!recipe.argv.some((arg) => /no-mark/.test(arg)));
});

test("emits line-editor ownership marks", async () => {
	const out = await runFish(["echo hi"]);
	assert.match(out, /input-ready=1/);
	assert.match(out, /input-released=1/);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && node --test shell/fish.test.mjs
```

Expected: FAIL — `shell/fish.fish` does not exist.

- [ ] **Step 3: Write `fish.fish`**

```fish
if set -q __OPERATOR_TERMINAL_LOADED
    exit 0
end
set -g __OPERATOR_TERMINAL_LOADED 1

function __operator_terminal_pct_encode
    printf '%s' $argv[1] | string escape --style=url
end

function __operator_terminal_prompt --on-event fish_prompt
    set -l cwd (__operator_terminal_pct_encode $PWD)
    set -l branch (__operator_terminal_pct_encode (git branch --show-current 2>/dev/null; or echo ""))
    printf '\e]7000;v=1;cwd=%s;branch=%s\a' $cwd $branch
    printf '\e]7000;v=1;input-ready=1\a'
end

function __operator_terminal_preexec --on-event fish_preexec
    set -l cmd (__operator_terminal_pct_encode $argv[1])
    printf '\e]7000;v=1;cmd=%s;start_ms=%s\a' $cmd (math (date +%s) x 1000)
    printf '\e]7000;v=1;input-released=1\a'
end

function __operator_terminal_postexec --on-event fish_postexec
    printf '\e]7000;v=1;exit=%s;end_ms=%s\a' $status (math (date +%s) x 1000)
end
```

Nothing here touches `fish_prompt`; fish's own OSC 133 keeps emitting and the recovery table handles the unpaired `A`.

- [ ] **Step 4: Run the fish tests**

```bash
cd packages/terminal && node --test shell/fish.test.mjs
```

Expected: PASS.

- [ ] **Step 5: Write `bash.sh` and its test**

Create `packages/terminal/shell/bash.sh`. bash has no `preexec`, so the `DEBUG` trap is the idiom — and it must chain any existing trap rather than replace it.

```sh
if [ -n "${__OPERATOR_TERMINAL_LOADED:-}" ]; then
	return 0 2>/dev/null || exit 0
fi
__OPERATOR_TERMINAL_LOADED=1

__operator_terminal_pct_encode() {
	local s=$1 out='' i ch
	for ((i = 0; i < ${#s}; i++)); do
		ch=${s:i:1}
		case $ch in
			[A-Za-z0-9._~/:@!\$\&\'\(\)\*\+,-]) out+=$ch ;;
			*) out+=$(printf '%%%02x' "'$ch") ;;
		esac
	done
	printf '%s' "$out"
}

__operator_terminal_precmd() {
	local code=$?
	printf '\033]7000;v=1;exit=%s\007' "$code"
	printf '\033]7000;v=1;cwd=%s\007' "$(__operator_terminal_pct_encode "$PWD")"
	printf '\033]7000;v=1;input-ready=1\007'
	return $code
}

__operator_terminal_preexec() {
	[ -n "${COMP_LINE:-}" ] && return
	printf '\033]7000;v=1;cmd=%s\007' "$(__operator_terminal_pct_encode "$BASH_COMMAND")"
	printf '\033]7000;v=1;input-released=1\007'
}

__operator_terminal_existing_debug_trap="$(trap -p DEBUG | sed "s/^trap -- '//;s/' DEBUG$//")"
if [ -n "$__operator_terminal_existing_debug_trap" ]; then
	trap "$__operator_terminal_existing_debug_trap; __operator_terminal_preexec" DEBUG
else
	trap '__operator_terminal_preexec' DEBUG
fi

case ";${PROMPT_COMMAND:-};" in
	*";__operator_terminal_precmd;"*) ;;
	*) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}__operator_terminal_precmd" ;;
esac
```

Create `packages/terminal/shell/bash.test.mjs` asserting: marks are emitted for a command; a pre-existing `DEBUG` trap still fires; a pre-existing `PROMPT_COMMAND` still runs; sourcing twice emits each mark once.

- [ ] **Step 6: Extend `spawnRecipe`**

In `packages/terminal/ts/core/src/types.ts`:

```ts
export type ShellKind = "zsh" | "bash" | "fish";
```

In `packages/terminal/ts/core/src/spawn-recipe.ts`, replace the hardcoded zsh branch with a table. Leave the `suppressPrompt` guard in place — Task 10 removes it, deliberately and together with the editor.

```ts
const BOOTSTRAPS: Record<ShellKind, { file: string; argv: (path: string) => string[] }> = {
	zsh: { file: "zsh.sh", argv: (p) => ["zsh", "-c", `source ${JSON.stringify(p)}; exec zsh`] },
	bash: { file: "bash.sh", argv: (p) => ["bash", "-c", `source ${JSON.stringify(p)}; exec bash`] },
	fish: { file: "fish.fish", argv: (p) => ["fish", "-C", `source ${JSON.stringify(p)}`] },
};
```

- [ ] **Step 7: Run every shell test and commit**

```bash
cd packages/terminal && node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs && npm run test -w @operator/terminal-core
```

```bash
git add packages/terminal/shell packages/terminal/ts/core
git commit -m "feat(terminal): add bash and fish bootstraps, fish with its own OSC 133 intact"
```

---

## Task 5: The `ts/editor` package and its buffer

**Files:**
- Create: `packages/terminal/ts/editor/package.json`, `tsconfig.json`, `vitest.config.ts`
- Create: `packages/terminal/ts/editor/src/index.ts`
- Create: `packages/terminal/ts/editor/src/buffer.ts`
- Test: `packages/terminal/ts/editor/src/buffer.test.ts`
- Modify: `packages/terminal/package.json` (workspace already globs `ts/*`)
- Modify: `packages/terminal/tsconfig.base.json` references if the build uses project references

**Interfaces:**
- Produces: `EditorBuffer` with `text: string`, `cursor: number`, and methods `insert(text: string)`, `deleteBackward()`, `deleteForward()`, `deleteWordBackward()`, `moveTo(index: number)`, `moveBy(delta: number)`, `moveWord(direction: -1 | 1)`, `moveLine(direction: -1 | 1)`, `moveHome()`, `moveEnd()`, `setText(text: string, cursor?: number)`, `clear()`, `lines(): string[]`, `cursorLineColumn(): { line: number; column: number }`. Tasks 6, 8, 9 and 11 consume it.

- [ ] **Step 1: Write the failing buffer test**

Create `packages/terminal/ts/editor/src/buffer.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { EditorBuffer } from "./buffer";

describe("EditorBuffer", () => {
	it("inserts at the cursor and advances it", () => {
		const b = new EditorBuffer();
		b.insert("git");
		b.insert(" log");
		expect(b.text).toBe("git log");
		expect(b.cursor).toBe(7);
	});

	it("deletes backward one code point, not one UTF-16 unit", () => {
		const b = new EditorBuffer();
		b.insert("ok🚀");
		b.deleteBackward();
		expect(b.text).toBe("ok");
	});

	it("deletes a word back to the previous boundary", () => {
		const b = new EditorBuffer();
		b.insert("git commit --amend");
		b.deleteWordBackward();
		expect(b.text).toBe("git commit ");
	});

	it("treats a newline as a line break for line motion", () => {
		const b = new EditorBuffer();
		b.setText("one\ntwo\nthree", 9);
		expect(b.cursorLineColumn()).toEqual({ line: 2, column: 1 });
		b.moveLine(-1);
		expect(b.cursorLineColumn().line).toBe(1);
	});

	it("clamps a cursor moved past either end instead of going negative", () => {
		const b = new EditorBuffer();
		b.setText("abc");
		b.moveBy(-99);
		expect(b.cursor).toBe(0);
		b.moveBy(99);
		expect(b.cursor).toBe(3);
	});

	it("reports lines for a multi-line command", () => {
		const b = new EditorBuffer();
		b.setText("for f in *; do\n  echo $f\ndone");
		expect(b.lines()).toEqual(["for f in *; do", "  echo $f", "done"]);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
```

Expected: FAIL — the workspace does not exist yet. Create `package.json` (name `@operator/terminal-editor`, version `0.1.0`, `main` `./dist/index.js`, exports mirroring `ts/renderer-dom`), `tsconfig.json` and `vitest.config.ts` by copying the shape of `ts/renderer-dom`, then re-run. Expected: FAIL — `EditorBuffer` not found.

- [ ] **Step 3: Implement the buffer**

Create `packages/terminal/ts/editor/src/buffer.ts`. Code points, not UTF-16 units — a terminal buffer that eats half an emoji is a bug users will hit within a day.

```ts
const WORD_BOUNDARY = /[\s/\\:;,.'"`|&<>()[\]{}=]/;

export class EditorBuffer {
	private value = "";
	private caret = 0;

	get text(): string {
		return this.value;
	}

	get cursor(): number {
		return this.caret;
	}

	setText(text: string, cursor = text.length): void {
		this.value = text;
		this.caret = clamp(cursor, 0, text.length);
	}

	clear(): void {
		this.setText("", 0);
	}

	insert(text: string): void {
		this.value = this.value.slice(0, this.caret) + text + this.value.slice(this.caret);
		this.caret += text.length;
	}

	deleteBackward(): void {
		if (this.caret === 0) return;
		const start = previousCodePoint(this.value, this.caret);
		this.value = this.value.slice(0, start) + this.value.slice(this.caret);
		this.caret = start;
	}

	deleteForward(): void {
		if (this.caret >= this.value.length) return;
		const end = nextCodePoint(this.value, this.caret);
		this.value = this.value.slice(0, this.caret) + this.value.slice(end);
	}

	deleteWordBackward(): void {
		if (this.caret === 0) return;
		let index = this.caret;
		while (index > 0 && WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		while (index > 0 && !WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		this.value = this.value.slice(0, index) + this.value.slice(this.caret);
		this.caret = index;
	}

	moveTo(index: number): void {
		this.caret = clamp(index, 0, this.value.length);
	}

	moveBy(delta: number): void {
		if (delta === 0) return;
		this.moveTo(
			delta < 0
				? previousCodePoint(this.value, this.caret)
				: nextCodePoint(this.value, this.caret),
		);
	}

	moveWord(direction: -1 | 1): void {
		let index = this.caret;
		if (direction < 0) {
			while (index > 0 && WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
			while (index > 0 && !WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		} else {
			while (index < this.value.length && WORD_BOUNDARY.test(this.value[index]!)) index += 1;
			while (index < this.value.length && !WORD_BOUNDARY.test(this.value[index]!)) index += 1;
		}
		this.moveTo(index);
	}

	lines(): string[] {
		return this.value.split("\n");
	}

	cursorLineColumn(): { line: number; column: number } {
		const before = this.value.slice(0, this.caret).split("\n");
		return { line: before.length - 1, column: before[before.length - 1]!.length };
	}

	moveLine(direction: -1 | 1): void {
		const { line, column } = this.cursorLineColumn();
		const lines = this.lines();
		const target = clamp(line + direction, 0, lines.length - 1);
		if (target === line) return;
		let offset = 0;
		for (let i = 0; i < target; i += 1) offset += lines[i]!.length + 1;
		this.moveTo(offset + Math.min(column, lines[target]!.length));
	}

	moveHome(): void {
		const { column } = this.cursorLineColumn();
		this.moveTo(this.caret - column);
	}

	moveEnd(): void {
		const { line } = this.cursorLineColumn();
		const lines = this.lines();
		let offset = 0;
		for (let i = 0; i < line; i += 1) offset += lines[i]!.length + 1;
		this.moveTo(offset + lines[line]!.length);
	}
}

function clamp(value: number, min: number, max: number): number {
	return value < min ? min : value > max ? max : value;
}

function previousCodePoint(text: string, index: number): number {
	if (index <= 0) return 0;
	const code = text.codePointAt(index - 2);
	return code !== undefined && code > 0xffff ? index - 2 : index - 1;
}

function nextCodePoint(text: string, index: number): number {
	const code = text.codePointAt(index);
	return code !== undefined && code > 0xffff ? index + 2 : index + 1;
}
```

- [ ] **Step 4: Run the tests**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
```

Expected: PASS, all six.

- [ ] **Step 5: Verify the boundary checker accepts the new package and commit**

```bash
cd packages/terminal && npm run check:boundaries
```

Expected: `boundary check passed`. The checker already maps `@operator/terminal-editor` → `ts/editor` and already forbids `ts/editor` → `ts/completions`.

```bash
git add packages/terminal/ts/editor packages/terminal/package-lock.json
git commit -m "feat(terminal): add the editor package with its pure text buffer"
```

---

## Task 6: The editor view, ownership-gated

**Files:**
- Create: `packages/terminal/ts/editor/src/keymap.ts`
- Create: `packages/terminal/ts/editor/src/line-editor.ts`
- Create: `packages/terminal/ts/editor/src/styles.css`, `src/styles.ts`
- Test: `packages/terminal/ts/editor/src/keymap.test.ts`
- Test: `packages/terminal/ts/editor/src/line-editor.test.ts`

**Interfaces:**
- Consumes: `EditorBuffer` (Task 5), `LineEditorState` (Task 2).
- Produces:
  ```ts
  export type EditorHost = {
      send(text: string): void;          // command text; the editor appends "\n"
      sendRaw(data: string): void;       // passthrough keystrokes
  };
  export class LineEditor {
      mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void;
      setTheme(theme: TerminalTheme): void;
      setFont(font: FontConfig): void;
      setText(text: string): void;       // used by Task 11's edit-and-rerun
      focus(): void;
      dispose(): void;
  }
  ```
  Tasks 8, 9, 10 and 11 consume these.

- [ ] **Step 1: Write the failing keymap test**

Create `packages/terminal/ts/editor/src/keymap.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { mapKey } from "./keymap";

const key = (init: Partial<KeyboardEvent> & { key: string }) =>
	({ ctrlKey: false, metaKey: false, altKey: false, shiftKey: false, ...init }) as KeyboardEvent;

describe("mapKey", () => {
	it("maps Enter to submit and Shift+Enter to a newline", () => {
		expect(mapKey(key({ key: "Enter" }))).toEqual({ kind: "submit" });
		expect(mapKey(key({ key: "Enter", shiftKey: true }))).toEqual({ kind: "newline" });
	});

	it("maps the readline motions users expect", () => {
		expect(mapKey(key({ key: "a", ctrlKey: true }))).toEqual({ kind: "home" });
		expect(mapKey(key({ key: "e", ctrlKey: true }))).toEqual({ kind: "end" });
		expect(mapKey(key({ key: "w", ctrlKey: true }))).toEqual({ kind: "delete-word-backward" });
		expect(mapKey(key({ key: "r", ctrlKey: true }))).toEqual({ kind: "reverse-search" });
	});

	it("returns a passthrough for Ctrl-C so a running program still sees it", () => {
		expect(mapKey(key({ key: "c", ctrlKey: true }))).toEqual({ kind: "passthrough", data: "\x03" });
	});

	it("returns null for a bare modifier so it is not treated as text", () => {
		expect(mapKey(key({ key: "Shift" }))).toBeNull();
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
```

Expected: FAIL — `mapKey` not found.

- [ ] **Step 3: Write the keymap**

Create `packages/terminal/ts/editor/src/keymap.ts`:

```ts
export type EditorCommand =
	| { kind: "insert"; text: string }
	| { kind: "newline" }
	| { kind: "submit" }
	| { kind: "delete-backward" }
	| { kind: "delete-forward" }
	| { kind: "delete-word-backward" }
	| { kind: "move"; delta: -1 | 1 }
	| { kind: "move-word"; direction: -1 | 1 }
	| { kind: "move-line"; direction: -1 | 1 }
	| { kind: "home" }
	| { kind: "end" }
	| { kind: "history"; direction: -1 | 1 }
	| { kind: "accept-suggestion" }
	| { kind: "reverse-search" }
	| { kind: "passthrough"; data: string };

const CTRL_PASSTHROUGH: Record<string, string> = {
	c: "\x03",
	d: "\x04",
	z: "\x1a",
	"\\": "\x1c",
};

export function mapKey(event: KeyboardEvent): EditorCommand | null {
	const { key, ctrlKey, metaKey, altKey, shiftKey } = event;
	if (key === "Shift" || key === "Control" || key === "Alt" || key === "Meta") return null;

	if (ctrlKey && !altKey && !metaKey) {
		const raw = CTRL_PASSTHROUGH[key.toLowerCase()];
		if (raw) return { kind: "passthrough", data: raw };
		switch (key.toLowerCase()) {
			case "a": return { kind: "home" };
			case "e": return { kind: "end" };
			case "w": return { kind: "delete-word-backward" };
			case "r": return { kind: "reverse-search" };
			case "u": return { kind: "delete-word-backward" };
		}
	}

	switch (key) {
		case "Enter": return shiftKey ? { kind: "newline" } : { kind: "submit" };
		case "Backspace":
			return altKey ? { kind: "delete-word-backward" } : { kind: "delete-backward" };
		case "Delete": return { kind: "delete-forward" };
		case "ArrowLeft": return altKey ? { kind: "move-word", direction: -1 } : { kind: "move", delta: -1 };
		case "ArrowRight":
			return altKey ? { kind: "move-word", direction: 1 } : { kind: "move", delta: 1 };
		case "ArrowUp": return { kind: "history", direction: -1 };
		case "ArrowDown": return { kind: "history", direction: 1 };
		case "Home": return { kind: "home" };
		case "End": return { kind: "end" };
		case "Tab": return { kind: "accept-suggestion" };
	}

	if (metaKey || altKey || ctrlKey) return null;
	if (key.length === 1) return { kind: "insert", text: key };
	return null;
}
```

- [ ] **Step 4: Run the keymap tests**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
```

Expected: PASS.

- [ ] **Step 5: Write the failing ownership test**

Create `packages/terminal/ts/editor/src/line-editor.test.ts`. This is the phase's central guarantee: the editor never submits a line into a running program.

```ts
it("is read-only and passes keystrokes straight through while Released", () => {
	const { editor, host, core } = mount();
	core.feed(encode("\x1b]7000;v=1;input-released=1\x07"));
	editor.handleKey(key({ key: "l" }));
	editor.handleKey(key({ key: "s" }));
	editor.handleKey(key({ key: "Enter" }));
	expect(host.sent).toEqual([]);
	expect(host.raw.join("")).toBe("ls\r");
});

it("is read-only and passes keystrokes straight through while Unknown", () => {
	const { editor, host } = mount();
	editor.handleKey(key({ key: "x" }));
	editor.handleKey(key({ key: "Enter" }));
	expect(host.sent).toEqual([]);
	expect(host.raw.join("")).toBe("x\r");
});

it("edits locally and submits once Owned", () => {
	const { editor, host, core } = mount();
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	editor.handleKey(key({ key: "l" }));
	editor.handleKey(key({ key: "s" }));
	expect(host.raw).toEqual([]);
	editor.handleKey(key({ key: "Enter" }));
	expect(host.sent).toEqual(["ls"]);
});

it("clears the buffer after submitting so the next command starts empty", () => {
	const { editor, host, core } = mount();
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	editor.handleKey(key({ key: "a" }));
	editor.handleKey(key({ key: "Enter" }));
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	editor.handleKey(key({ key: "b" }));
	editor.handleKey(key({ key: "Enter" }));
	expect(host.sent).toEqual(["a", "b"]);
});

it("keeps Ctrl-C a passthrough even while Owned, so a stuck program is killable", () => {
	const { editor, host, core } = mount();
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	editor.handleKey(key({ key: "c", ctrlKey: true }));
	expect(host.raw.join("")).toBe("\x03");
});
```

- [ ] **Step 6: Run it to verify it fails**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
```

Expected: FAIL — `LineEditor` not found.

- [ ] **Step 7: Implement the view**

Create `packages/terminal/ts/editor/src/line-editor.ts`. The essential shape — the ownership check is a plain read of core state on every key, with no cached "probably ready by now" flag:

```ts
export class LineEditor {
	private readonly buffer = new EditorBuffer();
	private core: TerminalCore | null = null;
	private host: EditorHost | null = null;
	private root: HTMLElement | null = null;

	mount(container: HTMLElement, core: TerminalCore, host: EditorHost): void {
		this.dispose();
		ensurePackageStyleTag();
		this.core = core;
		this.host = host;
		const root = document.createElement("div");
		root.className = "terminal-editor";
		root.tabIndex = 0;
		root.setAttribute("role", "textbox");
		root.setAttribute("aria-multiline", "true");
		root.addEventListener("keydown", this.onKeyDown);
		container.append(root);
		this.root = root;
		this.render();
	}

	private readonly onKeyDown = (event: KeyboardEvent): void => {
		const command = mapKey(event);
		if (!command) return;
		event.preventDefault();
		this.apply(command);
	};

	handleKey(event: KeyboardEvent): void {
		const command = mapKey(event);
		if (command) this.apply(command);
	}

	private apply(command: EditorCommand): void {
		const host = this.host;
		if (!host) return;
		if (command.kind === "passthrough") {
			host.sendRaw(command.data);
			return;
		}
		if (this.core?.lineEditorState() !== "owned") {
			host.sendRaw(passthroughFor(command));
			return;
		}
		switch (command.kind) {
			case "insert": this.buffer.insert(command.text); break;
			case "newline": this.buffer.insert("\n"); break;
			case "submit": {
				const text = this.buffer.text;
				this.buffer.clear();
				host.send(text);
				break;
			}
			case "delete-backward": this.buffer.deleteBackward(); break;
			case "delete-forward": this.buffer.deleteForward(); break;
			case "delete-word-backward": this.buffer.deleteWordBackward(); break;
			case "move": this.buffer.moveBy(command.delta); break;
			case "move-word": this.buffer.moveWord(command.direction); break;
			case "move-line": this.buffer.moveLine(command.direction); break;
			case "home": this.buffer.moveHome(); break;
			case "end": this.buffer.moveEnd(); break;
			default: break;
		}
		this.render();
	}
}

function passthroughFor(command: EditorCommand): string {
	switch (command.kind) {
		case "insert": return command.text;
		case "submit": return "\r";
		case "newline": return "\n";
		case "delete-backward": return "\x7f";
		case "move": return command.delta < 0 ? "\x1b[D" : "\x1b[C";
		case "history": return command.direction < 0 ? "\x1b[A" : "\x1b[B";
		case "home": return "\x01";
		case "end": return "\x05";
		case "delete-word-backward": return "\x17";
		case "accept-suggestion": return "\t";
		default: return "";
	}
}
```

`render()` builds the prompt row (Task 10) plus one `div.terminal-editor-line` per buffer line, with a caret span at `cursorLineColumn()`, reusing the theme CSS variables so the input row is visually continuous with the blocks above it.

- [ ] **Step 8: Run the editor tests**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor && npm run check:boundaries && node ./scripts/check-no-ownership-timer.mjs
```

Expected: PASS, `boundary check passed`, `no ownership timers found`.

- [ ] **Step 9: Commit**

```bash
git add packages/terminal/ts/editor
git commit -m "feat(terminal): add the ownership-gated line editor view"
```

---

## Task 7: Command syntax highlighting

**Files:**
- Create: `packages/terminal/ts/editor/src/highlight.ts`
- Test: `packages/terminal/ts/editor/src/highlight.test.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` (render tokens)
- Modify: `packages/terminal/ts/editor/src/styles.css`, `src/styles.ts`

**Interfaces:**
- Produces: `tokenize(text: string): Token[]` where `Token = { start: number; end: number; kind: TokenKind }` and `TokenKind = "command" | "argument" | "flag" | "string" | "operator" | "path" | "variable" | "comment"`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { tokenize } from "./highlight";

const kinds = (text: string) => tokenize(text).map((t) => `${t.kind}:${text.slice(t.start, t.end)}`);

describe("tokenize", () => {
	it("marks the first word as the command and the rest as arguments", () => {
		expect(kinds("git status")).toEqual(["command:git", "argument:status"]);
	});

	it("marks flags", () => {
		expect(kinds("ls -la --color")).toEqual(["command:ls", "flag:-la", "flag:--color"]);
	});

	it("marks quoted strings as one token including the quotes", () => {
		expect(kinds(`echo "hello world"`)).toEqual(["command:echo", `string:"hello world"`]);
	});

	it("marks an unterminated quote as a string to the end rather than dropping it", () => {
		expect(kinds(`echo "oops`)).toEqual(["command:echo", `string:"oops`]);
	});

	it("marks operators and starts a new command after them", () => {
		expect(kinds("cat f | wc -l")).toEqual([
			"command:cat", "argument:f", "operator:|", "command:wc", "flag:-l",
		]);
	});

	it("marks variables and paths", () => {
		expect(kinds("cd $HOME/src")).toEqual(["command:cd", "variable:$HOME/src"]);
	});

	it("marks a comment to end of line", () => {
		expect(kinds("ls # list")).toEqual(["command:ls", "comment:# list"]);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor -- highlight
```

Expected: FAIL — `tokenize` not found.

- [ ] **Step 3: Implement the tokenizer**

Create `packages/terminal/ts/editor/src/highlight.ts`. A single left-to-right scan; no regex backtracking, no shell grammar, no external library. It must never throw on any input, because it runs on every keystroke.

Rules, in order: `#` at a token boundary starts a comment to end of line; `"` or `'` starts a string that runs to the matching quote **or end of text**; `|`, `&&`, `||`, `;`, `>`, `>>`, `<`, `&` are operators and reset "next word is a command"; a token starting `$` is a variable; a token starting `-` is a flag; the first token of a command position is `command`; everything else is `argument`.

- [ ] **Step 4: Run the tests**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor -- highlight
```

Expected: PASS, all seven.

- [ ] **Step 5: Render tokens and add the styles**

In `line-editor.ts`'s `render()`, build one `span.terminal-editor-token[data-token-kind]` per token instead of a text node. In `styles.css` give each kind a colour drawn from the theme's ANSI variables — never a hex literal, the same rule the renderer follows.

- [ ] **Step 6: Verify parity and commit**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor && npm run check:boundaries
```

```bash
git add packages/terminal/ts/editor
git commit -m "feat(terminal): highlight command syntax in the editor"
```

---

## Task 8: History and ghost text

**Files:**
- Create: `packages/terminal/ts/editor/src/history.ts`
- Test: `packages/terminal/ts/editor/src/history.test.ts`
- Modify: `packages/terminal/ts/core/src/types.ts` (`HistoryStore`)
- Modify: `packages/terminal/ts/editor/src/line-editor.ts`

**Interfaces:**
- Produces:
  ```ts
  export type HistoryStore = {
      load(): Promise<readonly string[]>;
      save(entries: readonly string[]): Promise<void>;
  };
  export class HistoryModel {
      constructor(limit?: number);
      ingest(commands: readonly string[]): void;
      suggest(prefix: string): string | null;
      recall(prefix: string, direction: -1 | 1): string | null;
      entries(): readonly string[];
  }
  ```
  Task 9 consumes `entries()`.

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { HistoryModel } from "./history";

describe("HistoryModel", () => {
	it("suggests the most recent entry that extends the prefix", () => {
		const h = new HistoryModel();
		h.ingest(["git status", "git commit -m wip", "ls"]);
		expect(h.suggest("git ")).toBe("git commit -m wip");
	});

	it("returns null when nothing matches, rather than the whole history", () => {
		const h = new HistoryModel();
		h.ingest(["ls"]);
		expect(h.suggest("zzz")).toBeNull();
	});

	it("never suggests for an empty prefix", () => {
		const h = new HistoryModel();
		h.ingest(["rm -rf build"]);
		expect(h.suggest("")).toBeNull();
	});

	it("keeps the most recent occurrence when a command repeats", () => {
		const h = new HistoryModel();
		h.ingest(["ls", "cd /", "ls"]);
		expect(h.entries()).toEqual(["cd /", "ls"]);
	});

	it("walks back and forward through matching entries", () => {
		const h = new HistoryModel();
		h.ingest(["git a", "git b", "git c"]);
		expect(h.recall("git", -1)).toBe("git c");
		expect(h.recall("git", -1)).toBe("git b");
		expect(h.recall("git", 1)).toBe("git c");
	});

	it("drops the oldest entries past the limit", () => {
		const h = new HistoryModel(2);
		h.ingest(["a", "b", "c"]);
		expect(h.entries()).toEqual(["b", "c"]);
	});
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor -- history
```

Expected: FAIL — `HistoryModel` not found.

- [ ] **Step 3: Implement it**

Dedup keeps the most recent occurrence; `suggest` scans newest-first for a strict `startsWith` that is longer than the prefix; `recall` holds a cursor that resets when the prefix changes.

- [ ] **Step 4: Source history from marks, not from the user's history file**

In `line-editor.ts`, subscribe to the core and ingest command text from decoded blocks on each change:

```ts
private ingestHistory(): void {
	const core = this.core;
	if (!core) return;
	const commands = decodeBlocks(core.snapshot())
		.map((block) => block.command)
		.filter((command) => command.length > 0);
	this.history.ingest(commands);
}
```

Add a test asserting the editor never reads a path: `expect(readFileSpy).not.toHaveBeenCalled()` around a mount, and a source-level check in `check-boundaries.mjs` that `ts/editor` contains no `zsh_history`, `bash_history`, `fish_history` or `node:fs` reference.

- [ ] **Step 5: Render ghost text**

Append a `span.terminal-editor-ghost` carrying `suggest(buffer.text)` minus the prefix when the cursor is at the end of the buffer. `Tab` (`accept-suggestion`) replaces the buffer with the suggestion.

- [ ] **Step 6: Run and commit**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor && npm run check:boundaries
```

```bash
git add packages/terminal/ts/editor packages/terminal/ts/core packages/terminal/scripts
git commit -m "feat(terminal): history from marks with ghost-text suggestion"
```

---

## Task 9: Ctrl-R reverse search

**Files:**
- Create: `packages/terminal/ts/editor/src/reverse-search.ts`
- Test: `packages/terminal/ts/editor/src/reverse-search.test.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts`
- Modify: `packages/terminal/ts/core/src/types.ts` (`TerminalStrings` gains `searchHistory`, `searchNoMatches`)

**Interfaces:**
- Produces: `ReverseSearch` with `open(entries)`, `type(char)`, `backspace()`, `next()`, `previous()`, `accept(): string | null`, `cancel()`, `state(): { query: string; match: string | null; index: number; total: number }`.

- [ ] **Step 1: Write the failing test**

```ts
it("matches a substring anywhere in the entry, newest first", () => {
	const s = new ReverseSearch();
	s.open(["git status", "npm run build", "git commit"]);
	s.type("g"); s.type("i"); s.type("t");
	expect(s.state().match).toBe("git commit");
	s.next();
	expect(s.state().match).toBe("git status");
});

it("reports no match instead of falling back to an unrelated entry", () => {
	const s = new ReverseSearch();
	s.open(["ls"]);
	s.type("z");
	expect(s.state().match).toBeNull();
});

it("accept returns the match and cancel returns null", () => {
	const s = new ReverseSearch();
	s.open(["make test"]);
	s.type("test");
	expect(s.accept()).toBe("make test");
	s.open(["make test"]);
	s.type("test");
	s.cancel();
	expect(s.accept()).toBeNull();
});

it("backspace widens the match set again", () => {
	const s = new ReverseSearch();
	s.open(["alpha", "beta"]);
	s.type("a"); s.type("l");
	expect(s.state().total).toBe(1);
	s.backspace();
	expect(s.state().total).toBe(2);
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor -- reverse-search
```

- [ ] **Step 5: Wire Ctrl-R into the editor**

`{ kind: "reverse-search" }` opens the overlay; while open, printable keys go to `type`, `Backspace` to `backspace`, `Ctrl-R` to `next`, `Enter` to `accept` (which sets the buffer, closes, and does **not** submit), `Escape` to `cancel`. Add a test that `Enter` during search does not call `host.send` — accepting a search result and running it are two decisions.

- [ ] **Step 6: Add the two strings to `TerminalStrings` and `defaultStrings`, and to all eight Operator locale files. Run and commit.**

```bash
cd packages/terminal && npm run test -w @operator/terminal-editor
cd frontend && npm run test
```

```bash
git add packages/terminal/ts frontend/src/renderer/i18n
git commit -m "feat(terminal): Ctrl-R history search in the editor"
```

---

## Task 10: The prompt row, and suppression turned on

**This is the task §8.1 is about. The prompt row and prompt suppression land in the same commit. A reviewer who sees suppression enabled without the prompt row, or the guard removed in an earlier task, should reject it.**

**Files:**
- Create: `packages/terminal/ts/editor/src/prompt-row.ts`
- Test: `packages/terminal/ts/editor/src/prompt-row.test.ts`
- Modify: `packages/terminal/ts/core/src/spawn-recipe.ts`
- Modify: `packages/terminal/shell/zsh.sh`, `bash.sh`, `fish.fish`
- Test: `packages/terminal/shell/*.test.mjs`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts`

**Interfaces:**
- Produces: `renderPromptRow(context: PromptContext, strings: TerminalStrings): HTMLElement` where `PromptContext = { cwd: string; gitBranch: string; lastExitCode: number | null; lastDurationMs: number | null; state: LineEditorState }`.

- [ ] **Step 1: Write the failing prompt-row test**

```ts
it("shows cwd and branch from mark data", () => {
	const row = renderPromptRow(
		{ cwd: "/Users/x/src/app", gitBranch: "main", lastExitCode: 0, lastDurationMs: 120, state: "owned" },
		defaultStrings,
	);
	expect(row.textContent).toContain("app");
	expect(row.textContent).toContain("main");
});

it("marks a failing previous command without inventing an exit code", () => {
	const row = renderPromptRow(
		{ cwd: "/", gitBranch: "", lastExitCode: 1, lastDurationMs: null, state: "owned" },
		defaultStrings,
	);
	expect(row.dataset.lastExit).toBe("1");
	const none = renderPromptRow(
		{ cwd: "/", gitBranch: "", lastExitCode: null, lastDurationMs: null, state: "owned" },
		defaultStrings,
	);
	expect(none.dataset.lastExit).toBeUndefined();
});

it("says the shell owns the line when state is not owned", () => {
	const row = renderPromptRow(
		{ cwd: "/", gitBranch: "", lastExitCode: null, lastDurationMs: null, state: "unknown" },
		defaultStrings,
	);
	expect(row.dataset.state).toBe("unknown");
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

- [ ] **Step 5: Write the failing suppression tests**

In `packages/terminal/ts/core/src/spawn-recipe.test.ts`:

```ts
it("accepts suppressPrompt now that the editor exists", () => {
	const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: true });
	expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("1");
});

it("still offers a show-shell-prompt mode as the fallback", () => {
	const recipe = spawnRecipe("zsh", { integration: "auto", suppressPrompt: false });
	expect(recipe.env.OPERATOR_TERMINAL_SUPPRESS_PROMPT).toBe("0");
});
```

In `shell/zsh.test.mjs`:

```js
test("suppresses the prompt to a sentinel only when asked, and reversibly", async () => {
	const on = await runZsh(["echo hi"], { OPERATOR_TERMINAL_SUPPRESS_PROMPT: "1" });
	assert.ok(!on.includes("SHELLPROMPT"), "user prompt should not render");
	const off = await runZsh(["echo hi"], { OPERATOR_TERMINAL_SUPPRESS_PROMPT: "0" });
	assert.ok(off.includes("SHELLPROMPT"), "user prompt must still render when not suppressed");
});
```

- [ ] **Step 6: Remove the guard and assign the prompt variable**

In `spawn-recipe.ts` delete the `if (options.suppressPrompt) throw` block and pass `suppressPrompt ? "1" : "0"` through `env`.

In each bootstrap, assign the prompt variable in the precmd hook — **after** the user's config has loaded, which is what makes it reversible and what keeps it a variable assignment rather than a framework fight:

```sh
	if [[ ${OPERATOR_TERMINAL_SUPPRESS_PROMPT:-0} == 1 ]]; then
		PROMPT=''
		RPROMPT=''
	fi
```

No framework is named, nothing is unset, and flipping the env var restores the user's prompt on the next shell.

- [ ] **Step 7: Mount the prompt row above the editor input**

`LineEditor.render()` prepends `renderPromptRow(...)` built from the newest block's `cwd`, `gitBranch`, `exitCode` and `durationMs`, plus `core.lineEditorState()`.

- [ ] **Step 8: Run everything and commit as one change**

```bash
cd packages/terminal && npm test && node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs && npm run check:boundaries && node ./scripts/check-no-ownership-timer.mjs
```

```bash
git add packages/terminal
git commit -m "feat(terminal): draw the prompt row and turn prompt suppression on with the editor"
```

---

## Task 11: Operator mounts the editor

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx`
- Modify: `packages/terminal/ts/react/src/index.ts`
- Modify: `packages/terminal/ts/editor/src/line-editor.ts` (`setText` for rerun)
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx`
- Test: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`
- Test: `frontend/src/renderer/components/BlockTerminal.test.tsx`

**Interfaces:**
- Consumes: `LineEditor` (Task 6), `EditorHost` (Task 6).
- Produces: `TerminalSurfaceProps` gains `onSend(text: string): void` and `onSendRaw(data: string): void`.

- [ ] **Step 1: Write the failing surface test**

```tsx
it("mounts the editor below the block list and hides it in the alt screen", async () => {
	const { container, core } = renderSurface();
	expect(container.querySelector(".terminal-editor")).not.toBeNull();
	core.feed(encode("\x1b[?1049h"));
	await paint();
	expect(container.querySelector(".terminal-editor")?.checkVisibility?.() ?? false).toBe(false);
});

it("sends submitted text through onSend with no synthesized escape sequences", () => {
	const { editor, onSend, core } = renderSurface();
	core.feed(encode("\x1b]7000;v=1;input-ready=1\x07"));
	typeInto(editor, "make test");
	pressEnter(editor);
	expect(onSend).toHaveBeenCalledWith("make test");
	expect(onSend.mock.calls[0][0]).not.toMatch(/\x1b/);
});
```

- [ ] **Step 2–4: Run (FAIL), implement, run (PASS)**

`TerminalSurface` creates a `LineEditor` in the same layout effect that creates the renderer, mounts it into a sibling element below the block list host, and disposes it alongside. In alt screen the editor's container gets `hidden`, exactly as `AltScreenSlot` already does for the block list.

- [ ] **Step 5: Wire Operator's transport**

In `BlockTerminal.tsx`:

```tsx
const onSend = useCallback((text: string) => {
	transportRef.current.write(new TextEncoder().encode(`${text}\n`));
}, []);

const onSendRaw = useCallback((data: string) => {
	transportRef.current.write(new TextEncoder().encode(data));
}, []);
```

Add a test asserting a submit produces exactly `"make test\n"` on the transport and nothing else.

- [ ] **Step 6: Edit-and-rerun from a block**

The block action `rerun` already exists in `renderer-dom` and already has a `TerminalStrings.rerunCommand` label. Route it through a callback on `TerminalSurfaceProps` that calls `editor.setText(command)` and `editor.focus()` — prefill, never auto-submit. Add a test that rerun does not call `onSend`.

- [ ] **Step 7: Run every gate and commit**

```bash
cd packages/terminal && npm test && npm run check:boundaries
cd frontend && npm run typecheck && npm run test
```

```bash
git add packages/terminal frontend/src
git commit -m "feat(terminal): mount the input editor in Operator's session pane"
```

---

## Task 12: Close Phase 2

**Files:**
- Modify: `packages/terminal/bench/scenarios.json` (input-latency drives the editor)
- Modify: `packages/terminal/bench/adapters/dom.ts`
- Modify: `packages/terminal/CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md` (§14 phase status)

- [ ] **Step 1: Make `input-latency` measurable for our renderer**

Phase 1b's adapter throws for `dispatchPrintableKey` with "the DOM renderer has no input path until Phase 2". That is now false. Replace the throw with a real dispatch into the mounted `LineEditor`, measuring keydown → painted glyph.

- [ ] **Step 2: Run the §9.4 gate in full**

```bash
cd packages/terminal && npm run bench:terminal
```

Required, against the recorded xterm baselines: `large-output` throughput ≥ baseline; `input-latency` p95 ≤ baseline; `vtebench` ≥ 0.9× baseline; 50,000-block scroll holds 60fps.

- [ ] **Step 3: Prove the Tier-1-only session is usable**

A spec acceptance criterion. Add a Playwright case to the vite smoke: spawn with `integration: "osc133-only"`, confirm `lineEditorState()` stays `"unknown"`, the editor renders read-only, typing reaches the transport as raw bytes, and blocks still appear.

- [ ] **Step 4: Re-run the no-timer check across the finished ownership path**

```bash
cd packages/terminal && node ./scripts/check-no-ownership-timer.mjs
```

Expected: `no ownership timers found`, with a scanned-file count of **at least 3** — the two core Rust files plus `ts/editor/src/line-editor.ts`, which reads `lineEditorState()` and therefore joins the derived set automatically. If the count is still 2, the editor is not consulting core state on the input path and the phase's headline guarantee is unproven; fix that before closing, do not lower the check.

If a timer was introduced anywhere in the editor's ownership handling during Tasks 6–11, this is where it is caught and removed — not worked around.

- [ ] **Step 5: Full gate sweep**

```bash
cd packages/terminal && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
cd packages/terminal/go/marks && go test ./...
cd packages/terminal && node --test shell/zsh.test.mjs shell/bash.test.mjs shell/fish.test.mjs
cd packages/terminal && npm test && npm run check:boundaries && npm run smoke:vite && npm run smoke:tauri
cd frontend && npm run typecheck && npm run test
```

- [ ] **Step 6: Update the changelog and the spec's phase status, then commit**

```bash
git add packages/terminal docs
git commit -m "chore(terminal): close Phase 2 — editor, prompt ownership, three shells"
```

---

## Self-Review

**Spec coverage.** §10.1 editor → Tasks 5–9. §10.2 ownership → Tasks 1, 2, 6, and the checker in Task 2 Step 8. §10.3 submit semantics → Task 6 Step 7, Task 11 Step 5. §10.4 history → Task 8, including the "never read the user's history file" check. §8 additive bootstrap → Tasks 3, 4, 10. §8.1 suppression timing → Task 10, held together in one commit. §3.2 fish → Task 4 Step 1. §3.5 no timer → Tasks 1, 2, 12. §7.2 additive Tier 2 → Task 1 Step 3 and the interleave vector. §9.4 gate → Task 12. Phase 2 deliverables in §14 — `ts/editor`, suppression + prompt row, `input-ready`/`input-released` + `LineEditorState`, highlighting, multi-line, ghost text, Ctrl-R, edit-and-rerun, `bash.sh`, `fish.fish` — all have tasks.

**Known gap, deliberately named.** Completions are Phase 4 (renumbered by spec §2.8, which inserted the alternate-screen grid as Phase 3); `editor` must not import `completions`, and the boundary checker already enforces it. Task 6's keymap maps `Tab` to `accept-suggestion` rather than leaving it unbound, so that phase changes one branch rather than retrofitting a key.

**Type consistency.** `LineEditorState` is `"unknown" | "owned" | "released"` everywhere in TS and `LineEditorState::{Unknown, Owned, Released}` in Rust, wire values 0/1/2, fixed in Task 2 and consumed unchanged by Tasks 6, 10, 11. `EditorCommand` is defined once in Task 6 and consumed by Tasks 8 and 9. `EditorHost.send` takes bare command text and the editor appends the newline — Task 11's Operator wiring is the only place `\n` is added.

**Prerequisite from Phase 1, unresolved at the time of writing.** Phase 1 Tasks 6 (daemon `pipe-pane` capture), 8 (perf gate and the 50,000-block scroll test) and 9 (close) are open. Task 12 Step 2 of this plan runs the §9.4 gate, which Phase 1 Task 8 was supposed to establish. If that baseline does not exist when Phase 2 reaches Task 12, record it there before gating — do not skip the gate, and do not silently invent a baseline.
