# Design — `packages/terminal`: a Warp-grade terminal as a reusable package

Status: phases 0–5 landed; phase 6 deferred; phase 7 is next. See §0.7.
Date: 2026-08-29
Last synced to the tree: 2026-09-02 (tmux removal, blocks-view removal, look parity)
Author: design session with the user, 2026-08-29
Supersedes: the frontend half of `docs/superpowers/plans/2026-08-28-shell-blocks.md` (see §13)
Reference codebase: Warp at `/Users/omaraly/development/AI/warp` (read-only; we never copy code, we learn from it)

---

## 0. How to use this spec (read this before planning anything)

This section exists because implementation plans written from earlier specs in this
repo drifted from what the spec intended. If you are an agent turning this document
into an implementation plan, these rules bind you.

**0.1 — The decisions in §2 are closed.** They were made by the user in a design
session on 2026-08-29 after reading the Warp source. Every one of them has its
reasoning recorded. Do not reopen them, do not "improve" them, do not propose an
alternative in the plan. If you believe a decision is wrong, stop and say so to the
user in one paragraph — do not silently plan something else.

**0.2 — The evidence is checkable. Check it.** Every claim about Warp cites
`file:line` in `/Users/omaraly/development/AI/warp`. Every claim about Operator cites
`file:line` in this repo. If a citation does not say what this spec says it says,
that is a bug in this spec — report it rather than planning around it.

**0.3 — Phases are not negotiable in order, only in depth.** §14 lists phases 0
through 8. A plan covers one phase. A plan that "gets a head start" on the next phase
is wrong: the phase boundaries are where the user looks at the thing and decides
whether it feels like Warp. Removing a checkpoint removes the only steering we have.

**0.4 — Acceptance criteria are the contract.** Each phase in §14 has criteria that
are mechanically checkable. A plan must make each criterion a task with a verification
command. "It works" is not a criterion; `npm run bench:terminal -- --scenario large-output`
producing a number above the gate is.

**0.5 — When this spec says "MUST NOT", it is guarding against a specific failure we
already watched happen in Warp.** §15 lists the wrong turns explicitly. Read it.

**0.6 — Scope discipline.** This spec describes a package plus its integration into
Operator. It does not authorize refactoring Operator's session model, chat, kanban,
orchestrator, or backend beyond the integration points named in §13.

**0.7 — Where this stands, and what changed under it.** Synced against the tree on
2026-09-02. Phases 0–5 have landed. **Phase 6 is deferred by the user**: its four
inherited look gaps are closed, its own four deliverables are re-scoped in the table under
that phase, and scrollback persistence moved into phase 7. **Phase 7 is the next phase**,
and its first step is the history migration, not a deletion. Phase 8 is untouched. §14
carries the per-phase detail. Three things changed *outside*
this spec since it was written, and each one invalidates something the spec asserted:

1. **tmux is gone.** `docs/superpowers/specs/2026-09-01-tmux-free-pty-runtime-design.md`
   replaced the tmux runtime with `ptyhost` on every platform, landed as
   `ba5fd58a1` and the commits around it. `backend/internal/adapters/runtime/` now holds
   `ptyhost`, `runtimeselect` and `parity` — no tmux adapter, and `runtimeselect.New`
   has nothing left to select. The open work that cutover left behind is in
   `todo_without_tmux.md`, not here.

   **The consequence this spec must absorb: an agent pane is no longer in the alternate
   screen.** §11 and phase 3 both recorded that a Claude Code pane sits in the alternate
   screen "because tmux puts it there" — tmux's own client emitted `?1049h` in its first
   chunk. With tmux out of the path, the agent's own bytes reach the renderer, and
   Claude Code emits no `?1049` at all: it redraws inline in the **normal buffer** with
   cursor addressing. The normal-buffer grid landed by the 2026-08-30 plan is therefore
   not a hedge, it is the agent pane's only surface, and the block chrome is visible
   there. `XtermTerminal` and the alternate-screen surface now carry full-screen TUIs
   (`vim`, `htop`, `less`) and nothing else.

2. **The blocks view is gone from the session pane** (`e246a1470`). The pane offered a
   third surface behind a "Show blocks" toggle, with `defaultSessionViewMode` and an
   in-memory `sessionViewModeBySession` behind it. All of it is deleted, along with the
   font stepper, pane fullscreen and Cmd+wheel zoom (`c9c7f71d9`). A session is now the
   terminal plus the chat UI, which is what §13.4's "one session has exactly one
   terminal surface" was aiming at — arrived at from the other direction, and ahead of
   phase 7. `SessionBlocksPane` survives: it is the chat UI's renderer, not a terminal
   surface.

3. **Phase 6's look parity landed** — `a83e29013` through `fbe04f719`. The three wrong
   values in §12.1 are fixed and the table records that, as is the fourth item, the
   clipped bottom row, which turned out to be two bugs.

**And one thing that is settled but has no number to prove it.** Scroll — the complaint
the tmux removal existed to fix — was confirmed good in real use by the user on
2026-09-02. `todo_without_tmux.md` §1 records that the `scroll-latency` A/B was never run
against tmux (tmux ate the wheel report and entered copy-mode; the metric is vsync-
quantized at its floor, p50 = p95 = 17.000ms with zero variance). That gap is a missing
measurement, not a suspected regression, and nobody should re-open the scroll question
looking for a phase that fixes it: §0.7 item 1, §9.5's paint scheduling and §11's
fractional wheel-delta accumulation are the fix, and they have all landed.

---

## 1. Goal, and what "identical to Warp" means

### 1.1 The goal in one sentence

Build a terminal that a Warp user cannot distinguish from Warp in look and feel, as a
self-contained package that any project can consume, whose maintenance stays inside
its own directory.

### 1.2 What we are matching

Warp's identity comes from three mechanisms, not from its GPU renderer:

1. **The scrollback is a list of blocks, not a wall of rows.** Warp's grid is
   block-aware at the data-structure level — `crates/warp_terminal/src/model/blockgrid.rs`
   (1,020 lines), built on an Alacritty-derived grid:
   `crates/warp_terminal/src/model/grid/grid_handler.rs:1-2` states the code is
   *"adapted from the alacritty_terminal crate under the Apache license"*, and
   `crates/warp_terminal/src/model/ansi/mod.rs:1-11` describes their `Processor` as
   *"a lightweight wrapper around Alacritty's `VteParser`"*. Selection, find, filtering
   and the viewport are all per-block.

2. **The shell tells the app where blocks begin and end.** A 1,588-line
   `app/assets/bundled/bootstrap/zsh_body.sh` (plus 1,437 for bash, 804 for fish)
   injects hooks that emit DCS payloads for `InitShell`, `precmd` and `preexec`.

3. **Input is not the shell's readline.** `app/src/terminal/input/{classic,agent,buffer_model}.rs`
   is a real text editor. `app/src/terminal/line_editor_status.rs` exists solely to
   track whether the shell's line editor is idle so Warp can take input over.

The GPU renderer (`crates/warpui`, 34,439 lines including
`src/rendering/{atlas/,glyph_cache.rs,wgpu/}`) is how Warp draws, not why it feels like
Warp. We are explicitly not matching it (§2.3).

### 1.3 Scale, for calibration

Measured by `find … -name '*.rs' | xargs wc -l` on 2026-08-29:

| Warp subsystem | Lines |
| --- | --- |
| `app/src/terminal` | 230,377 |
| `crates/warp_terminal` | 46,585 |
| `app/src/editor` | 43,279 |
| `crates/warpui` | 34,439 |
| `crates/warp_completer` | 19,054 |

We are not writing 370k lines. We are writing the mechanisms in §1.2 and matching the
look in CSS, which is where a browser host is cheaper than a native one.

### 1.4 Non-goals

- **Not** a GPU/WebGL renderer in phases 0–7. §9.4 defines the escape hatch and the
  measurement that would trigger it.
- **Not** Warp's AI features. Operator already has agents; the package stays agent-agnostic.
- **Not** Warp's cloud features — sharing, teams, sync, auth, Warp Drive.
- **Not** a change to Operator's session model, orchestrator, or kanban.
- **Not** a Windows shell-block story in phases 0–6. Windows opens the raw grid and
  says shell blocks are unavailable, the same visible-absence rule plan 7 chose. Do
  not silently degrade. *Obsolete as a carve-out since 2026-09-02:* one runtime now
  runs on every platform (§0.7, §13.1), so Windows has capture and rendered output like
  everywhere else. The visible-absence rule survives as the rule for any capability that
  is genuinely absent.

---

## 2. Decisions already made — closed, with reasoning

These were decided by the user on 2026-08-29. §0.1 applies.

**2.1 — We own the input; the shell's readline is replaced.**
We draw the prompt row ourselves from mark data (cwd, git branch, exit code,
duration). The user's `starship`/`oh-my-zsh`/`powerlevel10k` prompt stops rendering.
*Reasoning:* this is the single largest contributor to "it feels like Warp", and it is
what makes a block's command text exact rather than scraped off the screen.
*Consequence accepted:* Ctrl-R and Tab completion become our code (phases 2 and 3).

**2.2 — Desktop first; mobile is phase 8.**
`frontend/src/renderer` gets the package. `packages/mobile` keeps its current xterm
fork until the desktop model is proven, then ports against the same daemon block
stream. The daemon-side work is shared from day one so mobile inherits it.

**2.3 — Rust/WASM core, DOM renderer first.**
The core (parser, grid, blockgrid, selection, find) is Rust compiled to WASM. The
renderer is DOM, virtualized, behind an interface.
*Reasoning:* parsing is where JS falls over, and a Rust core is reusable natively by
the Tauri side and by any future host. DOM gives us Warp's look in CSS, plus native
text selection, copy, accessibility and ligatures for free. The renderer interface
means a WebGL implementation can replace the DOM one later without touching core,
blocks, or the editor.
*Rejected:* WebGL-first (we would hand-build font fallback, ligatures and subpixel
positioning before anything looked finished, and re-implement selection and a11y);
TS-core (rewriting xterm, no perf win, no native reuse).

**2.4 — The package lives at `packages/terminal` in this repo, written as if published.**
No Operator imports. Own tests, own benchmarks, own version, own CHANGELOG.
*Reasoning:* iterating on package and app in one commit is worth more right now than a
hard repo boundary; the import rules in §4.2 are what actually keep it generic.

**2.5 — Everything gets built, in phases.** §14.

**2.6 — OSC 133 is the baseline; our extension is additive.** §7.
*Reasoning:* it is the single decision that makes the package generic, and it is the
one Warp can no longer retrofit. See §3.3.

**2.8 — The package renders the alternate screen itself; xterm is retired.**
Decided 2026-08-29 after instrumenting a live agent session: it enters the alternate
screen on the *first chunk* of output and stays there. Under the original plan
`XtermTerminal.tsx` was the permanent alt-screen surface, which meant the pane the user
actually watches all day was never ours — blocks, headers, actions and the editor only
ever appeared for a plain shell. Warp does not embed a second emulator; neither will we.
Phase 3 gives `vt-core` a real alternate-screen grid and the renderer a raw surface, and
phase 7 deletes `XtermTerminal.tsx` along with the shell-terminal tabs.
*Consequence accepted:* completions, navigation and chrome each move one phase later.
*Amended 2026-09-02, decision unchanged:* the premise — agent panes live in the alternate
screen — was tmux's doing and expired with tmux (§0.7, §11). The decision stands on its
own terms regardless: a host that embeds a second emulator for any buffer is a host whose
pane is not ours, and phase 7 still deletes xterm.

**2.7 — The terminal pane is pixel-Warp; the app chrome around it stays agent-orchestrator.**
`DESIGN.md:36` already carves this out: *"the accent is refined blue, and the terminal
keeps its own palette."* We are reading that carve-out as license for the pane's
interior. The tab strip, sidebar, and every surface outside the terminal pane continue
to track agent-orchestrator per `CLAUDE.md`.

---

## 3. What we are doing differently from Warp, and why

Each item is a mistake we can see in Warp's source, the rule we adopt instead, and the
citation so a planner can verify it.

### 3.1 Warp's shell takeover is so invasive it hardcodes a third-party prompt by name

`app/assets/bundled/bootstrap/zsh_body.sh:236-242` caches the user's `precmd_functions`
into `_USER_PRECMD_FUNCTIONS`, removes all of them, and restores them a prompt later —
with a carve-out matching `*(warp|p9k)*` so powerlevel10k does not break.
`:378-385` removes the user's `\ei` and `\ep` bindings and rebinds them to Warp
functions, with comments about `bindkey -v` and prezto re-linking keymaps underneath.

**Our rule — additive-only shell integration.** We register hooks with `add-zsh-hook`
and never unregister the user's. We never rebind a user key. We never source the
user's config on their behalf. When a prompt framework conflicts, the block degrades;
we do not add a vendor name to a shell script. §8 is the full contract.

### 3.2 Warp assumed marks arrive in pairs, and a spec-compliant shell broke it

`crates/warp_terminal/src/local_tty/shell.rs:691-694` launches fish with
`-f no-mark-prompt` to **disable** standard OSC 133, with the comment that fish
*"breaks Warp by emitting `OSC 133 A` but not `OSC 133 B` afterwards, which we have
assumed"*, citing `github.com/warpdotdev/Warp/issues/7588`. Their fix for a compliant
shell was to turn the standard off.

**Our rule — the block state machine is a tolerant parser.** Missing end mark closes
the block on the next start mark. Out-of-order marks recover. Unknown parameters are
ignored, never fatal. §7.4 specifies the recovery table, and §7.6 requires a fuzz
corpus that includes unpaired and interleaved marks from phase 1.

### 3.3 Warp's protocol is private, so no bootstrap means no blocks

`crates/warp_terminal/src/model/ansi/dcs_hooks.rs:16-28` defines three accumulated
payload encodings — `'d'` hex-encoded JSON, `'f'` unencoded JSON, `'k'` key-value —
and `HookSessionId = Option<u64>` where both `None` and `Some(0)` mean "legacy".
Warp *does* parse OSC 133 (`crates/warp_terminal/src/model/ansi/mod.rs:1019-1026`) but
does not treat it as a block source. The result: over ssh, inside a container, in a
devcontainer, in a subshell, or in any shell they do not ship a script for, there are
no blocks. Their ssh answer is heuristic — `app/assets/bundled/bootstrap/bash_body.sh:966-969`
defines `is_interactive_ssh_session()` which inspects the user's ssh arguments, next to
ControlMaster hang workarounds at `:87-93`.

**Our rule — OSC 133 + OSC 7 first, our extension second.** Any shell already emitting
semantic prompt marks for iTerm2, VS Code, kitty, WezTerm or ghostty gets blocks with
zero setup, including over ssh and inside containers. Our bootstrap adds only what 133
cannot express. Remote is never sniffed from argv. §7.

### 3.4 Warp let files grow without bound

`app/src/terminal/view.rs` is 29,236 lines. `app/src/terminal/input.rs` is 16,760.
That is how one subsystem reached 230k lines.

**Our rule — boundaries enforced by the package graph.** `renderer-dom` MUST NOT
import `editor`; `editor` MUST NOT import `completions`; all of them talk through
`core`. §4.3 makes this a lint. A source file over ~600 lines fails review.

### 3.5 Warp's input takeover is a 50ms timing guess

`app/src/terminal/line_editor_status.rs:17` defines
`LINE_EDITOR_ACTIVATION_DELAY: Duration = Duration::from_millis(50)`, documented as the
wait after a precmd hook *"before assuming the shell's line editor is active again"*,
existing to prevent *"Warp sending an escape sequence to an arbitrary running program"*.
The same file uses `did_receive_zsh_precmd` as a *proxy* for whether the session is
bootstrapped at all.

**Our rule — the shell states it explicitly.** Our extension carries an
`input-ready` / `input-released` mark. We never infer line-editor ownership from a
timer. This is cheap for us because we are authoring the protocol and impossible for
Warp because theirs is frozen. §10.2.

### 3.6 Warp runs invisible commands in the user's shell

`zsh_body.sh:254-262` kills "ongoing generator command jobs" in `warp_preexec`, and
`:205-208` documents generator commands *"left running/not cancelled properly"*. These
are commands Warp executes inside your session to gather UI state.

**Our rule — no invisible execution in the user's session, ever.** Everything we need
arrives via marks or is computed in our own process. If a feature seems to require
running something in the user's shell, it is out of scope until the user approves it
explicitly.

