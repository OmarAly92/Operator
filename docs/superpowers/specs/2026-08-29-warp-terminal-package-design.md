# Design — `packages/terminal`: a Warp-grade terminal as a reusable package

Status: approved design, not yet planned
Date: 2026-08-29
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
through 7. A plan covers one phase. A plan that "gets a head start" on the next phase
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

---

## 1. Goal, and what "identical to Warp" means

### 1.1 The goal in one sentence

Build a terminal that a Warp user cannot distinguish from Warp in look and feel, as a
self-contained package that any project can consume, whose maintenance stays inside
its own directory.

### 1.2 What we are matching

Warp's identity comes from three mechanisms, not from its GPU renderer:

1. **The scrollback is a list of blocks, not a wall of rows.** Warp's grid is
   block-aware at the data-structure level — `crates/warp_terminal/src/model/blockgrid.rs`,
   which sits next to `crates/warp_terminal/src/model/LICENSE-ALACRITTY` because it is
   Alacritty's grid forked and made block-aware. Selection, find, filtering and the
   viewport are all per-block.

2. **The shell tells the app where blocks begin and end.** A 1,588-line
   `app/assets/bundled/bootstrap/zsh_body.sh` (plus 1,437 for bash, 804 for fish)
   injects hooks that emit DCS payloads for `InitShell`, `precmd` and `preexec`.

3. **Input is not the shell's readline.** `app/src/terminal/input/{classic,agent,buffer_model}.rs`
   is a real text editor. `app/src/terminal/line_editor_status.rs` exists solely to
   track whether the shell's line editor is idle so Warp can take input over.

The GPU renderer (`crates/warpui`, 34,439 lines including
`src/rendering/{atlas,glyph_cache,wgpu}`) is how Warp draws, not why it feels like
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
  not silently degrade.

---

## 2. Decisions already made — closed, with reasoning

These were decided by the user on 2026-08-29. §0.1 applies.

**2.1 — We own the input; the shell's readline is replaced.**
We draw the prompt row ourselves from mark data (cwd, git branch, exit code,
duration). The user's `starship`/`oh-my-zsh`/`powerlevel10k` prompt stops rendering.
*Reasoning:* this is the single largest contributor to "it feels like Warp", and it is
what makes a block's command text exact rather than scraped off the screen.
*Consequence accepted:* Ctrl-R and Tab completion become our code (phases 2 and 3).

**2.2 — Desktop first; mobile is phase 7.**
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

The package MUST NOT know that Operator exists. No daemon, no tmux, no HTTP, no mux
channel, no session IDs, no Operator design tokens, no `react-i18next`.