**Where the line actually is.** This rule has been read too broadly twice, so it is
drawn here explicitly. What Warp did wrong is *asynchronous background jobs* it spawned
into the session to gather UI state — jobs it then had to hunt down and kill in
`warp_preexec` because they were "left running/not cancelled properly". The sin is
unbounded, invisible, cancellable-in-theory work living in the user's shell.

**Permitted**, because a hook that returns immediately and mutates nothing is not an
invisible job:

- a synchronous, read-only, fast command in a prompt hook that produces a Tier-2 field
  §7.2 requires — `git rev-parse --abbrev-ref HEAD` for `branch` is the one that exists,
  and `shell/zsh.sh` has shipped it since phase 1a;
- a one-shot command during bootstrap, run once at source time — for example probing
  whether a tool exists.

**Forbidden:**

- anything backgrounded, `&`-suffixed, or otherwise outliving the hook that started it;
- anything that mutates shell or repository state;
- a per-command subprocess for a field we can compute ourselves. Command duration is the
  concrete case: do **not** shell out to `date` in preexec and precmd to produce
  `start_ms` / `end_ms`. The package sees when marks arrive and computes duration in its
  own process. `shell/zsh.sh` deliberately emits neither key, and the other bootstraps
  MUST match it.

A bootstrap that is unsure should emit fewer Tier-2 fields, never run more commands:
Tier 2 is additive and every field is ignorable (§7.2).

### 3.7 What we deliberately copy from Warp

Not everything is a mistake. Adopt these:

- **A sum tree over the block list.** Warp uses `sum_tree` in exactly the four places
  that matter: `app/src/terminal/model/blocks.rs`, `app/src/terminal/block_list_viewport.rs`,
  `app/src/terminal/model/blocks/selection.rs`, `app/src/terminal/find/model/async_find.rs`.
  §6.3.
- **Flat chunked content with run-length attribute maps.** `crates/warp_terminal/src/model/grid/flat_storage/`. §6.2.
- **A recorded-stream test corpus.** Warp keeps `app/src/terminal/ref_tests/data/**/*.recording`
  — raw byte streams replayed against the parser. §6.6.
- **Alt-screen as an explicit, tracked mode.** `app/src/terminal/alt_screen/`. §11.

---

## 4. The package boundary

### 4.1 What the host provides and what the package returns

The package MUST NOT know that Operator exists. No daemon, no pty runtime, no HTTP, no
mux channel, no session IDs, no Operator design tokens, no `react-i18next`.

```ts
export interface PtyTransport {
  write(data: Uint8Array): void;
  onData(cb: (data: Uint8Array) => void): () => void;
  resize(cols: number, rows: number): void;
  dispose(): void;
}

export interface DirEntry {
  name: string;
  isDirectory: boolean;
  isHidden: boolean;
}

export interface HostCapabilities {
  writeClipboard(text: string): Promise<void>;
  readClipboard(): Promise<string>;
  openLink(url: string): Promise<void>;
  notify?(title: string, body: string): void;
  listDirectory?(path: string): Promise<readonly DirEntry[]>;
}

export interface SpawnRecipe {
  argv: string[];
  env: Record<string, string>;
}

export interface TerminalOptions {
  transport: PtyTransport;
  host: HostCapabilities;
  theme: TerminalTheme;
  font: FontConfig;
  strings: TerminalStrings;
  scrollback: number;
  integration: "auto" | "osc133-only" | "off";
}
```

`listDirectory` was added in phase 4 and is the only filesystem the package ever sees.
It is **optional** on purpose: path completion is the one provider that cannot be computed
in-process, and a host without a filesystem — a browser, a remote pane — must keep every
other provider rather than lose completions entirely. The three fields are Warp's
`EngineDirEntry` (`completer/engine/path.rs:36-51`). Note what is absent: there is no
capability that can run a command, which is what makes §3.6 structural here rather than a
rule someone has to remember.

`integration` selects the tier the host wants (§7.2). `auto` returns a bootstrap and
consumes both tiers. `osc133-only` returns a bare shell recipe and consumes Tier 1
only — this is the mode a host picks when it must not touch the user's shell at all,
and it MUST be a first-class tested path, not a degraded one. `off` disables mark
consumption entirely and renders a plain grid.

The load-bearing call is the other direction:

```ts
export function spawnRecipe(shell: ShellKind, opts: BootstrapOptions): SpawnRecipe;
```

The host asks the package what to spawn and pipes bytes. The host never parses marks
and never versions against the protocol. Operator's daemon is one host; a plain PTY in
another project is another. §13 shows Operator's wiring.

### 4.2 Import rules

- The package MUST NOT import anything from `frontend/`, `backend/`, or `packages/shared/`.
- `frontend/` imports the package **by package name only** — `@operator/terminal-react` —
  never by relative path. The existing pattern at
  `frontend/src/renderer/lib/ansi.ts:2` (`export { … } from "../../../../packages/shared/chat/ansi"`)
  is exactly what we are not doing, because a relative path across the boundary means
  nothing stops Operator types from leaking back in.
- User-facing copy is injected via `TerminalStrings` (§12.2). The package ships English
  defaults and ships no locale files.
- **`backend/` consumes the package the same way `frontend/` does: by name, never by
  path.** Two edges exist as of 2026-09-02 — the `packages/terminal/go/marks` Go module
  (§5.4), imported by module path with a `replace` directive in `backend/go.mod`, and
  `vt-core` as a wasm artifact loaded at runtime (§5.5). Neither gives the daemon a
  source-level dependency on anything else in the package, and neither may grow into one.
  `check-boundaries.mjs` does not police the Go side; the module graph does.

### 4.3 Enforcement

Phase 0 adds a check, run in CI, that fails if:
- any file under `packages/terminal/` contains an import resolving outside the package;
- `ts/renderer-dom` imports `ts/editor` or `ts/completions`;
- `ts/editor` imports `ts/completions`;
- any `packages/terminal` source file exceeds 600 lines.

This is a script under `packages/terminal/scripts/check-boundaries.mjs`, not a
convention. Conventions are how `view.rs` reached 29,236 lines.

---

## 5. Repository integration mechanics

This section exists because this repo has **no npm workspace and no root Cargo
workspace**, and a planner who assumes either will write tasks that do not run.

Verified on 2026-08-29:
- `package.json` (root) has no `workspaces` key; it delegates with `npm --prefix frontend`.
- `frontend/tsconfig.json` has exactly one path alias, `"@/*": ["./src/renderer/*"]`.
- `frontend/vite.renderer.config.ts:78-80` has exactly one alias, `"@" → ./src/renderer`.
- The only `Cargo.toml` outside `node_modules`/`target` is `frontend/src-tauri/Cargo.toml`,
  a standalone package (not a workspace root).

### 5.1 TypeScript packages

`packages/terminal/ts/*` are real npm packages with their own `package.json`,
`tsconfig.json` and vitest config. `frontend/package.json` gains:

```json
"@operator/terminal-react": "file:../packages/terminal/ts/react"
```

npm symlinks it into `frontend/node_modules`. Vite resolves it as a normal dependency.
This is deliberately different from the `packages/shared` relative-import pattern; §4.2
says why.

### 5.2 Rust crates

`packages/terminal/Cargo.toml` is a **new, independent Cargo workspace** containing
`crates/vt-core`, `crates/vt-wasm`, `crates/marks`. It is not joined to
`frontend/src-tauri`, which stays standalone.

Rust toolchain availability is not a new burden: building the desktop app already
requires it (`frontend/src-tauri`, `rust-version = "1.96.0"`).

### 5.3 The WASM build

- Built with `wasm-bindgen --target web`, with an explicit `init(wasmBytes)` entry
  rather than the auto-fetch form.
  *Reasoning:* `--target web` with explicit init loads identically in Vite (via
  `?url` + `fetch`) and in vitest (via `fs.readFile`). Auto-fetch and
  `--target bundler` each work in one and fight the other, and that fight is a
  half-day a planner should not have to rediscover.
- Build command: `npm run build:wasm` inside `packages/terminal`, producing
  `ts/core/wasm/vt_core_bg.wasm` plus bindings.
- The artifact is **gitignored** and built on demand. `frontend`'s `dev`, `test` and
  `tauri:dev` scripts gain a `pre*` step that builds it if absent.
- Phase 0 must prove the artifact loads in all three environments: Vite dev, vitest,
  and a Tauri release build.

### 5.4 The Go decoder

`packages/terminal/go/marks` is a Go module imported by the daemon. It reads the same
conformance vectors from `packages/terminal/protocol/vectors/` as the Rust decoder.
Its only job is finding mark boundaries and extracting fields — it never renders and
never owns a grid. §7.5.

A **second** Go module, `packages/terminal/go/bootstrap`, ships alongside it: it owns the
shell bootstrap scripts (`shell/`), their `recipes.json`, the `auto` / `osc133-only` /
`off` integration modes and the content hashing that decides when an installed script is
stale. Both are wired into `backend/go.mod` with `replace` directives (`:49`, `:51`), and
both hold the §4.2 rule — they are consumed by module path, and they import nothing from
`backend/`.

### 5.5 The second WASM consumer — added 2026-09-02

`vt-core` now has a **Go** consumer as well as a JS one. The tmux removal needed a VT
emulator inside the daemon's pty-host to answer `GetOutput`, `GetStyledOutput` and
alt-screen state, and the alternative — a second emulator written in Go — was rejected
because two implementations drift silently. So the pty-host runs the same core:

- `packages/terminal/crates/vt-host` is a `cdylib` exposing a plain **C-ABI wasm**
  surface (`vt_render_styled` and friends). It is a sibling of `vt-wasm`, which stays
  `wasm-bindgen` for the browser. The two exist because JS glue is unusable from Go.
- `backend/internal/adapters/runtime/ptyhost/vtwasm/` instantiates that module under
  **`wazero`** (`backend/go.mod:21`) — pure Go, so `CGO_ENABLED=0` cross-compilation
  survives, which is what four platform binaries from one machine depends on.
- The parser is **passive**: it is fed after the raw broadcast, never before it, so it
  never sits between the agent and the screen. Nothing user-facing reads it. It may lag
  the screen by milliseconds and that is correct.
- It must be resized with the PTY. `vt-core` defaults to 24 rows and only learns its
  height from `resize`; a parser that misses a resize renders a wrong grid, silently.

Two consequences for this spec. First, **§4.2 gained a bullet**: the daemon consumes
`vt-core` through the wasm boundary and must not gain a source-level dependency on
anything else in the package. Second, **CI needs a Rust
toolchain for the Go release builds** — `packages/build-binaries.sh` and the release
workflows install `rustup` and the `wasm32-unknown-unknown` target before the Go build.
`packages/build-binaries.sh:20-26` runs
`cargo build --release -p vt-host --target wasm32-unknown-unknown` and copies
`vt_host.wasm` into place ahead of it. One wasm artifact serves all four binaries, so the
single-machine cross-compile story is intact. The full reasoning is in
`docs/superpowers/specs/2026-09-01-tmux-free-pty-runtime-design.md`.

---

## 6. `vt-core` — the data model

### 6.1 Responsibilities

`vt-core` owns: the VT parser, the cell grid, the blockgrid, selection, find, and
redaction. It owns no rendering, no editor, no completions, no I/O, no host concepts.
It is `no_std`-friendly where practical and has zero WASM-specific code — that lives in
`vt-wasm`.

### 6.2 Cell storage — flat content plus run-length attributes

**Do not store a struct per cell.** Copy the shape Warp arrived at in
`crates/warp_terminal/src/model/grid/flat_storage/`, which is three separate structures:

- **Content** (`flat_storage/content.rs`) — a chunked buffer of graphemes keyed by a
  monotonically increasing byte offset. Chunking is what lets scrollback be trimmed off
  the front by dropping a chunk, with no copying and no re-zeroing of offsets. Its
  doc comment describes it as "a non-circular circular buffer, keyed by content offset."
- **AttributeMap** (`flat_storage/attribute_map.rs`) — one per attribute (fg, bg, style,
  hyperlink), stored as a `BTreeMap` from *ending* byte offset to value plus a tail
  value, coalescing equal neighbours into runs. Styling is stored as ranges, not
  per cell.
- **Index** (`flat_storage/index.rs`) — rows mapped to content offset ranges, which is
  where wrapping and resize (`grid_storage/resize.rs`) are resolved.

*Reasoning:* real terminal output has long runs of identical styling. Run-length
attributes make the grid dramatically smaller than a cell-struct array, and the
`BTreeMap` gives both point lookup and forward scanning, which is exactly the access
pattern a renderer has.

**The consequence for the renderer is large and is why this is in the design rather
than left as an implementation detail.** A row read out of this structure is a text
slice plus a list of attribute runs, which maps one-to-one onto DOM spans: the
renderer emits **one span per style run, not one per character**. DOM node count
becomes proportional to style changes rather than to output size. A planner who
instead materializes cells and then groups them has paid twice and lost the property
that makes the DOM renderer competitive.

`vt-wasm` exposes content as typed-array views over WASM linear memory and attribute
runs as a compact `(endOffset, value)` pair array. The DOM renderer reads slices and
**never materializes a JS object per cell**. This is the load-bearing decision that
makes a DOM renderer viable — the pixels can look right and the design still be broken.

**The two-tier shape that the normal buffer needs.** `FlatStorage` is Warp's
**scrollback** tier — its own doc comment rules out `Insert`, listing only `Index`,
`Scan`/`Iterate`, `Push` and `Pop`, and is suited to "grids that are immutable, or the
portion of a grid that cannot be accessed via the cursor"
(`crates/warp_terminal/src/model/grid/flat_storage/mod.rs:11-17`). The
cursor-addressable rows live in `GridStorage`, a mutable buffer of `Row`s; the normal
buffer is the union of the two, and `grid_handler.rs`'s `storage_row()` resolves a row
index across them by comparing against `flat_storage.total_rows()` and returning
`StorageRow::FlatStorage` for the scrollback side and `StorageRow::GridStorage` for the
cursor-addressable side (`grid_handler.rs:2399-2409`). A normal buffer built only
from `FlatStorage` cannot service `CUP`/`IL`/`DL`/`DECSTBM`, and the only way to make
a screen that does service them is to keep both tiers and route through `storage_row()`.

### 6.2a Known limits

One semantic change that callers must know about, and the grapheme storage that closes
the gap the first pass left open.

**Zero-width scalars are carried per cell.** `ScreenGrid::Cell` holds the base scalar
plus an `Option<Box<String>>` that, when present, carries the base scalar followed by
every zero-width scalar attached to it. That is the shape of Warp's
`CellExtra::cell_with_zero_width` (`crates/warp_terminal/src/model/grid/cell.rs:114-122`):
the accumulated grapheme is stored joined so a read never allocates to concatenate it,
and it is boxed so the common cell stays two words. Accumulation is capped at
`MAX_GRAPHEME_BYTES = 256`, matching Warp (`cell.rs:33`); past the cap further scalars
are dropped rather than growing a cell without bound. The owning cell is resolved the
way Warp resolves it (`grid/ansi_handler.rs:201-215`): the column before the cursor
unless a wrap is pending, stepping back once more off a wide-character spacer so a mark
lands on the base of a wide character rather than its continuation cell. A cell holding
only a space plus marks is **not** blank, so trailing-blank trimming must test the cell
rather than its base scalar.

**`scrollback` bounds history, not history plus screen.** `createTerminalCore({
scrollback: 5000 })` retains 5000 history rows *plus* the live screen. This matches
Warp, where `max_scroll_limit` applies to `FlatStorage` and `total_rows()` is
`flat_storage.total_rows() + grid_height`. It is a semantic change visible to any
consumer of the row count: the previous behaviour counted the live screen against the
budget, and any caller that sized a backing store off the returned row count must
revisit that math.

### 6.3 The blockgrid and its sum tree

A block is a half-open range over the scrollback plus its metadata:

```rust
pub struct Block {
    pub id: BlockId,
    pub command: Option<String>,
    pub cwd: Option<PathBuf>,
    pub git_branch: Option<String>,
    pub exit_code: Option<i32>,
    pub started_at: Option<Timestamp>,
    pub finished_at: Option<Timestamp>,
    pub rows: RowRange,
    pub state: BlockState,
    pub source: BlockSource,
}

pub enum BlockState { Running, Finished, Abandoned }
pub enum BlockSource { Osc133, Extension, Synthetic }
```

`BlockSource` is required, not decorative: it is how the UI and the tests distinguish a
zero-setup OSC 133 block from a fully-instrumented one (§7.2), and `Synthetic` covers
output that arrived with no marks at all (§7.4).

The block list is a **sum tree**: a B-tree whose internal nodes cache subtree summaries
of `{ block_count, row_count, byte_count, height_px }`. This makes O(log n):

- which blocks intersect a scroll range (the renderer's hot query);
- total content height;
- scroll-to-block and block index lookup;
- find result positioning across the whole scrollback.

Without it, DOM virtualization is fine at 500 blocks and collapses at 50,000, and the
collapse will be misattributed to the DOM. Warp reached the same conclusion — §3.7.

`height_px` is a summary the renderer writes back after measurement; the core stores it
and never computes it, because the core has no fonts.

### 6.3b Crate choices for `vt-core`

Evidence-backed, from Warp's own manifests:

| Need | Crate | Evidence |
| --- | --- | --- |
| VT parsing | `vte` | `Cargo.toml:347`; `crates/warp_terminal/Cargo.toml:61`; `model/ansi/mod.rs:4` calls their `Processor` a wrapper around Alacritty's `VteParser` |
| find | `regex-automata` | `crates/warp_terminal/Cargo.toml:43`; used as `RegexDFAs` in `blockgrid.rs` |
| grapheme segmentation | `unicode-segmentation` | `crates/warp_terminal/Cargo.toml:118` |
| display width | `unicode-width` | `crates/warp_terminal/Cargo.toml:56` |
| sum tree | ours | Warp's `crates/sum_tree` is 532 + 1,010 lines and generic over an `Item`/`Summary` pair; small enough to write against our own summary type rather than vendor |

**Use `vte` from crates.io. MUST NOT fork it.** `Cargo.toml:347` shows Warp pinned to
`git = "https://github.com/warpdotdev/vte.git"` at a fixed rev — a permanent
maintenance tax and a dependency no downstream project can audit easily, which matters
for a package meant to be reused (§2.4). If we hit a genuine `vte` limitation, the
first move is an upstream issue; forking needs the user's approval, not a planner's.

### 6.4 Selection

Selection is expressed in block-relative coordinates `(BlockId, row, col)` and can span
blocks. It lives in the core, not the renderer, so that a WebGL renderer later inherits
it unchanged. The DOM renderer maps native browser selection onto it rather than
replacing it, so copy, triple-click and accessibility keep working.

### 6.5 Find

Find runs over the sum tree and returns matches as `(BlockId, row, col_range)`. It must
be incremental and cancellable — a find over a 500k-row scrollback cannot block the
frame. Warp's equivalent is `app/src/terminal/find/model/async_find.rs`.

**Landed in Phase 5 (2026-09-01).** The cursor is rebuilt lazily on every
`findStep` from a borrow of `&self.core`, runs one step within the
`FIND_STEP_BUDGET = 1000` (TS, in `ts/core/src/terminal-core.ts:29`) block budget,
flattens results into the wasm `find_results` buffer, and drops before the wasm
call returns. The literal scan uses `memchr::memmem::Finder` (the `find.rs` doc
comment at line 219 calls this out). The query is held only as the `u32` session id
in JS; no per-block `Vec::clone`.

**Measured numbers (Task 1 bench, `bench/find.bench.ts`, 500k rows, query `row 250000`):**

| Budget | median | p95 |
| --- | --- | --- |
| 1000 (chosen) | ~16ms | **29.60 ms** (under the 100ms gate) |
| 100 (sensitive) | ~14ms | ~13.83 ms |
| 10 (sensitive) | ~13ms | ~13.62 ms |
| `Number.MAX_SAFE_INTEGER` (sensitive) | ~16ms | ~65.30 ms |

**Sensitivity ratio** p95(MAX)/p95(chosen) = 2.14× (from the bench JSON's
`sensitivity` field), above the 1.5× threshold the Task 1 reviewer required to prove
the budget knob matters. The chosen budget is 1000 blocks/step — high enough that a
single scan returns first results in well under the 100ms gate, low enough that the
per-step pause is a small fraction of a 60Hz frame. The next person changing the
budget should expect a single-step scan in the 13–30ms band; a 500ms p95 means the
cursor is cloning again.

**Cancellation:** `findCancel(id)` (wasm) and `core.findCancel(id)` (TS, exposed on
`TerminalCore`) stop the session, return an empty `findResults`, and let the next
`findOpen` reclaim the session id. Tested in `find.test.ts`.

### 6.6 Testing the core

- **Recording replay.** A corpus of raw byte streams under
  `packages/terminal/crates/vt-core/tests/recordings/` replayed against the parser with
  snapshotted grid output. Warp's `app/src/terminal/ref_tests/data/**/*.recording` is
  the model.
- **Fuzzing.** `cargo fuzz` over the parser and over the mark decoder (§7.6), with the
  invariant: no panic, no unbounded allocation, grid stays internally consistent.
- **Property tests** on the sum tree: summaries after any insert/remove/split match a
  naive recomputation.

---

## 7. The mark protocol

### 7.1 Where it lives

`packages/terminal/protocol/` is a top-level directory containing:

- `SPEC.md` — the normative protocol document;
- `vectors/*.json` — conformance vectors: input byte stream plus expected decoded events;
- `fuzz-corpus/` — seed inputs including malformed, unpaired and interleaved marks.

Both decoders (Rust `crates/marks`, Go `go/marks`) are tested against the same vectors.
Changing the protocol means changing the vectors, which fails both decoders at once.
That is the point.

### 7.2 Two tiers

**Tier 1 — OSC 133 + OSC 7, zero setup.** Consumed from any shell already configured
for iTerm2 / VS Code / kitty / WezTerm / ghostty, including over ssh and inside
containers.

| Sequence | Meaning | What we get |
| --- | --- | --- |
| `OSC 133 ; A ST` | prompt start | block boundary |
| `OSC 133 ; B ST` | prompt end / command start | command text start |
| `OSC 133 ; C ST` | command executed / output start | output start |
| `OSC 133 ; D ; <exit> ST` | command finished | exit code |
| `OSC 7 ; file://host/path ST` | cwd | prompt row cwd |

A Tier-1 block has `source: Osc133`. Command text is read from the grid between `B` and
`C`; it may be imperfect (wrapped lines, a prompt that repaints). That is acceptable
and is exactly why Tier 2 exists.

**Tier 2 — our extension, from our bootstrap.** Adds only what 133 cannot express:

| Field | Why 133 cannot carry it |
| --- | --- |
| exact command text | 133 has no command payload; grid-scraping is lossy |
| git branch | not in any standard sequence |
| command duration | 133 gives no timestamps |
| shell kind + version | needed to pick keymap and quoting rules |
| `input-ready` / `input-released` | the explicit line-editor signal replacing Warp's 50ms timer (§3.5, §10.2) |
| block id continuity across resize/reattach | needed for daemon/client correlation |

A Tier-2 block has `source: Extension`.

**MUST:** Tier 2 is strictly additive. Every Tier-2 mark is ignorable — a decoder that
sees only Tier 1 still produces correct, usable blocks. There MUST NOT be a code path
where a Tier-2 mark is required to close a block.

### 7.3 Extension encoding

One encoding, chosen once: `OSC 7000 ; <key>=<value> ; <key>=<value> ST`, values
percent-encoded.

The number `7000` was chosen after checking the allocations we would collide with:
`133` (FinalTerm/semantic prompt, which we consume), `633` (VS Code), `777`
(urxvt/foot notifications, which Warp also handles at
`crates/warp_terminal/src/model/ansi/mod.rs:1032`), `1337` (iTerm2), `9278` (Warp).
It is settled — a planner MUST NOT re-pick it. If a future collision is found, that is
a protocol version bump (§7.3, `v=` key), not a redesign.

*Reasoning:* Warp accumulated three encodings (`'d'` hex-JSON, `'f'` raw JSON, `'k'`
key-value — `dcs_hooks.rs:16-28`) and a session-id field with two meanings for
"legacy". We get one shot at not doing that. Key-value avoids a JSON parser in the Go
decoder and in the shell scripts; percent-encoding avoids quoting bugs across four
shells. Unknown keys MUST be ignored, which is the forward-compatibility story that
replaces adding a fourth encoding later.

The protocol carries a `v=<n>` key. Decoders accept any `v` they understand and ignore
marks with a higher major version rather than failing.

### 7.4 Tolerant parsing — the recovery table

This table is normative. `crates/marks` and `go/marks` MUST both implement it, and the
vectors MUST cover every row.

| Situation | Behavior |
| --- | --- |
| `A` with a block already open | close the open block as `Abandoned`, start a new one |
| `B` with no preceding `A` | start a block at the current row, `source` from the mark tier |
| `C` with no preceding `B` | command text is empty, output starts here |
| `D` with no open block | ignore |
| `D` with a missing exit parameter | `exit_code: None`, state `Finished` |
| `A` immediately followed by `A` | first closes `Abandoned` (this is the fish case, §3.2) |
| unknown OSC 133 subcommand | ignore, do not close or open anything |
| unknown OSC 7000 key | ignore that key, keep the rest of the mark |
| malformed / truncated sequence | ignore the sequence, never drop subsequent bytes |
| output arriving with no marks at all | accumulate into a `Synthetic` block |

**MUST NOT:** assume any mark is paired. §3.2 is what that assumption cost Warp.

### 7.5 The Go decoder's narrow job

`packages/terminal/go/marks` turns the stream into lossless raw spans with absolute byte
offsets as well as decoded mark fields. `StreamDecoder.Feed`, `Flush`, and `ResetAt`
preserve every byte in a contiguous journal run, including ordinary terminal controls
and incomplete sequences at a sealed end. The daemon records the resulting
`CaptureCursor` (`epoch`, segment, offset) only after a completed block commits, so it
can replay an earlier cursor idempotently after a restart.

The decoder does not maintain a grid, render, or own block layout. The capture worker
feeds its raw spans to the block assembler; that worker uses journal gaps to abandon the
partial block, resets the decoder at the retained cursor, and resumes at the next valid
prompt. A gap deliberately does not reset the assembler's alternate-screen state: if an
unobserved leave sequence was lost, capture stays suppressed until a later leave rather
than risk storing TUI repaint bytes. Full terminal rendering still happens where pixels
happen.

### 7.6 Conformance and fuzzing

Phase 1 ships:
- vectors covering every row of §7.4 and both tiers;
- a Rust test and a Go test that both run the vectors;
- a fuzz target over the decoder seeded with `fuzz-corpus/`, including unpaired marks,
  marks split across read boundaries, and marks interleaved with SGR and alt-screen
  switches.

A decoder that passes the vectors but panics on a split-across-reads mark is a decoder
that will fail in production, because PTY reads split wherever they like.

---

## 8. Shell bootstrap — the additive-only contract

`packages/terminal/shell/` holds `zsh.sh`, `bash.sh`, `fish.fish`, `pwsh.ps1`. These
are package-owned assets returned to the host through `spawnRecipe()` (§4.1).

**MUST:**
- register hooks additively (`add-zsh-hook precmd …`, bash `PROMPT_COMMAND` append,
  fish `--on-event fish_prompt`);
- leave the user's rc loading to the shell's own startup; if we need an env var, pass
  it through `SpawnRecipe.env`;
- be a no-op when already loaded (idempotent under subshells and re-exec);
- degrade to Tier 1 if any Tier-2 step fails.

**MUST NOT:**
- remove, reorder or stash the user's hook functions (Warp: `zsh_body.sh:236-242`);
- add or remove any `bindkey` / `bind` binding (Warp: `zsh_body.sh:378-385`);
- reference any third-party prompt framework by name — no `p9k`, no `starship`, no
  `oh-my-zsh` special cases;
- execute any command in the user's session for our own purposes (Warp: `zsh_body.sh:205-208, 254-262`);
- inspect or rewrite the user's ssh arguments (Warp: `bash_body.sh:966-969`).

If a conflict with a prompt framework cannot be solved additively, the correct outcome
is a Tier-1 block, not a special case.

### 8.1 Prompt suppression — a phase 2 act, never a phase 1 one

Because we draw the prompt row (§2.1), the bootstrap can set the shell's prompt to a
minimal sentinel. This is a prompt *variable* assignment — `PS1`/`PROMPT`/`fish_prompt`
— made after the user's config has loaded, and it is reversible: the package exposes a
"show shell prompt" mode that skips it, which is also the fallback when the user's
framework fights us.

**Suppression is off until phase 2, and this is load-bearing.** The prompt row and the
input editor are the same feature seen from two sides: suppressing the shell's prompt
without shipping the editor leaves the user with nothing to type into. Phase 1
therefore ships the bootstrap with suppression **disabled** — the user's own prompt and
readline stay live inside the grid, and we draw block chrome around the commands that
marks identify. That is the iTerm2 / VS Code model, it is a genuinely usable terminal,
and it is what makes phase 1 shippable on its own (§14.0).

Phase 2 flips suppression on in the same change that introduces the editor. A planner
who enables it earlier has broken §14.0.

---

## 9. The renderer

### 9.1 The interface

```ts
export interface BlockRenderer {
  mount(container: HTMLElement, core: TerminalCore): void;
  setTheme(theme: TerminalTheme): void;
  setFont(font: FontConfig): void;
  invalidate(range: RowRange): void;
  measure(): { cellWidth: number; cellHeight: number };
  scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
  dispose(): void;
}
```

`renderer-dom` is the phase 1 implementation. Nothing outside `renderer-dom` may assume
DOM.

### 9.2 Virtualization

Two levels, both driven by sum-tree queries (§6.3): visible blocks, and visible rows
within a tall block. Live DOM is capped at the viewport plus a fixed overscan. Rows are
built from typed-array slices (§6.2).

### 9.3 What DOM buys us — do not throw it away

Native text selection, clipboard, find-in-page semantics, accessibility, ligatures,
font fallback, per-block hover UI. A planner who reaches for a canvas "for the fast
path" inside a DOM block has given all of this up for a micro-optimization. The escape
hatch is a whole-renderer replacement, not a hybrid.

### 9.4 The perf gate

`frontend/perf/scenarios.json` already defines `vtebench`, `large-output` (16 MiB),
`input-latency`, `reconnect`, `cpu-time` and `active-memory`, run by
`frontend/scripts/benchmark-terminal.mjs`. Phase 0 moves an equivalent harness into
`packages/terminal/bench/` so the package owns its own gate, and records the current
xterm numbers as the baseline.

Gate, checked at the end of every phase from 1 onward:

- `large-output` throughput MUST be ≥ the recorded xterm baseline.
- `vtebench` MUST be ≥ 0.9× the xterm baseline (parser work moves to WASM; a small
  regression here is acceptable, a large one is not).
- `input-latency` p95 MUST be ≤ **the recorded xterm baseline plus one 60Hz frame plus
  3.3ms of measurement tolerance** — that is, `baseline + 20.0ms`. **Amended 2026-09-02;
  the original contract was `≤ baseline` and §9.5 records why it changed.** This
  scenario measures the passthrough path on both renderers — keystroke leaves as raw
  bytes, the echo comes back, the parser renders it. The allowance is not slack: the
  paint cap in §9.5 means an echoed byte waits for the next frame like any other PTY
  output, so exactly one frame is the structural cost of the cap and anything beyond it
  is a real regression. Measured p95 at the time of the amendment was 24.80ms against a
  9.00ms baseline, a +15.8ms delta consistent with one frame; the ceiling is 29.00ms.
  **The allowance is additive, not a factor**, so `bench/gate.mjs` needs an `allowance`
  field beside `factor` — see `todo_without_tmux.md` §10.
- `input-latency-owned` p95 MUST be ≤ **16.7 ms**, one frame at 60fps. Once the editor
  owns the line there is no echo and no round trip, so xterm has no comparable
  measurement and a comparison would flatter us for doing less work. The question stops
  being "faster than xterm" and becomes "imperceptible", which is what the budget
  encodes. This scenario is dom-only and MUST NOT be recorded into an xterm baseline.
- Scroll through 50,000 blocks MUST hold 60fps on the reference machine.

**The gate is `npm --prefix packages/terminal run bench:gate`**, which loads the recorded
baseline, applies the rules above, prints each verdict and exits non-zero on any failure.
It MUST NOT be replaced by reading numbers off a report: for most of phase 2 there was no
comparison step at all, and every "the gate passes" claim in that period was arithmetic
done by hand against numbers that turned out to be measuring the wrong thing.

A renderer-specific branch inside a scenario is a defect, not a convenience. If two
renderers cannot be measured by the same code path, that is a signal they are not doing
comparable work, and the answer is a second scenario with its own yardstick — as
`input-latency-owned` is — never an `if` inside the shared one.

If `renderer-dom` misses a gate after honest optimization, that is the trigger for a
WebGL renderer behind §9.1 — not a redesign of core, blocks or editor.

### 9.5 Paint scheduling and row reuse — **landed 2026-08-30**

The gate in §9.4 measures throughput and latency. It does not measure *smoothness*, and
the first raw surface to carry a live agent pane was measurably janky while passing every
gate. Two rules close that, both copied from Warp:

**One paint per frame, at most 60 per second.** `DomBlockRenderer` schedules every repaint
through `requestAnimationFrame` and drops a frame whose timestamp is less than
`1000 / 60` ms after the last painted one (with a 0.25 ms epsilon, because rAF timestamps
are not exactly 16.667 ms apart). There is **no synchronous escape hatch**: the first
implementation painted inline whenever more than 4 ms had passed, which under a chatty
agent redraw meant roughly 250 paints per second, each one fighting the compositor. Warp
caps the same way — `MAX_WAKEUPS_PER_SECOND = 60` and `WAKEUP_THROTTLE_PERIOD`
(`app/src/terminal/view.rs:613-615`), applied as `throttle(WAKEUP_THROTTLE_PERIOD,
wakeups_rx)` (`view.rs:3752-3754`) with trailing-edge coalescing (`app/src/throttle.rs:23-45`)
so the last state in a burst is always the one drawn.

**Repaint only the rows that changed.** `renderAltSurface` keeps a per-surface fingerprint
of each row — the row's slice of `content` and its slice of `stylePairs` — and rebuilds a
row's children only when that slice differs from the previous paint. A full-screen TUI
frame typically rewrites a handful of rows; rebuilding all of them (measured: 46 rows /
506 spans / 1.6 ms median) is the difference between a paint that fits in a frame and one
that does not. The fingerprints live in a `WeakMap` keyed by the surface node, so a
disposed surface takes its fingerprints with it, and a row-count change falls back to a
full replace rather than trying to diff across a resize.

Neither rule may be traded away for a §9.4 number. A renderer that wins `large-output` by
painting more often than the display refreshes has not made anything faster.

**Open, measured 2026-08-30: the frame cap costs `input-latency`, and the two rules are in
conflict.** The paragraph above was written the same morning the cap landed and before the
§9.4 gate was re-run against it. It has since been: `input-latency` p95 went from 9.10ms at
`695223617` to 24.80ms with the cap, and the gate compares against a 9.00ms xterm baseline.
The evidence and the ruling-out of the other candidates are in §14 Phase 4. The median cost
is the `requestAnimationFrame` hop that replaced the synchronous paint path; the tail is the
16.67ms inter-paint deferral.

This is a genuine trade, not a bug to fix quietly. Three options were on the table:

- **Reverting the cap** restores sub-frame echo and brings back the ~250 paints/sec that
  made an agent pane visibly janky — the thing §9.5 exists to prevent.
- **Amending the `input-latency` contract** is defensible on Warp's own architecture: Warp
  throttles **PTY event-loop wakeups**, and its own comment says the channel exists "so that
  we can coalesce successive wakeup events during situations of high throughput (e.g.
  running `yes`)" (`crates/warp_terminal/src/event_listener.rs:19-21`). Echo in passthrough
  arrives over the PTY like any other output, so Warp coalesces it too; Warp's answer to
  input latency is that it *owns* the line editor and never round-trips the PTY. Ours does
  the same, and `input-latency-owned` passes at 8.50ms against its 16.7ms budget.
- **Exempting echo from the cap** is the only option that keeps both numbers, and it is not
  obviously reachable: in passthrough we cannot distinguish an echoed keystroke from any
  other PTY byte without inventing a heuristic §3.5 would warn about.

### DECIDED 2026-09-02 — option 2, amend the contract

**The user's ruling, on evidence the benchmark does not carry: typing feels fine.** The
cap stays; `input-latency`'s contract becomes `baseline + one frame + 3.3ms tolerance`
(§9.4). The reasoning, recorded so this is not re-litigated:

1. **The number measures the case where you are mostly reading, not typing.**
   `input-latency` is the *passthrough* path — a program owns the line and every
   keystroke round-trips the PTY. The path that carries the user's actual typing is the
   owned line editor, and `input-latency-owned` passes at 8.50ms against a 16.7ms budget.
   Warp's own answer to input latency is the same: own the line and never round-trip.
2. **One frame is structural, not sloppiness.** With the cap, an echoed byte waits for the
   next frame like every other PTY byte. The measured +15.8ms delta over baseline is one
   frame, which is what the allowance encodes. It stays falsifiable: a regression past
   29.00ms fails, and 24.80ms sits 4.2ms inside it.
3. **The alternative was worse and measured.** Removing only the inter-paint deferral
   recovers the tail (24.80 → 17.30) but not the median, because the median frame *is* the
   `requestAnimationFrame` hop. Buying 7.5ms of tail back at the price of the jank the cap
   exists to prevent is not a trade worth making.

**What the allowance is not.** It is not a licence to keep loosening. The 3.3ms tolerance
is measurement noise, not headroom, and one frame is the specific cost of one specific
mechanism. If a future change adds a second frame, the answer is to remove the second
frame, not to widen the allowance again. The original instruction stands in amended form:
**do not silence a failure by moving the number.**

**Still to do:** `bench/gate.mjs:39` expresses this rule as a multiplicative `factor`, and
the new contract is additive. Until an `allowance` field lands, `bench:gate` keeps
reporting this scenario red against the old rule. Tracked in `todo_without_tmux.md` §10.
The decision is made; the gate has not caught up with it.

---

## 10. The input editor

### 10.1 What it is

A DOM-based editor at the bottom of the pane: multi-line, command syntax highlighting,
ghost-text history suggestion, Ctrl-R history search, and a completions dropdown. It is
`ts/editor`, it talks to `ts/core`, and it MUST NOT import `ts/completions` directly —
completions arrive through a provider interface registered on the core.

**The dropdown landed in phase 4.** The editor never names the completion engine: it calls
`core.requestCompletions(line, cursor)` and renders whatever arrives on
`core.onCompletions(...)`, and it calls `core.cancelCompletions()` on any edit that would
strand a stale list. The one-way dependency is what makes the rule above enforceable, and
it is enforced — `check-boundaries.mjs` reports `editor must not import completions` and
exits non-zero, verified by sabotage on 2026-08-30.

**Tab changed hands.** Tab was bound to accepting the ghost-text history suggestion; it now
means completion, matching Warp and readline. Ghost text is accepted with `Ctrl-E`, or with
`→` when the cursor is at end of line — off the end, `→` falls back to moving the cursor,
so the key never becomes unavailable for what it normally does.

**Not CodeMirror.** The editor must share cell metrics, theme and font with the block
renderer so the input row is visually continuous with the blocks above it, and it must
render our completion and ghost-text affordances. A general-purpose editor library
brings a second theming system and a second measurement model for a feature surface we
would override almost entirely.

### 10.2 Line-editor ownership

The core exposes:

```rust
pub enum LineEditorState { Owned, Released, Unknown }
```

- `Owned` — the shell's line editor is idle and accepting input. Entered on an
  `input-ready` mark; left on `input-released`.
- `Released` — a program owns the tty. Keystrokes go straight through.
- `Unknown` — Tier-1-only session, or no marks yet. Keystrokes go straight through and
  the editor renders read-only.

**MUST NOT:** infer `Owned` from a timer. §3.5 is what that costs.

In `Unknown`, the pane behaves as a plain terminal with block decorations. That is the
honest Tier-1 experience and it MUST be usable, because it is what every ssh session
and every unsupported shell gets.

### 10.3 Sending a command

On submit, the package sends the command text plus a newline through the transport. It
MUST NOT attempt to synthesize readline editing sequences to manipulate the shell's own
buffer. Multi-line commands are sent as-is; the shell's own continuation handling
applies.

### 10.4 History

History is the package's, sourced from marks (every Tier-1 or Tier-2 block yields a
command), persisted through an optional `HistoryStore` the host provides. The package
MUST NOT read the user's `.zsh_history` — that is the user's file and reading it is a
privacy decision the host makes, not the package.