```ts
export interface PtyTransport {
  write(data: Uint8Array): void;
  onData(cb: (data: Uint8Array) => void): () => void;
  resize(cols: number, rows: number): void;
  dispose(): void;
}

export interface HostCapabilities {
  writeClipboard(text: string): Promise<void>;
  readClipboard(): Promise<string>;
  openLink(url: string): Promise<void>;
  notify?(title: string, body: string): void;
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

### 6.4 Selection

Selection is expressed in block-relative coordinates `(BlockId, row, col)` and can span
blocks. It lives in the core, not the renderer, so that a WebGL renderer later inherits
it unchanged. The DOM renderer maps native browser selection onto it rather than
replacing it, so copy, triple-click and accessibility keep working.

### 6.5 Find

Find runs over the sum tree and returns matches as `(BlockId, row, col_range)`. It must
be incremental and cancellable — a find over a 500k-row scrollback cannot block the
frame. Warp's equivalent is `app/src/terminal/find/model/async_find.rs`.

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

`go/marks` finds boundaries and extracts fields from a byte stream. It does not
maintain a grid, does not render, does not track alt-screen cell state beyond the
enter/leave signal, and does not own block layout. The daemon uses it to record which
bytes belong to which block so a session with no client attached still has scrollback.
Full parsing happens only where pixels happen.

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

### 8.1 Prompt suppression

Because we draw the prompt row (§2.1), the bootstrap sets the shell's prompt to a
minimal sentinel. This is a prompt *variable* assignment — `PS1`/`PROMPT`/`fish_prompt`
— made after the user's config has loaded, and it is reversible: the package exposes a
"show shell prompt" mode that skips it, which is also the fallback when the user's
framework fights us.

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
- `input-latency` p95 MUST be ≤ the recorded xterm baseline.
- `vtebench` MUST be ≥ 0.9× the xterm baseline (parser work moves to WASM; a small
  regression here is acceptable, a large one is not).
- Scroll through 50,000 blocks MUST hold 60fps on the reference machine.

If `renderer-dom` misses a gate after honest optimization, that is the trigger for a
WebGL renderer behind §9.1 — not a redesign of core, blocks or editor.

---

## 10. The input editor

### 10.1 What it is

A DOM-based editor at the bottom of the pane: multi-line, command syntax highlighting,
ghost-text history suggestion, Ctrl-R history search, and (phase 3) a completions
dropdown. It is `ts/editor`, it talks to `ts/core`, and it MUST NOT import
`ts/completions` directly — completions arrive through a provider interface registered
on the core.

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

Phase 1 uses the existing `XtermTerminal.tsx` as the raw surface, wired as the host's
`AltScreenSurface`. It is not deleted — it becomes the fallback. Whether the package
later ships its own raw surface is a phase 5 question, not a phase 1 one.

`vt-core` MUST track alt-screen as explicit state, not as a rendering detail; the
daemon-side decoder needs the same signal to suspend capture (§13.2).

---

## 12. Theming and strings

### 12.1 Theme

`TerminalTheme` is a plain object: 16 ANSI colors plus foreground, background, cursor,
selection, and the block chrome colors. The package ships a Warp-matching default and a
loader for **Warp's own theme file format**, so the ecosystem of Warp themes works
here. Operator passes a theme derived from its skin for the chrome colors only; the
ANSI palette stays the terminal's own per `DESIGN.md:36`.

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

`docs/superpowers/plans/2026-08-28-shell-blocks.md` stands for its backend half and is
superseded for its frontend half.

**Survives, and this spec depends on it:**
- `tmux pipe-pane` as the server-side capture path. Plan 7's analysis is correct and is
  not reopened: `newAttachment` is per-client
  (`backend/internal/terminal/manager.go:448`, `backend/internal/terminal/doc.go:11`),
  so parsing at `attachment.onData` duplicates blocks with two clients attached and
  produces none with zero attached.
- A second entry point on `blockevent`, not an overload of
  `ports.ActivitySignal`. `backend/internal/service/blockevent/types.go:11-17` already
  documents that `SourceID` will be "a shell mark's counter later"; that is this. Do
  not bend `ActivitySignal` — `backend/internal/ports/runtime_observations.go:41+` is
  hook-shaped and a `ToolUseID` holding a command counter is a lie that costs a week.
- Alt-screen tracking in the daemon's parse pass.
- Windows gets no shell blocks and says so.

**Superseded:** plan 7's block rendering, block viewport, composer and find tasks in the
renderer. Those are this package's phases 1–4.

**Action:** when planning phase 1, rewrite plan 7 as the backend-only plan it should
have been rather than executing it and then undoing its frontend half.

### 13.2 The daemon's job

1. Ask the package for a `SpawnRecipe` (via a small Go-side accessor over
   `packages/terminal/shell/`) and spawn the session's shell with it.
2. `tmux pipe-pane` the session's output into a reader using `go/marks`.
3. Record block boundaries and their bytes through `blockevent.Service`, with
   `SourceID` = the mark's block id.
4. Suspend capture between alt-screen enter and leave.
5. Publish on the existing `blocks` mux channel — `frontend/src/renderer/lib/terminal-mux.ts:12`
   documents it and `:75-80` are the subscribe/unsubscribe frames. No new channel.

### 13.3 The renderer's job

`TerminalPane.tsx` mounts `@operator/terminal-react` instead of `XtermTerminal`
directly, passing a `PtyTransport` backed by the existing mux terminal channel, the
skin-derived theme, the host capabilities Operator already has (clipboard, external
link policy at `frontend/src/renderer/lib/external-link-policy.ts`), and
`XtermTerminal` as the alt-screen surface.

Live blocks come from the package's own parse of the stream it is already receiving.
History (blocks from before this client attached) comes from
`GET /sessions/{id}/blocks` and is fed into the core as pre-parsed blocks. Both paths
must converge on the same `BlockId` — that is why block id continuity is a Tier-2 field
(§7.2).

### 13.4 Retirement (phase 6)

Per plan 7's settled decision 3, one session has exactly one terminal surface. These go:
`ShellTerminalsView.tsx` (180 lines), `ShellTerminalTab.tsx` (194),
`useShellTerminals.ts`, the `CenterPane` tab strip, the `/terminals` route
(`frontend/src/renderer/routes/_shell.terminals.tsx`) and
`frontend/e2e/shell-terminal-tabs.spec.ts`. This is last so a revert costs nothing
before it.

---

## 14. Phases

Each phase is a separate implementation plan. §0.3 applies.

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
the find *engine* (§6.5 — the find UI is phase 4, but the engine ships here because the
sum tree it queries is built here and retrofitting it later means rewriting it);
`crates/marks` and `go/marks` with the §7.4 recovery table, vectors and fuzz target;
`shell/zsh.sh` per §8; `renderer-dom` with two-level virtualization; the Warp prompt row
(cwd, branch, exit code, duration); per-block selection, copy and hover actions;
alt-screen handoff to `XtermTerminal`; daemon capture via `pipe-pane` publishing on the
`blocks` channel.

**Accept when:**
- **a shell with only OSC 133 configured, and no bootstrap, produces correct blocks** —
  this is a phase 1 test, not a later nice-to-have (§2.6);
- every row of the §7.4 recovery table has a passing vector in both decoders;
- the fuzz target runs clean on the seeded corpus including split-across-read marks;
- a session with no client attached records blocks, and a session with two clients
  attached records each block exactly once;
- entering and leaving `vim` suspends and resumes capture, leaving one collapsed block;
- the §9.4 gate passes;
- scrolling 50,000 blocks holds 60fps.

### Phase 2 — Input

**Deliver:** `ts/editor`; `input-ready`/`input-released` marks and the
`LineEditorState` machine (§10.2); command syntax highlighting; multi-line; ghost-text
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

### Phase 3 — Completions

**Deliver:** `ts/completions`; the provider interface on the core; path, flag and git
subcommand providers; fuzzy ranking; the dropdown UI; a declarative spec format for
per-command completions.

**Accept when:**
- no completion path executes anything in the user's shell (§3.6);
- completions are cancellable and never block a frame;
- the spec format has at least three commands defined in it and a documented schema;
- the §9.4 gate still passes.

### Phase 4 — Navigation

**Deliver:** command palette; block find, filter and bookmark; sticky command header;
jump-to-block; the full block action menu.

**Accept when:** find across a 500k-row scrollback returns first results under 100ms and
is cancellable; every action is keyboard-reachable; the §9.4 gate still passes.

### Phase 5 — Chrome and configuration

**Deliver:** the theme system with Warp theme-file loading; font and ligature settings;
splits and panes; scrollback persistence and restore.

**Accept when:** a stock Warp theme file loads and renders; a restored session shows
its prior blocks with correct metadata; the §9.4 gate still passes.

### Phase 6 — Retirement

**Deliver:** §13.4.

**Accept when:** the files listed in §13.4 are gone, no route references `/terminals`,
and the full e2e suite passes.

### Phase 7 — Mobile

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
12. **Deleting `XtermTerminal.tsx` in phase 1.** It becomes the alt-screen surface. §11.
13. **Reading the user's shell history file.** §10.4.
14. **Adding a second extension encoding.** §7.3. Unknown keys are ignored; that is the
    versioning story.
15. **Planning two phases at once.** §0.3.

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
  exception it does declare is `crates/warp_terminal/src/model/LICENSE-ALACRITTY`,
  which covers the Alacritty lineage of the grid; where we want that lineage, take it
  from Alacritty upstream under Alacritty's own licence, not from Warp's fork.
- **It is a reference, not an authority.** §3 lists six places where Warp is wrong for
  our purposes. When this spec and Warp disagree, this spec wins.
- **The Alacritty lineage matters.** `crates/warp_terminal/src/model/LICENSE-ALACRITTY`
  sits beside the grid because that is where the grid came from. Alacritty itself is
  often the clearer read for pure VT behaviour.

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
| `renderer-dom` grid painting | `app/src/terminal/{grid_renderer.rs,blockgrid_renderer.rs,blockgrid_element.rs}`, `crates/warpui/src/rendering/{atlas,glyph_cache,wgpu}` | read only if §9.4's gate ever forces the WebGL renderer | do not build a glyph atlas in phases 0–7 (§1.4) |
| `ts/editor` (§10) | `app/src/terminal/input.rs` (16,760 lines — skim), `app/src/terminal/input/{classic.rs,buffer_model.rs}`, `app/src/editor/` | the buffer model and what the editor must own | `input.rs`'s size is the §3.4 lesson; ours is split by §4.3 |
| Line-editor ownership (§10.2) | `app/src/terminal/line_editor_status.rs` | the exact problem statement, stated well in its own comments | the 50ms timer and the `did_receive_zsh_precmd` proxy — §3.5 |
| History (§10.4) | `app/src/terminal/{history.rs,history_tests.rs}` | dedup, ordering, per-directory ranking | reading the user's shell history file — §10.4 |
| `ts/completions` (§14 phase 3) | `crates/warp_completer/src/{lib.rs,meta.rs,parsers/,signatures/}`, `crates/warp_completer/src/parsers/README.md`, `app/src/completer/`, `app/src/terminal/dynamic_enum_suggestions.rs`, `command-signatures-v2/` | the spec format and the command-signature idea | anything that executes in the user's shell — §3.6 |
| Command palette (§14 phase 4) | `app/src/command_palette.rs` | action registry and ranking | — |
| Themes (§12.1) | `app/src/themes/{theme.rs,default_themes.rs}` | the theme file format we must load | their theme creator UI is out of scope |
| Links (§9) | `app/src/terminal/links.rs`, `model/grid/hyperlink_registry.rs` | OSC 8 hyperlinks and detected links as a side table | — |
| Keys (§10) | `app/src/terminal/{keys.rs,keys_settings.rs,meta_shortcuts.rs}` | keymap layering | — |
| Test corpus (§6.6) | `app/src/terminal/ref_tests/{mod.rs,data/}` | recorded byte streams replayed against the parser | — |
| Images | `crates/warp_terminal/src/model/{iterm_image.rs,kitty.rs,image_map.rs}`, `model/grid/image.rs` | iTerm2 and Kitty image protocols, if we ever want them | out of scope for phases 0–7 |

### 17.4 Citation index

Every Warp citation used in the body of this spec, in one place, for checking.

| § | Claim | Citation |
| --- | --- | --- |
| 1.2, 3.7 | the grid is Alacritty-derived and block-aware | `crates/warp_terminal/src/model/blockgrid.rs`, `crates/warp_terminal/src/model/LICENSE-ALACRITTY` |
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
| 7.3 | OSC 777 also handled, informing our number choice | `crates/warp_terminal/src/model/ansi/mod.rs:1032` |

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
| 11, 13.3 | the surface that becomes the alt-screen fallback | `frontend/src/renderer/components/XtermTerminal.tsx` (1,057 lines) |
| 12.2 | the eight locale files | `frontend/src/renderer/i18n/{en,zh-CN,ja,ko,es,fr,de,pt-BR}.json` |
| 13.1 | per-client attach makes in-band parsing wrong | `backend/internal/terminal/manager.go:448`, `backend/internal/terminal/doc.go:11` |
| 13.1 | `SourceID` was always meant to carry a shell mark's counter | `backend/internal/service/blockevent/types.go:11-17` |
| 13.1 | `ActivitySignal` is hook-shaped and must not be overloaded | `backend/internal/ports/runtime_observations.go:41` |
| 13.2 | the existing `blocks` mux channel and its frames | `frontend/src/renderer/lib/terminal-mux.ts:12`, `:75-80` |
| 13.3 | host link policy Operator already has | `frontend/src/renderer/lib/external-link-policy.ts` |
| 13.4 | what phase 6 retires | `ShellTerminalsView.tsx` (180) · `ShellTerminalTab.tsx` (194) · `useShellTerminals.ts` · `routes/_shell.terminals.tsx` · `frontend/e2e/shell-terminal-tabs.spec.ts` |