---

## 11. Alt-screen handoff

When the stream enters the alternate screen (`1049`), block capture suspends and the
pane hands the full area to a raw grid renderer. On leave, blocks resume and the
alt-screen session leaves a single collapsed block recording what ran.

Phase 3 lands the package's own alternate-screen grid as the default raw surface
(`renderer-dom`'s `alt-surface.ts`, painted through the existing `BlockRenderer` seam).
`XtermTerminal.tsx` stays in the tree as a host-flagged fallback
(`VITE_ALT_SCREEN_SURFACE=xterm`) so a regression in the package grid is one flag away
from a working pane. Phase 7 deletes it outright — component, dependencies, theme bridge
and flag — per §13.4.2, which also lists the input work that must land before it can go.

*Why this is not optional.* An agent session — Claude Code, or any TUI harness — enters
the alternate screen on the first chunk of output and never leaves it. Measured on a
live Operator session, 2026-08-29: the first mux frame was
`ESC [?1049h ESC [22;0;0t ESC [?1h ESC = ESC [H ESC [2J`. If xterm owns the alt screen
permanently then the block list, the Warp headers, the block actions and the phase-2
editor are all invisible in the pane the user actually watches, and "it looks like Warp"
is true only of a plain shell. §2.8.

**What the package's raw surface MUST do (phase 3):**

- `vt-core` keeps a second, fixed `rows × cols` grid for the alternate buffer. Entering
  `1049` saves the cursor and switches the active grid; leaving restores both. The
  alternate buffer has **no scrollback** — that is what the alternate buffer *is*, and
  synthesizing one is a bug, not a feature.
- Cursor addressing (`CUP`, `CUU/CUD/CUF/CUB`, `HVP`), scroll regions (`DECSTBM`, `IND`,
  `RI`), erase (`ED`, `EL`) and line editing (`IL`, `DL`, `ICH`, `DCH`) apply to **both**
  buffers, since both are `ScreenGrid`; the only difference between the normal and
  alternate buffers is the **eviction policy** — the alternate buffer discards the row
  it scrolls off the top instead of promoting it to scrollback. These are the
  sequences a full-screen TUI actually uses; a raw surface that renders text but
  ignores them draws garbage. Warp models the same distinction as
  `FullGridClearBehavior::{Clear, Scroll}` (`grid_handler.rs:405`): `Clear` resets
  visible cells in place for TUI-style redraws on the primary grid, `Scroll` preserves
  the normal primary-grid behaviour where full-grid clears and resizes move visible
  rows into scrollback.
- The renderer paints the alternate grid through the same `BlockRenderer` seam, as a
  single full-height region with no block chrome.
- Input in the alternate screen is raw passthrough, exactly as the phase-2 editor
  already does in `Released` (§10.2). The editor is hidden, not disabled-in-place.
- **The wheel goes to the program when the program asked for it.** `vt-core` tracks
  `1006` (SGR encoding) and `1000`/`1002`/`1003` (tracking level) as private-mode state
  and publishes both on the snapshot. When SGR encoding and any tracking level are both
  on — which is what a full-screen TUI with a scrollable pane sets — a wheel event is
  reported as `CSI < 64 ; col ; row M` (up) or `65` (down) at the cell under the pointer,
  so the program scrolls its own pane. Only when the program has *not* asked does the
  surface synthesize arrow keys (`CSI A`/`B`, or `SS3 A`/`B` under application cursor
  keys). Getting this backwards is the shape of a real bug we shipped: an agent CLI read
  the synthesized `CSI A` as "up arrow" and walked its prompt history every time the user
  tried to scroll.
- **Wheel deltas are normalized against the measured cell height, and the remainder is
  kept.** `deltaMode` is one of pixels, lines or pages; pixels are divided by
  `renderer.measure().cellHeight` and pages by the grid height. The fractional remainder
  accumulates across events instead of being truncated away, which is what makes a
  trackpad feel continuous rather than stepping. There is no line cap — capping a burst
  loses scroll distance the user asked for.

*Which buffer an agent pane is actually in — settled twice, and the second answer is
the live one.* The original 2026-08-29 measurement saw `?1049h` in the first mux frame
and concluded agent panes are permanently in the alternate screen. That was true, but
not of the agent: the **tmux client** emitted it, within the first chunk it wrote to its
terminal. A correction on 2026-08-30 recorded that Claude Code driven directly emits no
`?1049` and redraws inline with `CUU`, and read that as a discrepancy to be reconciled
with tmux in the path.

**tmux left the path on 2026-09-02 and the discrepancy resolved in the agent's favour.**
An Operator agent pane is now in the **normal buffer**, redrawing in place with cursor
addressing, and the block chrome is visible in it. The normal-buffer cursor-addressable
grid landed by the 2026-08-30 plan is not a hedge against a future tmux removal — it is
the surface every agent pane uses. The alternate screen is now what it is in any
terminal: `vim`, `htop`, `less`, and any TUI that asks for it.

Nothing in §11's requirements changes. The alternate-screen grid, the shred rule, the
wheel-reporting rules and the no-scrollback rule all still hold for the programs that do
enter it. What changes is the stake: an alt-screen regression no longer blanks the pane
the user watches all day, and a normal-buffer regression now does.

`vt-core` MUST track alt-screen as explicit state, not as a rendering detail; the
daemon-side decoder needs the same signal to suspend capture (§13.2). Phase 1's boolean
is the seam this grows from — it already freezes the block list correctly, and that
behavior MUST survive: a TUI can draw bytes that look like marks, and routing them into
`BlockGrid` would shred the real blocks the shell produced before the TUI took over.

---

## 12. Theming and strings

### 12.1 Theme

`TerminalTheme` is a plain object: 16 ANSI colors plus foreground, background, cursor,
selection, and the block chrome colors. The package ships a Warp-matching default and a
loader for **Warp's own theme file format**, so the ecosystem of Warp themes works
here. Operator passes a theme derived from its skin for the chrome colors only; the
ANSI palette stays the terminal's own per `DESIGN.md:36`.

**Warp's own defaults, for the values we got wrong.** Recorded 2026-08-30 so Phase 6
did not have to re-derive them; the last column is the 2026-09-02 state after the
look-parity commits (`a83e29013` … `fbe04f719`):

| Property | Warp | Ours | Source |
| --- | --- | --- | --- |
| Line-height ratio | `1.2` | ✅ `1.2` — `BlockTerminal.tsx:371` | `crates/warpui_core/src/elements/gui/text.rs:33`, wired at `app/src/settings/font.rs:50-58` |
| Monospace family | `Hack` | ✅ `"Hack", ui-monospace, "SF Mono", Menlo, monospace`, bundled in `renderer-dom/src/fonts` — `BlockTerminal.tsx:369` | `app/src/settings/font.rs:11` |
| Monospace size | `13.0` | `14` package default, host passes its own | `app/src/settings/font.rs:12` |
| Monospace weight | `Normal` | `400` | `app/src/settings/font.rs:13` |
| Grid padding | `16` left, `8` vertical | ✅ carried by `.terminal-block`, not the surface — `styles.css:47-49, 97-100` | `app/src/terminal/view.rs:744, 13098-13099` |

The padding row landed in a shape worth knowing before touching it: `--terminal-padding-x`
and `--terminal-padding-y` are `0px` on the surface and the 16px inset lives on the
**block**, so a hairline block border sits flush and the grid measures against the space
*inside* the padding (`2c700136f`). Sizing the grid off the surface box instead is what
made rows clip.

The package's own `defaultFont()` already used `1.2`; the `1.35` came from
`BlockTerminal.tsx`, which overrode it. Warp also makes alt-screen padding separately
configurable (`alt_screen_padding`, `app/src/terminal/settings.rs:163`) with a carve-out
set for apps that must match blocklist padding — `k9s` and `lazygit`
(`view.rs:603-609`). Copy the setting, not just the number.

### 12.2 Strings

`TerminalStrings` is a flat object of English defaults the host may override. The
package ships no locale files and does not import `react-i18next`.

Operator's side of this is real work, not a formality: every string the package
surfaces through Operator must be added to all eight locale files under
`frontend/src/renderer/i18n/` — `en, zh-CN, ja, ko, es, fr, de, pt-BR` — non-empty and
key-matched. That is Operator's task in the integration phase, not the package's.

---

## 13. Operator integration

### 13.1 Relationship to plan 7

`docs/superpowers/plans/2026-08-28-shell-blocks.md` is historical. Its backend tasks are
superseded by the shipped lifecycle plan
[`2026-08-31-shell-blocks-daemon.md`](../plans/2026-08-31-shell-blocks-daemon.md).

**The production boundary this spec depends on:**
- **The runtime's own capture sink is the server-side capture path.** Since 2026-09-02
  that is `ptyhost`'s capture tee (`ptyhost/capture.go`, armed over
  `MsgCaptureStartReq`), which replaced `tmux pipe-pane`. The requirement is unchanged
  and is what made the replacement non-optional: capture must not read a client
  attachment, because attachment delivery is per client while durable capture must exist
  with zero clients and must not duplicate work with two.
- The stream is captured once, outside client attachments.
- **Windows is no longer the exception.** The spec was written when tmux ran Unix and
  ConPTY ran Windows with `durableBlocks: false` and `ErrCaptureUnsupported`. One runtime
  now runs everywhere, so capture, rendered `GetOutput` and styled output work on all
  platforms. The visible-absence rule that governed the Windows degradation stays as the
  rule for any future capability gap; it currently has nothing to govern.

**Superseded:** the execution steps in the 2026-08-28 plan. Use the amended lifecycle
plan above for the current implementation boundary.

### 13.2 The daemon's job

1. The shell runtime starts `opr pane-capture --dir <daemon-resolved journal directory>
   --epoch <uuid>` as the runtime's capture sink — `MsgCaptureStartReq` to the pty-host,
   which tees raw PTY output into the helper's stdin (`ptyhost/capture.go`). The helper
   owns rotation: one active 1 MiB `.open` segment, at most eight sealed `.ready`
   segments, `gap.json` before pruning, and a manifest when it seals. It remains running
   while the daemon is down, because the pty-host outlives the daemon.
2. The runtime reports `pipeOpen` and `alternateOn` together, over `MsgCaptureStateReq`
   / `MsgCaptureStateRes`, before capture. This replaced tmux's `#{pane_pipe}` /
   `#{alternate_on}` pair and the idempotency problem it existed to solve: `pipe-pane -o`
   was a toggle rather than an atomic start-if-absent, so the `#{pane_pipe}` guard
   supplied idempotency. The host now owns start-if-absent directly, and the supervisor
   still serializes start and stop per handle. Adoption does not start a second helper
   when a live pane already has a sink armed.

   **The capture sink applies back-pressure, and that is deliberate.** `captureSink.write`
   queues through a forwarder goroutine capped at `maxQueuedCaptureBytes` (four read
   buffers); past the cap it blocks. It cannot write straight through, because a slow
   `opr pane-capture` — disk stall, segment rotation — would then stall the host's pump
   and freeze ring append and client broadcast for the whole session. Pinned by
   `TestCaptureQueueIsBounded` and `TestCaptureBackpressureDoesNotStallDelivery`. The
   reasoning is recorded at length in `todo_without_tmux.md` §8.
3. Daemon shell-terminal wiring reaps prior-run terminals and checks current-run
   liveness before passing live records to `terminalcapture.Supervisor.Adopt`. The
   supervisor owns capture workers: an existing pipe resumes its epoch, otherwise a
   fresh epoch starts. It seeds alternate-screen state before consuming bytes and
   excludes repaint payload while alternate mode is on.
4. `terminal_blocks` stores the assembled raw replay and lifecycle metadata. Cursor
   checkpoints advance only after the corresponding record commits; replaying an older
   cursor upserts rather than duplicates. The service retains the newest 100 blocks per
   terminal and the newest 5,000 output lines per block, with an additional 8 MiB raw
   byte safety cap and recorded omission counts.
5. `GET /api/v1/shell-terminals/{handleId}/blocks?limit=100` returns chronological,
   terminal-handle-keyed raw history. Committed blocks can also be published on the
   existing `blocks` mux channel with `blockType: "terminal_block"`, keyed by handle.
6. Explicit close stops the pipe, waits for the helper to seal, drains the journal,
   persists completed/final blocks and the cursor, then destroys the runtime. Graceful
   daemon shutdown drains and detaches without stopping live pipes; adoption on the next
   boot consumes the remaining journal bytes.

### 13.3 The renderer's job

`TerminalPane.tsx` uses `BlockTerminal` for the block surface and retains the existing
mux terminal attachment for live terminal bytes. `useTerminalSession` accepts an
`enabled` gate so a shell terminal can finish restoring durable history before it opens
that attachment.

For a shell terminal, the frontend loads
`GET /api/v1/shell-terminals/{handleId}/blocks?limit=100` first and feeds each decoded
`rawOutput` replay into a fresh core in chronological order. Only after that history
barrier does it attach the live mux stream, so live bytes are newer than the restored
snapshot. The history endpoint is terminal-handle keyed; the existing session
block-event endpoint is not shell-block history and does not return pre-parsed shell
blocks. Tier-2 IDs remain an in-flight reconnect upsert aid, not a cross-barrier replay
deduplication mechanism.

**What landed 2026-08-30, and the three host-side rules it settled.**

*A session opens on the raw terminal.* `defaultSessionViewMode` returned `"raw"` for
every session. It previously returned `"blocks"` for any harness with a block mapper
(`claude-code`, `codex`, `grok`), so all three agents opened on the block view and had to
be switched by hand — and because `sessionViewModeBySession` was in-memory only, never
persisted, that switch was lost on every restart as well as on every new session.

**Superseded 2026-09-02 (`e246a1470`): the view mode is gone entirely.** The toggle,
`defaultSessionViewMode`, `sessionViewModeBySession`, `blocksCoverHarness` and the two
strings behind them are deleted. A session pane is the terminal; the chat UI is the other
half of the screen and renders through `SessionBlocksPane`, which is not a terminal
surface and stays. This lands §13.4's "one session has exactly one terminal surface"
early and from the product side rather than as a phase-7 retirement step — phase 7 still
owes the shell-terminal tabs and xterm.

*`XtermTerminal` runs headless when it is not the surface.* Under the default
(`VITE_ALT_SCREEN_SURFACE` unset), `XtermTerminal` mounts a headless attachment that
satisfies the `onReady` handle and renders nothing, and `useTerminalSession` stops
mirroring bytes into it. Keeping a second full VT parsing and painting the same stream
off-screen is pure waste, and it is exactly the fallback path §13.4.2 will delete; the
flag still swaps the real component back in.

*Geometry is published from the measured surface, never from the fallback's defaults.*
The open call and the post-open resize both use `surfaceGeometry` — the grid the package
surface actually measured — falling back to the terminal handle's `cols`/`rows` only when
nothing has measured yet, and `transport.resize` no-ops until the channel is open. Opening
at an unmeasured 80×24 and resizing afterwards makes the pane render a partial screen for
the first frames, which is what "the terminal not showing full" was.

### 13.4 Retirement (phase 7)

Per plan 7's settled decision 3, one session has exactly one terminal surface. Two
separate removals land in this phase.

**13.4.1 The shell-terminal tabs.** These may go in phase 7, but their current
handle-keyed capture and history ownership does not. The one-session/one-terminal
replacement must migrate the journal directory, supervisor lifecycle, `terminal_blocks`
ownership, history endpoint contract, and `durableBlocks` capability to its replacement
handle; deleting the tabs alone must not delete or session-key that bridge.

**13.4.2 xterm itself.** Phases 1–3 keep `XtermTerminal.tsx` as the alt-screen bridge and
then as a flagged fallback (§11). Phase 7 deletes it. What goes:

| Artefact | Note |
| --- | --- |
| `frontend/src/renderer/components/XtermTerminal.tsx` (1058 lines) and its test | the component |
| `frontend/src/renderer/theme/bridge/xterm-theme.ts` | `skinToTerminalTheme` maps through it today and must map directly instead |
| `import "@xterm/xterm/css/xterm.css"` in `main.tsx`, and the `.xterm*` rules in `styles.css` | |
| the seven `@xterm/*` entries in `frontend/package.json` | |
| `VITE_ALT_SCREEN_SURFACE` and `handsAltScreenToXterm` in `BlockTerminal.tsx` | the escape hatch has nothing left to escape to |
| the `surface` prop on `AltScreenSlot` | the slot collapses to the block list |

**`packages/terminal/bench/adapters/xterm.ts` is NOT deleted, in this phase or any
other.** The §9.4 gate is defined against xterm baselines; deleting the adapter deletes
the only external reference point the renderer is measured against. It is a benchmark
dependency, not a product one.

**Prerequisites. xterm cannot be removed until the package supplies what it currently
supplies.** `XtermTerminal` is not just a renderer — it owns the mux attachment and the
whole input path through the `AttachableTerminal` contract
(`frontend/src/renderer/hooks/useTerminalSession.ts:30`). Measured against that contract
on 2026-08-30, most of it is cheap and one part is not:

- `cols`/`rows` and `onResize` — **already ours.** The measured pane box is the single
  publisher of pty geometry; see §13.4.3.
- `write(data, done)`, `writeln`, `showLatestOutput`, `prepareForActivation` — cheap.
  `core.feed` is synchronous so `done` fires immediately, and the DOM renderer already
  has stick-to-bottom.
- **`onUserInput` is the blocker.** It emits five sources — `keyboard`, `paste`,
  `composition`, `shortcut`, `wheel` — and behind them sit xterm's full key encoder
  (modifiers, function keys, Alt/Meta, ctrl, keypad), bracketed paste, SGR mouse reports,
  IME composition, and the copy/paste/word-nav handler. The package's `mapKey` +
  `passthroughFor` is the *editor's* command set, roughly a dozen keys.

So phase 7 MUST first deliver, in the package: a complete key→bytes encoder honouring
`DECCKM` (phase 3 has this) and `DECKPAM`; **bracketed paste (`?2004`)**; **mouse
reporting (`?1000`/`?1002`/`?1003`/`?1006`)**; and IME composition. The first three are
`vt-core` mode tracking that phase 3 deliberately scoped out (§2.5 of the phase 3 plan).
A phase 7 that deletes `XtermTerminal.tsx` without them ships a pane that cannot paste,
cannot be clicked in, and mis-encodes half the keyboard.

**Three of those four landed ahead of phase 7, on 2026-09-02.** Recorded here so phase 7
scopes against the tree rather than against this paragraph as first written:

| Prerequisite | State |
| --- | --- |
| key→bytes encoder | ✅ `ts/editor/src/encode-key.ts` with its test — `4b31952aa`, "encode the key the user pressed for a child process". `DECKPAM` coverage still to be confirmed against the encoder's table. |
| bracketed paste `?2004` | ✅ tracked in `vt-core` (`parser.rs:145`, surfaced on the snapshot as `bracketedPaste`, `terminal-core.ts:138`) and consumed by `ts/editor/src/paste.ts` — `7b36b82c9`, "make Cmd+V paste reach the terminal again". |
| mouse reporting `?1000`/`?1002`/`?1003`/`?1006` | 🟡 wheel reporting is complete (§11, phase 3). Click and drag reporting are not; that is what "cannot be clicked in" still means. |
| IME composition | ⬜ untouched. |

Selection came along with them and is not on this list because xterm never supplied it:
`4bf497c9d` and `fbe04f719` paint selection per row the way Warp does, and `90d06f15c`
restored transcript selection.

**13.4.3 One geometry publisher.** Settled 2026-08-30 while xterm was still mounted, and
it stays true after removal: the measured pane box is the only thing that sizes the pty.
The failure it fixes is worth recording, because it is easy to reintroduce — a mounted
xterm inside a `hidden` slot reads its container through `getComputedStyle`, which under
`display: none` returns the *specified* `100%` rather than a resolved box; `FitAddon`
parses that as 100px and proposes **12 columns**, which it then published to the real pty.
Every full-screen TUI drew into a 12-column sliver. Warp resolves the same problem the
same way: one `SizeInfo` built from the pane size and pushed to grid and pty from a single
place, with `crates/warp_terminal/src/runtime.rs:36-44` explaining that rows must come
from the pane and never from whichever element happens to be measuring.

**`XtermTerminal.tsx` goes here too, along with the `@xterm/*` dependencies** — but only
once phase 3's alternate-screen grid has shipped and been used (§2.8, §11). Removing it
before that leaves full-screen TUIs with no surface at all. The xterm bench adapter in
`packages/terminal/bench/adapters/xterm.ts` **stays**: the §9.4 gate is defined against
recorded xterm baselines, and deleting the thing we measure against would make the gate
unfalsifiable.

This is last so a revert costs nothing before it.

---

## 14. Phases

Each phase is a separate implementation plan. §0.3 applies.

### 14.0 The usable cutline — read before planning any phase

The nine phases are not nine steps toward a first working terminal. There are two
lines that matter, and every phase must respect them.

**Phases 0 + 1 = a terminal that works and ships.** At the end of phase 1, Operator's
session pane is a real terminal: it runs any command, it runs a full-screen TUI through
the alt-screen surface, it runs an agent CLI such as Claude Code end to end, and it
draws Warp-style block chrome around commands using marks. The user's own shell prompt
and readline are still doing the typing (§8.1). Nothing after phase 1 is required for
the terminal to be *used*.

**Phases 0 + 1 + 2 = it feels like Warp.** Phase 2 replaces readline with our editor
and turns prompt suppression on. This is where the product identity lands.

**Phase 3 is what makes the agent pane ours.** It is not enrichment. A session running
an agent CLI sat in the alternate screen from its first chunk of output, so until
phase 3 landed, everything phases 1 and 2 built was invisible in that pane and xterm was
what the user was looking at. §2.8, §11.

*Why this reads in the past tense.* The alternate screen was the agent pane's buffer
because tmux put it there, and tmux was deleted on 2026-09-02 (§0.7). Agent panes are now
in the normal buffer. Phase 3 was still the right call and its grid still carries every
full-screen TUI — but the argument above is history, and the sentence a later reader
needs is the one in §11: an alt-screen regression no longer blanks the pane the user
watches all day.

**Phases 4–8 are enrichment.** Completions, navigation, chrome, retirement and mobile
each make it better; none of them is load-bearing for a working terminal. If work stops
after any of them, what exists still works.

Three consequences a planner MUST honour:

- **Phase 1 MUST be independently shippable.** No phase-1 task may leave the terminal
  unusable pending phase 2. The specific trap is prompt suppression — §8.1, and §15
  item 16.
- **Phase 2 MUST NOT be partially adopted.** Suppression and the editor land together
  or neither lands.
- **Phase 3 MUST NOT delete `XtermTerminal.tsx`.** It ships the replacement and leaves
  the old surface reachable behind a host flag; deletion is phase 7, after the new
  surface has carried real use. §13.4.

### Phase 0 — Skeleton and gate

**Deliver:** `packages/terminal` workspace (npm packages per §5.1, Cargo workspace per
§5.2); the WASM build proven in Vite dev, vitest and a Tauri release build (§5.3); the
boundary-check script (§4.3); the bench harness in `packages/terminal/bench/` with
xterm baselines recorded; a `vt-core` that parses a byte stream into a grid and paints
one block.

**Accept when:**
- `npm --prefix packages/terminal run build:wasm` produces the artifact from a clean tree;
- the same WASM module loads in all three environments, proven by a test in each;
- `check-boundaries.mjs` passes and fails correctly on a deliberately bad import;
- `packages/terminal/bench` records baseline numbers for `vtebench`, `large-output` and
  `input-latency` against today's xterm;
- `npm run frontend:typecheck` and `npm run lint` pass.

### Phase 1 — Blocks

**Deliver:** `vt-core` parser, flat cell grid, blockgrid with sum tree, selection, and
the find *engine* (§6.5 — the find UI is phase 5, but the engine ships here because the
sum tree it queries is built here and retrofitting it later means rewriting it);
`crates/marks` and `go/marks` with the §7.4 recovery table, vectors and fuzz target;
`shell/zsh.sh` per §8 **with prompt suppression disabled** (§8.1); `renderer-dom` with
two-level virtualization; Warp-style block headers carrying the block's metadata (cwd,
branch, exit code, duration); per-block selection, copy and hover actions; alt-screen
handoff to `XtermTerminal`; daemon capture publishing on the `blocks` channel (via
`pipe-pane` as shipped; the runtime's own capture sink since 2026-09-02, §13.2); the pane
mounted in Operator per §13.3.

The live input in phase 1 is the user's own shell prompt and readline, rendered in the
grid. We draw chrome around blocks, we do not yet own the typing. §14.0.

**Accept when:**
- **a shell with only OSC 133 configured, and no bootstrap, produces correct blocks** —
  this is a phase 1 test, not a later nice-to-have (§2.6);
- every row of the §7.4 recovery table has a passing vector in both decoders;
- the fuzz target runs clean on the seeded corpus including split-across-read marks;
- a session with no client attached records blocks, and a session with two clients
  attached records each block exactly once;
- entering and leaving `vim` suspends and resumes capture, leaving one collapsed block;
- **the terminal is usable as the daily driver**: mounted in Operator, it runs an
  interactive shell, a full-screen TUI, and an agent CLI (Claude Code) end to end, with
  the user's own prompt and readline intact (§14.0);
- the §9.4 gate passes;
- scrolling 50,000 blocks holds 60fps.

### Phase 2 — Input

**Status: complete as of 2026-08-30.**

**Deliver:** `ts/editor`; **prompt suppression turned on, in the same change** (§8.1)
together with the Warp prompt row that replaces it; `input-ready`/`input-released`
marks and the `LineEditorState` machine (§10.2); command syntax highlighting; multi-line; ghost-text
history; Ctrl-R; edit-and-rerun from a block; `shell/bash.sh` and `shell/fish.fish`.

**Accept when:**
- no timer anywhere decides line-editor ownership — grep for a delay constant in the
  ownership path returns nothing;
- a Tier-1-only session is fully usable with the editor read-only in `Unknown`;
- fish specifically works **without** disabling its OSC 133 (the §3.2 regression test);
- the editor never *submits a command* while a program owns the tty: in `Released` and
  `Unknown` the editor is read-only and keystrokes pass straight through to the program
  (which is correct — that is how you interact with it). The guarantee is that no
  timer-driven path can inject a line into a running program;
- the §9.4 gate still passes, `input-latency` included.

### Phase 3 — The alternate screen — **landed 2026-08-30**

**Deliver:** the alternate-screen grid in `vt-core` per §11 — second grid, saved cursor,
cursor addressing, scroll regions, erase and line editing; the raw surface in
`renderer-dom` behind the existing `BlockRenderer` seam; the alt-screen slot switched
from `XtermTerminal` to the package's own surface; raw input passthrough while the
alternate screen is active.

**Accept when:**
- `vim`, `htop` and `less` render correctly, including window resize and `less`'s
  scroll-region use — verified by running them, not by unit tests alone;
- an agent CLI (Claude Code) runs end to end in the package's own surface with
  `XtermTerminal` unmounted;
- entering and leaving the alternate screen leaves exactly one collapsed block, and the
  blocks recorded before entry are byte-identical afterwards (the §11 shred rule);
- the alternate buffer has no scrollback: scrolling up in a full-screen TUI moves
  nothing, matching every other terminal;
- `XtermTerminal.tsx` is still present and still reachable behind a host flag, so a
  regression is one flag away from a working pane — its deletion is phase 7;
- the §9.4 gate still passes.

**Correction recorded by Task 11 (2026-08-30 plan).** The "an agent CLI (Claude Code)
runs end to end in the package's own surface" criterion above was signed off on the
assumption that Claude Code drives the alternate screen; a fresh capture on 2026-08-30
showed Claude Code emitting no `?1049` and no OSC 133, and redrawing inline with
`CUU`. The 2026-08-30 plan (this one) closes the gap: §6.2 records the
`FlatStorage` + `GridStorage` split and the 2026-08-30 work landed the
cursor-addressable rows that an inline-redrawing TUI needs, including the zero-width
scalar regression in §6.2a and the scrollback semantic change in §6.2a.

**Status 2026-08-30, end of day.** The 2026-08-30 plan landed in full (`255770fbd`
through `4f2b6d62d`), and four follow-ups landed on top of it, each recorded in the
section it changed: the zero-width scalar regression closed with Warp's per-cell grapheme
storage (`4fa3c00a2`, §6.2a); wheel events reported to a mouse-tracking pane, and panes
opened at the measured grid (`b2ce3f9cc`, §11 and §13.3); sessions opening raw with a
headless `XtermTerminal` (`ac9236563`, §13.3); and the paint-scheduling and row-reuse
rules that fixed the jank (`ac9236563`/`d45009946`, §9.5). The correction above was itself corrected in §11 — an
agent pane *is* in the alternate screen, because tmux puts it there — and that second
correction expired on 2026-09-02.

**Final answer, 2026-09-02.** tmux is deleted (§0.7). No tmux client means no injected
`?1049h`, and Claude Code's own bytes are what reach the renderer: it stays in the
**normal buffer** and redraws inline. So the 2026-08-30 capture was right about the agent
all along, and the cursor-addressable normal-buffer rows it motivated are now the agent
pane's production path rather than a hedge. Phase 3's third accept criterion — "an agent
CLI runs end to end in the package's own surface" — is still met, but through the primary
grid, not the alternate one. Do not re-derive this a fourth time: `?1049` in a capture
tells you what the *outermost* program in the pane wants, and until 2026-09-02 that
program was never the agent.

### Phase 4 — Completions — **landed 2026-08-30**

**Deliver:** `ts/completions`; the provider interface on the core; path, flag and git
subcommand providers; fuzzy ranking; the dropdown UI; a declarative spec format for
per-command completions.

**Accept when:**
- no completion path executes anything in the user's shell (§3.6);
- completions are cancellable and never block a frame;
- the spec format has at least three commands defined in it and a documented schema;
- the §9.4 gate still passes.

**Landed.** All eleven tasks of the 2026-08-30 plan, `f0a215893` through `0426591db`.
281 tests across five packages, `check:boundaries` clean. The engine is
`ts/completions`: a signature format and registry, a cursor-location resolver
(`Command`/`Flag`/`Argument`, after `LocationType` at `completer/engine/mod.rs:35-58`),
a smart-case matcher, Warp's four-tier ranking, the path/flag/command providers, and
frame-budgeted ranking. `cd`, `git` and `docker` ship as specs; the schema is
`ts/completions/SPEC.md`.

**Three deviations from Warp that outlive this phase.**

1. **No generators.** Warp's fourth `ArgumentValue` variant runs a shell script —
   `GeneratorFn::ShellCommand { script, post_process }`, "a sh command"
   (`signatures/v2/mod.rs:104-118`). Those are the jobs `zsh_body.sh:254-262` hunts down
   in `warp_preexec`, and §3.6 forbids them. Our union has three variants and no fourth,
   so the first accept criterion is structural rather than a rule to remember. The cost is
   real and should be stated: `git checkout <branch>` cannot offer your actual branches.
   Restoring that needs a §3.6 decision, not a quiet addition.
2. **The fuzzy scorer is ours.** Warp calls `SkimMatcherV2`
   (`crates/fuzzy_match/src/lib.rs:81-83`). It cannot be linked from TypeScript and the
   crate is not vendored into the Warp checkout, so its constants were not readable and
   were not invented. `ts/completions/SPEC.md` documents the five constants we do use.
   What is copied is Warp's observable **smart-case rule**.
3. **`LocationType::Variable` is deferred.** Warp completes `$VAR`; `locate` returns
   `null` for a `$`-prefixed token, so the behaviour is defined rather than accidental.

**The §9.4 gate is red, and phase 4 did not make it red.** `input-latency` fails at
p95 24.80ms against a 9.00ms xterm baseline. Measured on 2026-08-30, same machine, same
scenario configuration:

| Build | median | p95 |
| --- | --- | --- |
| `695223617` (phase 3 merge, before the paint throttle) | 8.20 | 9.10 |
| pre-phase-4 `ts/editor` + `ts/core`, paint throttle present | 16.40 | 24.50 |
| phase 4 at `0426591db` | 16.40 | 24.80 |

Checking out the pre-phase-4 editor and core and rebuilding reproduces the failure
exactly, so the regression entered with the paint throttle in `ac9236563` (§9.5), not with
completions. System load was ruled out — 16.40 at load 3.6 matches 16.50 at load 6.46.
Removing only the inter-paint deferral recovers the tail (24.80 → 17.30) but not the
median: the median frame is the `requestAnimationFrame` hop itself, which is what replaced
the old synchronous paint path.

Phase 4 is therefore accepted with the gate inherited red, and the regression is carried as
an open §9.5 item rather than attributed here. Two things a later reader should not do:
loosen the `input-latency` factor to 1.1 — 24.80 is 2.75× the baseline, so it would not
pass anyway — or "fix" the editor, whose per-keystroke cost in passthrough is one
`isOpen()` check and which measures identically when removed entirely.

### Phase 5 — Navigation — **landed 2026-09-01**

**Deliver:** command palette; block find, filter and bookmark; sticky command header;
jump-to-block; the full block action menu.

**Accept when:** find across a 500k-row scrollback returns first results under 100ms and
is cancellable; every action is keyboard-reachable; the §9.4 gate still passes.

**Landed.** All eight tasks of the 2026-08-31 plan
(`docs/superpowers/plans/2026-08-31-warp-terminal-phase-5-navigation.md`),
`0d97f9704` through `78451230c` (plus 7 Task 1 commits and 1 fix round). 149 tests in
`ts/renderer-dom` (was 99 before the phase — +50), 281 tests across the workspace,
`check:boundaries` clean, `smoke:vite` green in real Chromium.

**What ships, by task:**

- **Task 1 (find engine, 7 commits).** The find cursor is rebuilt lazily on every
  `findStep` from a borrow of `&self.core`, runs one step within the budget, and
  drops before the wasm call returns. JS never holds the cursor — it holds the
  `u32` session id. The literal scan uses `memchr::memmem::Finder`. The bench
  proves the gate: 29.60ms p95 at the chosen `FIND_STEP_BUDGET = 1000`, well
  under the 100ms ceiling. Numbers tabulated in §6.5.
- **Task 2 (find bar UI).** `createFindBar({ core, renderer, host, strings })`
  returns a `FindBar` handle with `mount`, `open`, `close`, `dispose`. Cmd/Ctrl+F
  opens it; typing runs the find session; Enter walks forward, Shift+Enter
  backward, Escape closes and restores focus. Match-in-below-the-fold is
  `host.scrollToBlock(match.blockId, "center")` — the find bar does not own
  scroll; the renderer's `scrollToBlock` does.
- **Task 3 (sticky command header).** The pinned header is the first child of
  the host, `position: sticky; top: 0`. The brief said sticky would not survive
  `contain: strict` — real Chromium in the smoke harness proved the opposite,
  and the absolute-position alternative failed because absolute children of
  `overflow: auto` containers position at the content origin, not the padding
  box. Deviation recorded in §17.4.
- **Task 4 (jump-to-block).** `mountBlockNav` listens on the renderer's container
  for Cmd/Ctrl+ArrowUp/ArrowDown, walks the filtered block list, and calls
  `scrollToBlock(id, "center")`. Inert when `isAltScreenActive()` is true; the
  first test in `block-nav.test.ts`. Module lives in `ts/renderer-dom/src/block-nav.ts`
  — *not* in the line-editor keymap — because the brief's `keymap.ts` is for
  line-editor commands only (the same pattern as `find-bar.ts`).
- **Task 5 (filter and bookmark).** `applyFilter(blocks, filter)` is a pure
  function in `block-filter.ts`; it never mutates the input array and never
  reorders, evicts, or renumbers `BlockId`s — filter is a view, never an edit.
  `core.setBlockBookmarked(id, bool)` and `core.blockBookmarked(id)` are the
  bookend API; the host owns persistence. Bookmark bit lives at position 17 of
  the packed state-source-hasexit-bookmarked word (§6.3b). The Rust `BlockTree::find`
  is `O(n)` over the closed tree; deferred to a future perf-gate iteration.
- **Task 6 (full block action menu).** `renderBlockActions` emits up to seven
  buttons: copy-command, copy-output, share-output, bookmark, filter-to-command,
  jump, rerun. Each action is a real `<button>` with `aria-label`; rerun fires
  `RERUN_EVENT`, the other four new actions fire `BOOKMARK_EVENT`,
  `FILTER_COMMAND_EVENT`, `JUMP_EVENT`. Synthetic blocks only get copy-output.
  The `does not call any host capability that can execute commands` test pins
  §3.6: `openLink` and `notify` spies are asserted to never be called, and
  `HostCapabilities` itself has no `execute` or `spawn` method
  (`ts/core/src/types.ts:194-200`).
- **Task 7 (command palette).** `mountPalette({ container, getCommands, isAltScreenActive, strings })`
  opens on Cmd/Ctrl+Shift+P, lists package- and host-defined commands, and
  supports type/arrow/Enter/Escape. Substring filter, not prefix — `includes`,
  not `startsWith` — a strict superset. The first test in `palette.test.ts`
  is alt-screen inertness, matching the brief's hard requirement. `isAltScreenActive()`
  is checked in *two* places: the keyboard listener and `open()`, so even a
  programmatic `open()` while the alt screen is active is a no-op.
- **Task 8 (this section).**

**Deviations from the brief, recorded plainly so the next reader does not re-open them.**

1. **The find cursor is rebuilt on every step, not held across wasm calls.** The
   brief specified the cursor would live on the JS side; the first implementer's
   `OwnedFindCursor` cloned the entire 500k-block content at `findOpen`. The
   rebuild-per-step shape is the one that actually hits the gate, and JS never
   needs to hold a cursor — it holds the `u32` session id. The trade: mutation
   between steps is tested explicitly in `find.test.ts` (the borrow-cannot-cross-wasm
   trap), and a future find that needs cross-step mutation state can stash it on
   the `&mut WasmTerminalCore` itself.
2. **The pinned header is `position: sticky`, not `position: absolute` as the
   brief first read.** The brief said sticky would not survive `contain: strict`
   on the host. Real Chromium in `smoke:vite` says the opposite: sticky works
   when the pinned element is the *first child* of the host. Switching to sticky
   AND making the pinned the first child put the natural flow top at y=0, where
   sticky pins. The absolute alternative failed because absolute children of
   `overflow: auto` containers position at the content origin (which scrolls
   with the content), not at the host's visible top. **§17.4 cites this.**
3. **Block navigation and the palette live in `ts/renderer-dom/src/`, not in
   `ts/editor/src/keymap.ts`.** The brief listed `keymap.ts` for both. The
   line-editor keymap is for line-editor commands only, and adding a
   `kind: "block-nav"` or `kind: "open-palette"` to `EditorCommand` would force
   the line editor to handle commands the line editor should never see. The
   renderer-level chords (Cmd/Ctrl+Arrow, Cmd/Ctrl+Shift+P) are owned by the
   modules themselves, attached to the renderer's container, not the line
   editor's root. Same ruling in both tasks.
4. **The package does not ship a default command list for the palette.** The
   brief said the package "registers its own commands (find, filter, bookmark,
   jump, the block actions)". The package instead ships the open/close/type/arrow
   mechanism, and the host supplies the command list via
   `getCommands: () => readonly PaletteCommand[]`. The reasoning: reaching
   `findBar` or `setFilter` from the palette would force the package to expose
   its private machinery, and the host is the right place to compose the list.
   A `createDefaultPaletteCommands(deps)` factory is the right extension if
   hosts want a drop-in default.
5. **Substring filter, not strict prefix.** The pre-flight ruling said "prefix
   match for the palette". The implementation uses `label.toLowerCase().includes(needle)`,
   a strict superset of `startsWith`. A user typing "book" matches "Bookmark" —
   that's what users expect from VS Code, Sublime, and Warp. A future test
   wanting strict prefix is a one-line change in `palette.ts:88`.
6. **Every Task 3-8 dispatch died.** The Cloudflare provider returned `402
   Provider returned error` for every subagent dispatched in this session, after
   the same pattern from the previous session. Per the prior ruling in the
   `progress.md` ledger ("controller does the implementation, controller does
   the review"), every Task 3-8 implementer and reviewer was the controller.
   Output is reviewable: 5–19 files per task, all green, with self-reviews
   named in the SDD workspace. A future session with a recovered provider
   can re-dispatch any of these tasks for a second pair of eyes; the work
   is on `phase-5-navigation` and ready.

**Status 2026-09-01, end of phase.** The eight tasks landed in order, each with
its brief → report → review → ledger entries under
`.superpowers/sdd/2026-08-31-warp-terminal-phase-5-navigation/`. The Phase 5
deliverable list above maps 1:1 onto the spec's "Deliver" line; the eight
"Accept when" criteria are met. The §9.4 gate is not re-measured here — that
is a separate harness (`bench/`) and is owned by the next phase that touches
input latency. Phase 6 is unblocked.

### Phase 6 — Chrome and configuration — **look parity landed; the rest deferred 2026-09-02**

**Deliver:** the theme system with Warp theme-file loading; font and ligature settings;
splits and panes; scrollback persistence and restore.

**Deferred here on 2026-08-30, from a look-comparison against Warp.** Phase 3 delivered
the alternate-screen *grid*, not Warp's *look*, and a side-by-side found four gaps. The
first three are wrong values, not missing machinery, and their Warp-side numbers are
tabulated in §12.1: the host passes line-height `1.35` where Warp uses `1.2`; the grid
has no padding where Warp pads 16px left and 8px vertical; and the font is the system
monospace stack rather than Hack 13. The fourth is not understood: in a live agent pane
the bottom row rendered clipped with the TUI's input composer missing, which
`Math.floor(clientHeight / cellHeight)` in `TerminalSurface.tsx:118` should make
impossible — it under-fills, it cannot clip. That one needs reproduction before a fix,
and it may not belong in this phase at all.

What was checked and is **correct**, so nobody re-opens it: a full-screen TUI renders as
a plain grid with no block chrome. That is §11, and it is what Warp's own
`AltScreenElement` does (`app/src/terminal/view.rs:24363`). "No blocks in the agent pane"
is not a defect.

**Accept when:** a stock Warp theme file loads and renders; a restored session shows
its prior blocks with correct metadata; the four deferred items above are each fixed or
explicitly re-deferred with a reason; the §9.4 gate still passes.

**Status 2026-09-02 — the four deferred items are closed; the phase's own deliverables
are not.** The look-parity work ran as
[`2026-08-31-warp-look-parity.md`](../plans/2026-08-31-warp-look-parity.md), landing as
`a83e29013` … `fbe04f719`. That plan's checkboxes were never ticked — read the tree, not
the plan file.

| Deferred item | State |
| --- | --- |
| line-height `1.35` → `1.2` | ✅ `BlockTerminal.tsx:371` |
| no grid padding → Warp's 16px / 8px | ✅ carried by `.terminal-block` (`093791034`, `db0a09305`); see §12.1 for why it sits there and not on the surface |
| system monospace → Hack 13 | ✅ Hack bundled in `renderer-dom/src/fonts`, `BlockTerminal.tsx:369`. The `13` size is still host-supplied against a package default of `14`. |
| the unexplained clipped bottom row | ✅ reproduced and fixed, and it was two bugs, not one: blocks reserved height for rows a redraw had erased (`18dc9331e`), and the grid was measured against the surface box rather than the space inside the block padding (`2c700136f`) |

Landing alongside them, in the same window and not on the deferred list: the block list
anchored to the bottom of the pane (`0280b48e2`), the primary-screen cursor (`d12311401`),
Warp's kill-line on Cmd+Backspace (`e6b05bd8c`, `20f716c3e`), Cmd+V paste
(`7b36b82c9`), Warp-style selection painting (`4bf497c9d`, `fbe04f719`), and the line
editor hiding its prompt while a child owns the line (`cd9e9f0a2`). The three that touch
input and paste are phase-7 prerequisites arriving early — §13.4.2 tracks them.

**Deferred by the user, 2026-09-02.** The phase's own four deliverables were written on
2026-08-29, before anyone had used the terminal daily. Having used it, none of them is
what stands between the pane and "good" — §14.0's own ruling that phases 4–8 are
enrichment is the license, and the four *deferred look items* above were this phase's
load-bearing half and are closed. The remaining four are re-scoped rather than dropped:

| Deliverable | Disposition |
| --- | --- |
| Scrollback persistence and restore | **Moved into phase 7.** It was already half-required there: §13.4.1 makes retiring the shell-terminal tabs conditional on migrating the journal directory, supervisor lifecycle, `terminal_blocks` ownership, history endpoint contract and `durableBlocks` capability to the session terminal's handle. That migration *is* durable block history owned by the session rather than a tab, which is this deliverable wearing a different hat. Doing it inside phase 7 is one piece of work instead of two. |
| Warp theme-file loading | Deferred, no phase. `renderer-dom/src/theme-warp.ts` ships `warpDarkTheme` — Warp's bundled dark palette transcribed with citations — and the host does not yet consume it. A *loader* for Warp's theme file format is unbuilt. Nothing downstream needs it. |
| Font and ligature settings | Deferred, no phase, and the shape of the ask changed: `c9c7f71d9` deleted the font stepper deliberately, so "settings" now means a preferences surface, not a toolbar control. That is a product decision, not a terminal one. |
| Splits and panes | Deferred, no phase, and **flagged rather than merely postponed**: Operator already has a session model with its own pane layout, and §0.6 forbids refactoring it. Whether the package should own splits at all needs a user decision before it needs a plan. |

*Do not treat this as phase 6 being "done".* It is deferred with its remainder placed. A
future reader who wants theme files or splits picks them up from this table; they do not
belong to a numbered phase any more.

**The §9.4 gate is inherited red from phase 4 and has not been re-measured.** It is not a
phase 6 debt and deferring the phase does not discharge it — the §9.5 decision is
outstanding regardless of what happens to the phase numbering.

**What the deferral does not touch: scroll.** Phase 6 was never the scroll story and no
reader should look for it here. Scroll smoothness was fixed by the tmux removal (§0.7),
§9.5's paint scheduling, and §11's fractional wheel-delta accumulation — all landed, and
confirmed good in real use by the user on 2026-09-02. `todo_without_tmux.md` §1 carries
the remaining benchmark gap, which is a missing number, not a suspected regression.

### Phase 7 — Retirement

**Deliver:** §13.4 — both the shell-terminal tabs (§13.4.1) and xterm itself (§13.4.2),
including the input prerequisites §13.4.2 names. **Plus scrollback persistence and
restore, inherited from phase 6 on 2026-09-02** — see that phase's deferral table for
why it belongs here rather than there.

**Accept when:**
- a restored session shows its prior blocks with correct metadata, and the durable
  history that the shell-terminal tabs own today is owned by the session terminal's
  handle rather than deleted with them (§13.4.1, and the phase 6 deferral);
- the files listed in §13.4.1 and §13.4.2 are gone and no route references `/terminals`;
- `grep -rn "@xterm" frontend/src frontend/package.json` returns nothing, while
  `packages/terminal/bench/adapters/xterm.ts` is untouched and `npm run bench:gate` still
  runs against the xterm baseline;
- typing, pasting, mouse clicks and IME composition all work in `vim`, `htop`, `less` and
  an agent CLI with no xterm in the tree — verified by running them, not by unit tests
  alone;
- bracketed paste and mouse reporting are covered by `vt-core` tests and by at least one
  recorded vector each — the vectors live in `packages/terminal/protocol/alt-vectors`
  and `redraw-vectors`, which is also what the pty-host parity harness replays;
- the full e2e suite passes.

**Scope note, 2026-09-02.** Two pieces of phase 7 arrived early from other work and are
no longer this phase's to do: the session pane's third surface and its view-mode toggle
are already deleted (§13.3), and three of the four xterm prerequisites in §13.4.2 have
landed. What remains is the shell-terminal tabs (§13.4.1, `ShellTerminalsView.tsx` and
friends are still in the tree with their handle-keyed capture and history ownership),
click/drag mouse reporting, IME composition, and then the deletion itself.

**Ordering within the phase, because one of these can destroy data and the others
cannot.** The history migration comes first and lands on its own: §13.4.1 is explicit
that *"deleting the tabs alone must not delete or session-key that bridge."* A phase 7
that opens with `git rm` is the failure mode this phase is arranged to avoid. So:

1. **Migrate durable block history to the session terminal's handle** — journal
   directory, supervisor lifecycle, `terminal_blocks` ownership, history endpoint
   contract, `durableBlocks` capability. Verified by a restored session showing its
   prior blocks *while the tabs still exist*. This is the inherited phase 6 deliverable
   and it is reversible on its own.
2. **Close the input gaps** — click/drag mouse reporting (`?1000`/`?1002`/`?1003`, with
   `?1006` encoding already tracked from phase 3) and IME composition. Until these land,
   deleting `XtermTerminal.tsx` ships a pane that cannot be clicked in.
3. **Delete the shell-terminal tabs**, once (1) proves the bridge moved.
4. **Delete xterm**, last, once (2) proves the package supplies what xterm supplied.

Steps 3 and 4 are the only irreversible ones and they are last by construction. §13.4's
own closing line — *"This is last so a revert costs nothing before it"* — is the rule
this ordering implements.

### Phase 8 — Mobile

**Deliver:** the block renderer and input editor in Flutter against the same daemon
block stream, per `CLAUDE.md`'s `packages/mobile` conventions.

**Accept when:** `flutter analyze` reports "No issues found!", `flutter test` passes,
and a session shows the same blocks on phone and desktop.

---

## 15. Common wrong turns

Written for the planner. Each of these is a specific way this design gets quietly
broken.

1. **Building JS objects per cell in the renderer.** Defeats §6.2 and puts the perf
   gate out of reach. Rows are built from typed-array slices.
2. **Skipping the sum tree "for now".** It is not an optimization; it is the structure
   the virtualizer queries. Retrofitting it means rewriting the renderer.
3. **Treating OSC 133 as a fallback to add later.** It is the baseline (§2.6) and a
   phase 1 acceptance test. A design where blocks only exist with our bootstrap is
   Warp's design, and §3.3 is why we rejected it.
4. **Assuming marks are paired.** §3.2, §7.4.
5. **Overloading `ports.ActivitySignal` for shell blocks.** §13.1.
6. **Parsing marks at `attachment.onData`.** Duplicates with two clients, produces
   nothing with zero. §13.1.
7. **Reaching for a timer to decide when it is safe to take input.** §3.5, §10.2.
8. **Special-casing a prompt framework by name in a shell script.** §3.1, §8.
9. **Running a command in the user's shell to gather state.** §3.6, §8.
10. **Importing across the package boundary by relative path.** §4.2.
11. **Adding a canvas fast-path inside a DOM block.** §9.3. The escape hatch is a whole
    renderer, not a hybrid.
12. **Deleting `XtermTerminal.tsx` before phase 7.** It is the alt-screen surface for
    phases 1 and 2, and phase 3's own surface must prove itself before the fallback goes.
    §11, §13.4.
13. **Reading the user's shell history file.** §10.4.
14. **Adding a second extension encoding.** §7.3. Unknown keys are ignored; that is the
    versioning story.
15. **Planning two phases at once.** §0.3.
16. **Turning prompt suppression on in phase 1.** It suppresses the only thing the user
    can type into before the editor exists, and it breaks the §14.0 cutline that makes
    phase 1 shippable. Suppression ships with the editor, in phase 2. §8.1.
17. **Treating phase 1 as a stepping stone rather than a release.** If phase 1 lands and
    everything stops, Operator must still have a terminal it can use every day. §14.0.
18. **Assuming an agent pane is in the alternate screen.** It was, until 2026-09-02, and
    only because tmux's client put it there. It is now in the normal buffer. Three
    separate readings of the same capture reached three different answers, so: `?1049`
    tells you what the *outermost* program in the pane wants, and the outermost program
    is now the agent. §0.7, §11.
19. **Reintroducing an unbounded queue to fix a blocking write in the runtime.** Every
    write on the pty-host's paths is load-bearing back-pressure: it stops the pump, which
    stops the PTY being read, which makes the child throttle itself. Bound the queue and
    block past the cap, the way `captureSink` does. `todo_without_tmux.md` §8 is the full
    account of getting this wrong and then right.

---

## 16. Glossary

- **Block** — one command with its output, its metadata and its lifecycle state.
- **Blockgrid** — the scrollback modeled as a sum tree of blocks over a cell grid.
- **Tier 1 / Tier 2** — OSC 133-only blocks vs. blocks with our extension marks (§7.2).
- **Mark** — an escape sequence carrying block-lifecycle information.
- **`SpawnRecipe`** — the argv+env the package tells a host to spawn (§4.1).
- **Line-editor ownership** — whether the shell's readline is idle and we may own input (§10.2).
- **Alt screen** — the `1049` alternate buffer a full-screen TUI takes over (§11).
- **The gate** — the perf thresholds in §9.4, checked at the end of every phase from 1.
- **agent-orchestrator** — the user's *separate* reference app governing Operator's
  visual language. Not this repository. See `CLAUDE.md`.

---

## 17. Appendix — the Warp reference map

### 17.1 Where it is, and the rules for using it

The Warp source is checked out at `/Users/omaraly/development/AI/warp`. Every path in
this appendix is relative to that root and was verified to exist on 2026-08-29.

**Rules:**
- **Read it, do not copy it.** We are learning the mechanism and the data structures.
  We are not transplanting code, comments, or asset files. The checkout carries **no
  top-level `LICENSE`** — treat it as all-rights-reserved and read-only. The one
  lineage it declares in-source is Alacritty's, at
  `crates/warp_terminal/src/model/grid/grid_handler.rs:1-2` (*"adapted from the
  alacritty_terminal crate under the Apache license"*); where we want that lineage,
  take it from Alacritty upstream under Alacritty's own licence, not from Warp.
- **It is a reference, not an authority.** §3 lists six places where Warp is wrong for
  our purposes. When this spec and Warp disagree, this spec wins.
- **The Alacritty lineage matters.** `grid_handler.rs:1-2` names it explicitly, and
  `model/ansi/mod.rs:4` shows the parser is Alacritty's `VteParser` wrapped. Alacritty
  itself is often the clearer read for pure VT behaviour.
- **Verify before you cite.** `grid_handler.rs:2` points at a
  `crates/warp_terminal/src/model/LICENSE-ALACRITTY` file that is **not present** in our
  checkout. This spec cited it in three places before the citation was checked and
  removed. Treat every path in §17.4 as checkable, and report a miss rather than
  planning around it — that is §0.2 doing its job.

### 17.2 Reading order for someone starting cold

Roughly two hours, in this order:

1. `crates/warp_terminal/src/model/ESCAPE_SEQUENCES.md` — their own primer on what
   they write to the pty, with links to the VT100 spec.
2. `crates/warp_terminal/src/model/grid/flat_storage/mod.rs`, then `content.rs`, then
   `attribute_map.rs` — the storage design we are adopting (§6.2).
3. `crates/sum_tree/src/lib.rs` and `cursor.rs` — 1,997 lines total, the whole
   sum-tree idea (§6.3).
4. `crates/warp_terminal/src/model/blockgrid.rs` — how blocks and the grid meet.
5. `app/assets/bundled/bootstrap/zsh_body.sh` — the shell side, and the single best
   argument for our additive-only rule (§8).
6. `app/src/terminal/line_editor_status.rs` — small, and the clearest statement of the
   problem our explicit `input-ready` mark solves (§10.2).

### 17.3 Component map

Our component on the left, what to read on the right.

| Ours | Read in Warp | Take | Avoid |
| --- | --- | --- | --- |
| `vt-core` cell storage (§6.2) | `crates/warp_terminal/src/model/grid/flat_storage/{mod,content,attribute_map,index,grapheme,style,hyperlink,row_iterator}.rs` | the whole shape: chunked content, run-length attributes, row index | nothing — this is the best part of their design |
| `vt-core` resize/reflow (§6.2) | `crates/warp_terminal/src/model/grid/grid_storage/resize.rs`, `model/grid/resize.rs`, `model/grid/row.rs` | how wrapped rows survive a resize | — |
| `vt-core` grapheme handling | `model/grid/grapheme_cursor.rs`, `model/char_or_str.rs` | wide chars, combining marks, cursor movement over graphemes | — |
| `vt-core` blockgrid (§6.3) | `crates/warp_terminal/src/model/{blockgrid.rs,block_id.rs,block_index.rs,block_filter.rs}`, `app/src/terminal/model/{blocks.rs,block.rs}` | block identity, indexing, the block/grid boundary | `app/src/terminal/model/blocks.rs` also carries UI state — keep that out of our core |
| `vt-core` sum tree (§6.3) | `crates/sum_tree/src/{lib.rs,cursor.rs}`, used at `app/src/terminal/{model/blocks.rs,block_list_viewport.rs,model/blocks/selection.rs,find/model/async_find.rs}` | the summary/cursor design and the four places it pays off | — |
| `vt-core` selection (§6.4) | `crates/warp_terminal/src/model/selection.rs`, `model/grid/selection_cursor.rs`, `app/src/terminal/model/blocks/selection.rs` | cross-block selection in block coordinates | their renderer owns hit-testing; ours delegates to the browser |
| `vt-core` find (§6.5) | `crates/warp_terminal/src/model/find.rs`, `app/src/terminal/find/model/async_find.rs` + `async_find/{background_task,work_queue}.rs`, `find/model/block_list.rs` | incremental, cancellable, work-queued find | — |
| `vt-core` redaction | `crates/warp_terminal/src/model/secrets.rs`, `model/grid/secrets.rs` | secret detection at the grid layer | — |
| VT parser (§6.1) | `crates/warp_terminal/src/model/ansi/mod.rs`, `model/grid/ansi_handler.rs`, `model/grid/ansi_handler/tab_stops.rs`, `model/escape_sequences.rs` | coverage: which sequences a real terminal must handle | `ansi/mod.rs:1019-1026` shows OSC 133 parsed but not used as a block source — we do the opposite (§3.3) |
| Mark protocol (§7) | `crates/warp_terminal/src/model/ansi/dcs_hooks.rs`, `crates/warp_terminal/src/bootstrap.rs`, `crates/warp_terminal/src/shell/{mod.rs,unescape.rs}` | the field set worth carrying | three encodings and a two-meaning session id (`dcs_hooks.rs:16-28`) — we ship one encoding, §7.3 |
| Shell bootstrap (§8) | `app/assets/bundled/bootstrap/{zsh_body.sh,bash_body.sh,fish.sh,pwsh_init_shell.ps1}`, `crates/warp_terminal/src/local_tty/shell.rs` | which hook points exist per shell; the subshell and re-entrancy problems | hook stashing (`zsh_body.sh:236-242`), keybinding theft (`:378-385`), generator commands (`:205-208,254-262`), ssh argv sniffing (`bash_body.sh:966-969`), disabling fish's OSC 133 (`shell.rs:691-694`) |
| Alt screen (§11) | `app/src/terminal/alt_screen/{mod.rs,alt_screen_element.rs}`, `app/src/terminal/alt_screen_reporting.rs`, `crates/warp_terminal/src/model/mode.rs` | alt screen as explicit tracked state, and find inside it (`find/model/alt_screen.rs`) | — |
| `renderer-dom` block list (§9.2) | `app/src/terminal/{block_list_element.rs,block_list_viewport.rs,block_list_settings.rs}` | viewport maths, overscan, what a block's chrome contains | it is a GPU element list; our virtualization is DOM |
| `renderer-dom` grid painting | `app/src/terminal/{grid_renderer.rs,blockgrid_renderer.rs,blockgrid_element.rs}`, `crates/warpui/src/rendering/{atlas/,glyph_cache.rs,wgpu/}` | read only if §9.4's gate ever forces the WebGL renderer | do not build a glyph atlas in phases 0–7 (§1.4) |
| `ts/editor` (§10) | `app/src/terminal/input.rs` (16,760 lines — skim), `app/src/terminal/input/{classic.rs,buffer_model.rs}`, `app/src/editor/` | the buffer model and what the editor must own | `input.rs`'s size is the §3.4 lesson; ours is split by §4.3 |
| Line-editor ownership (§10.2) | `app/src/terminal/line_editor_status.rs` | the exact problem statement, stated well in its own comments | the 50ms timer and the `did_receive_zsh_precmd` proxy — §3.5 |
| History (§10.4) | `app/src/terminal/{history.rs,history_tests.rs}` | dedup, ordering, per-directory ranking | reading the user's shell history file — §10.4 |
| `ts/completions` (§14 phase 4) | `crates/warp_completer/src/{lib.rs,meta.rs,parsers/,signatures/}`, `crates/warp_completer/src/parsers/README.md`, `app/src/completer/`, `app/src/terminal/dynamic_enum_suggestions.rs`, `command-signatures-v2/` | the spec format and the command-signature idea | anything that executes in the user's shell — §3.6 |
| Command palette (§14 phase 5) | `app/src/command_palette.rs` | action registry and ranking | — |
| Themes (§12.1) | `app/src/themes/{theme.rs,default_themes.rs}` | the theme file format we must load | their theme creator UI is out of scope |
| Links (§9) | `app/src/terminal/links.rs`, `model/grid/hyperlink_registry.rs` | OSC 8 hyperlinks and detected links as a side table | — |
| Keys (§10) | `app/src/terminal/{keys.rs,keys_settings.rs,meta_shortcuts.rs}` | keymap layering | — |
| Test corpus (§6.6) | `app/src/terminal/ref_tests/{mod.rs,data/}` | recorded byte streams replayed against the parser | — |
| Images | `crates/warp_terminal/src/model/{iterm_image.rs,kitty.rs,image_map.rs}`, `model/grid/image.rs` | iTerm2 and Kitty image protocols, if we ever want them | out of scope for phases 0–7 |

### 17.4 Citation index

Every Warp citation used in the body of this spec, in one place, for checking.

| § | Claim | Citation |
| --- | --- | --- |
| 1.2, 3.7 | the grid is Alacritty-derived and block-aware | `crates/warp_terminal/src/model/blockgrid.rs`, `crates/warp_terminal/src/model/grid/grid_handler.rs:1-2`, `crates/warp_terminal/src/model/ansi/mod.rs:1-11` |
| 6.3b | Warp wraps a pinned fork of `vte`, and uses `regex-automata` for find | `Cargo.toml:347`, `crates/warp_terminal/Cargo.toml:43,56,61,118` |
| 1.2 | shell bootstrap sizes | `app/assets/bundled/bootstrap/zsh_body.sh` (1,588), `bash_body.sh` (1,437), `fish.sh` (804) |
| 1.2 | input is a real editor, not readline | `app/src/terminal/input/{classic,agent,buffer_model}.rs`, `app/src/terminal/line_editor_status.rs` |
| 1.3 | subsystem line counts | `app/src/terminal` 230,377 · `crates/warp_terminal` 46,585 · `app/src/editor` 43,279 · `crates/warpui` 34,439 · `crates/warp_completer` 19,054 |
| 3.1 | user hooks stashed and restored; p10k carved out by name | `app/assets/bundled/bootstrap/zsh_body.sh:236-242` |
| 3.1 | user keybindings removed and rebound | `app/assets/bundled/bootstrap/zsh_body.sh:378-385` |
| 3.2 | fish's OSC 133 disabled because pairing was assumed | `crates/warp_terminal/src/local_tty/shell.rs:691-694`, `github.com/warpdotdev/Warp/issues/7588` |
| 3.3 | three payload encodings, two-meaning session id | `crates/warp_terminal/src/model/ansi/dcs_hooks.rs:16-28` |
| 3.3 | OSC 133 parsed but not used as a block source | `crates/warp_terminal/src/model/ansi/mod.rs:1019-1026` |
| 3.3 | ssh argv sniffing and ControlMaster workarounds | `app/assets/bundled/bootstrap/bash_body.sh:966-969`, `:87-93` |
| 3.4 | unbounded file growth | `app/src/terminal/view.rs` 29,236 lines · `app/src/terminal/input.rs` 16,760 lines |
| 3.5 | the 50ms line-editor timer and the bootstrap proxy | `app/src/terminal/line_editor_status.rs:17` and the `did_receive_zsh_precmd` field |
| 3.6 | generator commands run in the user's shell and leak | `app/assets/bundled/bootstrap/zsh_body.sh:205-208`, `:254-262` |
| 3.7, 6.3 | sum tree used for blocks, viewport, selection, find | `app/src/terminal/model/blocks.rs`, `block_list_viewport.rs`, `model/blocks/selection.rs`, `find/model/async_find.rs` |
| 3.7, 6.6 | recorded-stream test corpus | `app/src/terminal/ref_tests/data/**/*.recording` |
| 6.2 | chunked content, run-length attribute maps, row index | `crates/warp_terminal/src/model/grid/flat_storage/{content,attribute_map,index}.rs` |
| 6.5 | Warp's find is async, work-queued, incremental, cancellable | `app/src/terminal/find/model/async_find.rs`, `find/model.rs`, `find/model/async_find/{background_task,work_queue}.rs`, `find/model/block_list.rs`, `find/model/alt_screen.rs` |
| 6.5 | Warp's find uses `sum_tree::SeekBias` and `BlockList` for block-level walk | `app/src/terminal/find/model/async_find.rs:16` (use), `find/model/block_list.rs` |
| 7.3 | OSC 777 also handled, informing our number choice | `crates/warp_terminal/src/model/ansi/mod.rs:1032` |
| 14 Phase 5 | Warp scrolls to a block by walking the block list, not by absolute coordinates | `app/src/terminal/block_list_viewport.rs:863` (`scroll_to_blocklist_row_if_not_visible`), `:1159` (definition) |
| 14 Phase 5 | Warp's block filter is per-block output, with "Filter block output" placeholder and an "Invert filter" toggle | `app/src/terminal/block_filter.rs:33` (placeholder), `:52` (invert tooltip), `crates/warp_terminal/src/model/block_filter.rs` (model) |
| 14 Phase 5 | Warp's command palette opens the input editor with `PromptEditorOpenSource::CommandPalette` | `app/src/terminal/input.rs:2033` (open source), `:6366` (open event) |
| 14 Phase 5 | Warp's bookmark navigation: `bookmark_block`, `bookmark_up`, `bookmark_down` are the block-list walk | `app/src/terminal/view.rs:21550` (bookmark_block), `:22772` (bookmark_up), `:22801` (bookmark_down) |
| 14 Phase 5 | sticky positioning of the pinned header survives `contain: strict` in Chromium; absolute children of `overflow: auto` containers position at the content origin, not the padding box | proved in real Chromium via `smoke:vite`; pinned element is the first child of the host (`ts/renderer-dom/src/pinned-header.ts:1-49`) |

### 17.5 Operator citations used in this spec

| § | Claim | Citation |
| --- | --- | --- |
| 2.7 | the terminal keeps its own palette | `DESIGN.md:36` |
| 4.2 | the relative-path cross-package import we are not repeating | `frontend/src/renderer/lib/ansi.ts:2` |
| 5 | no npm workspace; delegation via `--prefix` | `package.json` (root) |
| 5 | the single tsconfig path alias | `frontend/tsconfig.json` |
| 5 | the single vite alias | `frontend/vite.renderer.config.ts:78-80` |
| 5.2 | the only Cargo package, standalone, Rust 1.96 | `frontend/src-tauri/Cargo.toml` |
| 9.4 | existing perf scenarios and runner | `frontend/perf/scenarios.json`, `frontend/scripts/benchmark-terminal.mjs` |
| 11, 13.3 | the alt-screen bridge for phases 1–2, replaced in phase 3, deleted in phase 7 | `frontend/src/renderer/components/XtermTerminal.tsx` (1,117 lines on 2026-09-02; 1,057 when first cited) |
| 12.2 | the eight locale files | `frontend/src/renderer/i18n/{en,zh-CN,ja,ko,es,fr,de,pt-BR}.json` |
| 13.1 | per-client attach makes in-band parsing wrong | `backend/internal/terminal/manager.go:448`, `backend/internal/terminal/doc.go:11` |
| 13.1 | `SourceID` was always meant to carry a shell mark's counter | `backend/internal/service/blockevent/types.go:11-17` |
| 13.1 | `ActivitySignal` is hook-shaped and must not be overloaded | `backend/internal/ports/runtime_observations.go:41` |
| 13.2 | the existing `blocks` mux channel and its frames | `frontend/src/renderer/lib/terminal-mux.ts:12`, `:75-80` |
| 13.3 | host link policy Operator already has | `frontend/src/renderer/lib/external-link-policy.ts` |
| 13.4 | what phase 7 retires | `ShellTerminalsView.tsx` (180) · `ShellTerminalTab.tsx` (194) · `useShellTerminals.ts` · `routes/_shell.terminals.tsx` · `frontend/e2e/shell-terminal-tabs.spec.ts` · `XtermTerminal.tsx` (1,057) · the `@xterm/*` dependencies — **not** `bench/adapters/xterm.ts`, which the §9.4 gate measures against |
| 6.5 | find bench and chosen block budget (Phase 5, Task 1) | `packages/terminal/bench/find.bench.ts`, `packages/terminal/ts/core/src/terminal-core.ts:29` (`FIND_STEP_BUDGET = 1000`) |
| 14 Phase 5 | find bar UI is renderer-owned, inert in alt screen | `packages/terminal/ts/renderer-dom/src/find-bar.ts`, `find-bar.test.ts` |
| 14 Phase 5 | pinned command header is the first child of the host, `position: sticky; top: 0` | `packages/terminal/ts/renderer-dom/src/pinned-header.ts`, `pinned-header.ts:1-49` |
| 14 Phase 5 | block navigation lives in the renderer, not the line-editor keymap | `packages/terminal/ts/renderer-dom/src/block-nav.ts`, `block-nav.test.ts` (alt-screen inertness is the first assertion) |
| 14 Phase 5 | filter is a pure view function, never an edit; `BlockId`s survive a filter-and-clear cycle | `packages/terminal/ts/renderer-dom/src/block-filter.ts`, `block-filter.test.ts` |
| 14 Phase 5 | bookmark bit at position 17 of the packed state-source-hasexit-bookmarked word | `packages/terminal/crates/vt-wasm/src/lib.rs` (encoder), `packages/terminal/ts/core/src/blocks.ts` (decoder) |
| 14 Phase 5 | full block action menu: 7 actions, every action is a real `<button>` with `aria-label`, no action may run a command | `packages/terminal/ts/renderer-dom/src/block-actions.ts`, `action-events.ts`, `block-actions.test.ts`, `action-events.test.ts` |
| 14 Phase 5 | command palette: substring filter, Cmd/Ctrl+Shift+P, inert in alt screen in two places | `packages/terminal/ts/renderer-dom/src/palette.ts`, `palette.test.ts` |
| 14 Phase 5 | `HostCapabilities` has no capability that can execute anything (§3.6 structural) | `packages/terminal/ts/core/src/types.ts:194-200` |
| 14 Phase 5 | `dom-block-renderer.ts` did not grow past 600 lines (599/600 at the cap) | `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts` |
| 0.7 | tmux is deleted; one pty-host runtime on every platform | `backend/internal/adapters/runtime/{ptyhost,runtimeselect,parity}/`, `runtimeselect/runtimeselect.go` (`New` returns `ptyhost` unconditionally), commit `ba5fd58a1` |
| 0.7, 13.2 | the runtime's own capture sink replaced `pipe-pane`, and is bounded rather than unbounded | `backend/internal/adapters/runtime/ptyhost/capture.go`, `TestCaptureQueueIsBounded`, `TestCaptureBackpressureDoesNotStallDelivery`, `todo_without_tmux.md` §8 |
| 0.7, 11, 14 Phase 3 | an agent pane is in the normal buffer now that no tmux client injects `?1049h` | `docs/superpowers/specs/2026-09-01-tmux-free-pty-runtime-design.md` (§Problem), and the 2026-08-30 direct capture of Claude Code recorded in 14 Phase 3 |
| 0.7, 13.3 | the session view mode and its blocks surface are deleted | commit `e246a1470`; `frontend/src/renderer/components/CenterPane.tsx`, `stores/ui-store.ts` |
| 0.7, 14 Phase 6 | the font stepper, pane fullscreen and Cmd+wheel zoom are deleted | commit `c9c7f71d9`; `frontend/src/renderer/components/CenterPane.tsx`, `TitlebarNav.tsx` |
| 12.1, 14 Phase 6 | the four §12.1 look gaps are closed | `frontend/src/renderer/components/BlockTerminal.tsx:369,371`, `packages/terminal/ts/renderer-dom/src/styles.css:47-49,97-100`, `packages/terminal/ts/renderer-dom/src/fonts/`, commits `a83e29013` … `fbe04f719` |
| 13.4.2 | three of the four xterm prerequisites landed early | `packages/terminal/ts/editor/src/encode-key.ts`, `paste.ts`, `packages/terminal/crates/vt-core/src/parser.rs:145`, `packages/terminal/ts/core/src/terminal-core.ts:138` |
| 13.4.1 | the shell-terminal tabs are still in the tree | `ShellTerminalsView.tsx` (180) · `ShellTerminalTab.tsx` · `useShellTerminals.ts` · `routes/_shell.terminals.tsx` · `frontend/e2e/shell-terminal-tabs.spec.ts` |
| 5.5 | `vt-core` runs in the daemon as a C-ABI wasm module under `wazero`, passive and resized with the PTY | `packages/terminal/crates/vt-host/` (cdylib), `backend/internal/adapters/runtime/ptyhost/vtwasm/vtwasm.go`, `backend/go.mod:21`, `packages/build-binaries.sh:20-26` |
