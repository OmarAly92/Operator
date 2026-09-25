# Terminal roadmap: the next ten plans (design)

**Date:** 2026-09-24
**Decision owner:** Omar Aly
**Status:** design, input to ten implementation plans. Nothing here is built.
**Derived from:** [`2026-09-19-terminal-reference-survey.md`](2026-09-19-terminal-reference-survey.md)
(status lines checked 2026-09-24) and
[`2026-09-24-not-done-plain-language.md`](2026-09-24-not-done-plain-language.md).

## What the user chose

On 2026-09-24 the user picked these survey entries to build. Every one is
**Not done** or **Partial** in the survey:

| Plain-language item | Survey entries |
|---|---|
| Typing ahead | §7.2 |
| Crash recovery | §6.3 |
| Very old output | §5.8 |
| Window title and messages from programs | §1.15 |
| 1. Search that keeps up | §1.7, §3.12 |
| 2. Smarter search | §2.6 |
| 3. One look for highlights | §1.8 |
| 4. Highlight your words | §5.6 |
| 5. Paste safety | §1.10, §2.11 |
| 6. Resize without a mess | §1.5, §2.4, §5.4 |
| 14. Agents report what they're doing | §7.1 |
| 15. Terminal notices the agent is idle | §6.9 |
| 16. Faster text processing | §1.11 |
| 17. Faster line edits | §1.12 |
| 18. Tidier control-code handling | §2.2 |
| 19. Safety caps | §2.14 |
| 20. Report window size | §1.16 |

§7.1, §6.9, §2.2 and the §1.5/§5.4 resize work were **non-goals of the
agent-TUI spec** (`docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`,
Non-goals). This choice supersedes that for the entries above.

## Rules every plan obeys

- **Licences decide how a reference is used.** Checked in the local copies
  under `/Users/omaraly/development/AI/` on 2026-09-24:

  | Project | Licence | Use |
  |---|---|---|
  | Ghostty | MIT | code may be adapted, with its notice kept |
  | Alacritty (and `vte`) | Apache-2.0 / MIT | code may be adapted, with its notice kept |
  | xterm.js | MIT | code may be adapted, with its notice kept |
  | WezTerm | MIT | code may be adapted, with its notice kept |
  | VS Code | MIT | code may be adapted, with its notice kept (as `LICENSE-VSCODE-MIT` already does) |
  | **Kitty** | **GPL-3.0** | **clean-room only**: read for behaviour, write our own code, never copy |
  | **Warp** | **AGPL-3.0** | **clean-room only**, the same rule as the path detection rebuild (`b17acd63c`) |

  Adapted MIT/Apache code gets an attribution file next to the existing
  `LICENSE-VSCODE-MIT` / `VSCODE-LINK-PARSING-ATTRIBUTION.md` and a line in
  `TERMINAL.md` §3.2.
- `packages/terminal` stays product-independent (`TERMINAL.md` §3). Operator
  decisions (where a title shows, when to confirm a paste) live on the host
  side of a seam.
- Read `TERMINAL.md` end to end before each plan. No comments in new code.
  Specs and plans cite `file:line` or write "not known".
- Every plan that touches rendering keeps `npm run bench:feel` at zero pixel
  diff unless it deliberately changes pixels and says which. Every plan runs
  `bench:selection`, `bench:agent:scroll`, `bench:agent:gate`,
  `bench:affordances` and the unit suites. A `vt-core` change rebuilds both
  wasm artifacts and the daemon (`TERMINAL.md` §6).
- A/B performance runs alternate order and cross-check with a trace
  (`TERMINAL.md` §4.26; the containment measurement).
- Workflow per plan: the plan is written in a cleared session from this
  spec, executed subagent-driven in another, reviewed here, real-app
  verified, merged to `development`.

## Order

| # | Plan | Entries | Size | Why this position |
|---|---|---|---|---|
| 1 | Paste safety | §1.10, §2.11 | S | Small, protects against a real risk, no dependencies |
| 2 | Search | §1.7, §3.12, §2.6 | M | Used daily on Claude output |
| 3 | Messages from programs | §1.15, §1.16, §2.14 | M | Claude's title is the most visible win in the list |
| 4 | Crash recovery | §6.3 | M–L | Robustness; backend only |
| 5 | Highlights and marks | §1.8, §5.6 | M | Builds on Plan 2's find hits |
| 6 | Typing ahead (shell) | §7.2 | M | Needs a careful design; shell only |
| 7 | Very old output | §5.8 | M | Needs the eviction path Plan 9 may touch; independent otherwise |
| 8 | Agent awareness | §7.1, §6.9 | M | Mostly valuable for remote sessions |
| 9 | Parser rework | §2.2, §1.11, §1.12 | L | Invisible; largest regression risk |
| 10 | Shell resize reflow | §1.5, §2.4, §5.4 | L | Riskiest; can change what Claude Code panes show on resize |

Plans 1–4 are independent of each other. Plan 5 needs Plan 2. Plan 3's
title-stack caps (§2.14) are simpler after Plan 9 but do not wait for it.
Plan 10 goes last so Plan 9's parser is settled first.

---

## Plan 1 — Paste safety (§1.10, §2.11)

**For the user:** text copied from a web page can hide a line break or
control characters that make a command run the moment it is pasted. After
this plan such a paste is cleaned or you are asked first.

**References:** Ghostty `src/input/paste.zig:160-190` (`isSafe`: unsafe if
the data contains `\n` or `\x1b[201~`, whatever the mode) and
`src/terminal/paste.zig:1-17` (one function turns a paste into pty bytes);
Alacritty `alacritty/src/event.rs:1369-1410` (inside bracketed paste strip
every `\x1b` and `\x03`; outside, `\r\n`/`\n` become `\r`). MIT/Apache.

**Today:** `ts/editor/src/paste.ts:17-26` `planPaste`:
- when the line editor owns the line (shell prompt), the text is inserted
  into the editor, so nothing runs until Enter (`:20`);
- otherwise newlines become `\r` and, without bracketed paste, are sent as
  is, so every line runs (`:21-22`);
- with bracketed paste only the literal `ESC[201~` is removed (`:23`); a
  lone `ESC` or `^C` passes through.
Callers: `line-editor.ts:223`, `TerminalSurface.tsx:335`.

**Build:**
- One pure function in `ts/editor` that returns the bytes to send plus a
  verdict `{ safe: true } | { safe: false, reason: "newline" | "control" | "paste-end" }`.
  Inside brackets strip `\x1b` and `\x03` (Alacritty); outside brackets a
  multi-line or control-bearing paste is unsafe (Ghostty).
- A host seam: `HostCapabilities.confirmPaste?(preview, reason): Promise<boolean>`.
  With no host handler, behaviour is today's (product independence).
- Operator implements the confirm with a shadcn dialog showing the first
  lines and the reason. The editor-owned path stays as is (already safe).

**Decisions for the plan:** whether Operator confirms only unbracketed
multi-line pastes (Ghostty's default) or every unsafe verdict; a "don't ask
again for this pane" option or not. Default proposal: confirm unbracketed
multi-line and any control character, no "don't ask".

**Tests:** a table test over the verdicts (Ghostty's and Alacritty's cases,
our own); `TerminalSurface` test that a confirm "no" sends nothing; Claude
Code still receives a bracketed multi-line paste unchanged apart from
stripped `ESC`/`^C`.

---

## Plan 2 — Search that keeps up, smarter search (§1.7, §3.12, §2.6)

**For the user:** while Claude is still writing, new matches appear in the
find bar without searching again; "error" finds "Error"; next/previous stays
fast in huge output.

**References:** Ghostty `src/terminal/search/` (`active.zig:11-19`: re-search
only the mutable area; `viewport.zig:12-22`: viewport by fingerprint;
`sliding_window.zig:30-60`); xterm.js `addons/addon-search`
(`SearchLineCache.ts:29-60`, results changed events); Alacritty
`alacritty_terminal/src/term/search.rs:25-60` (directional, bounded lazy
DFAs, smart case `:39-40`). All MIT/Apache.

**Today:** `crates/vt-core/src/find.rs:15-142` — `FindQuery::{Literal, Regex}`
and a `FindCursor` that steps block by block over the whole buffer once
(`step` `:107`). `ts/renderer-dom/src/find-bar.ts:237-245` opens one session
per query with `core.findOpen(query, false)` (`terminal-core.ts:383`,
`isRegex = false`): literal and case-sensitive, and it does not pick up
output that arrives later. Hits carry stable rows (Plan B).

**Build:**
- `vt-core`: a `FindSession` kept on the core: history hits extended from a
  `scanned_to` offset as content grows (append-only, never rescanned);
  screen hits recomputed only when the screen generation changed; a rewrap
  invalidates nothing (byte ranges re-resolve through the row index).
  Expose `find_update() -> (added, removed)`.
- Smart case: case-insensitive unless the query has an uppercase letter
  (Alacritty). Regex as an option in the bar.
- Directional `find_next(from, direction)` bounded by a budget, so
  next/previous from the current hit does not scan everything.
- `find-bar.ts` subscribes to updates while open and keeps the current hit
  anchored (stable row) while output streams.

**Tests:** `vt-core/tests/find_session.rs` (history not rescanned after new
output; a live-frame hit updates; a match across the scrollback/screen
boundary; a rewrap keeps the hit; smart case both ways);
`find-bar.test.ts` "does not rescan history on repaint", "a new match
appears without retyping". Perf: a 60k-row buffer, time per update before
and after.

---

## Plan 3 — Messages from programs: title, notifications, size reports, caps (§1.15, §1.16, §2.14)

**For the user:** each session can show what Claude says it is doing right
now (for example "◐ Number list 1 to 3000"); a program's own "done"
notification reaches you; the few programs that ask for the window size in
pixels get an answer.

**References:** Ghostty (OSC coverage, `src/terminal/`; size reports
`src/terminal/size_report.zig:5-40`, `stream_terminal.zig:249-260`, mode
2048); Alacritty `alacritty_terminal/src/term/mod.rs:42-48`, `:2235-2248`
(title stack capped at 4096). MIT/Apache.

**Today:**
- `crates/vt-core/src/parser/perform.rs:89` and `history.rs:152`: both
  `osc_dispatch` handle only OSC 8. Titles, notifications, colour queries and
  pointer shape are dropped.
- Evidence of use: the `claude-long-50k` fixture carries 1,047 `OSC 0`
  titles, `claude-spinner-10s` 16 (spinner glyph while working, `✳` when idle,
  then Claude's task summary). Whether Claude Code emits OSC 9/777
  notifications depends on its notification setting: **not known**; the plan
  records one session per setting and counts.
- `ts/core/src/types.ts:252` has a `notify?(title, body)` host seam with no
  callers.
- No XTWINOPS `14/16/18 t`, no mode 2048 (§1.16 status line).

**Build:**
- `vt-core`: store the latest OSC 0/2 title (and XTWINOPS 22/23 push/pop with
  a capped stack, §2.14); OSC 9, OSC 777 `notify` and OSC 99 parsed into
  notification events; OSC 10/11 colour queries answered from the theme;
  OSC 22 pointer shape recorded. Both dispatchers (`perform.rs`,
  `history.rs`) stay in step.
- Replies (OSC 10/11, XTWINOPS 14/16/18, 2048): find where the existing
  replies to Claude Code's probes are produced today (XTVERSION, DECRQM,
  DA1; memory note "Claude Code probes the terminal before sync output") and
  use the same path. Where that path is: **not known** to this spec; the
  plan names it with `file:line` first.
- `ts/core`: `onTitle(title)` and the existing `notify` seam fire; pointer
  shape applied by the renderer.
- Operator: the title shows on the session card / pane header (placement is
  a UI decision under `DESIGN.md`; the plan proposes one with a screenshot
  and asks). Program notifications route into the existing agent-alerts path
  (`docs/superpowers/specs/2026-09-23-agent-alerts-design.md`) only when the
  pane is not visible.

**Decisions for the plan:** where the title shows; whether the spinner glyph
is stripped; whether program notifications are on by default.

**Tests:** `vt-core` tests per OSC (set, overwrite, push/pop at the cap,
malformed input ignored); a fixture test that the Claude recording's last
title is `✳ …`; reply byte tests for 10/11/14/16/18/2048.

---

## Plan 4 — Crash recovery (§6.3)

**For the user:** a terminal whose helper process hangs is noticed and
recovered instead of staying frozen; a terminal whose helper dies keeps its
history.

**Correction to the plain-language doc:** terminals already survive a
daemon restart. A pty-host outlives the daemon that spawned it and is found
again through an on-disk registry
(`backend/internal/adapters/runtime/ptyhost/claim.go:1-3,17-19`,
`ptyregistry`). What is missing is below.

**References:** VS Code `src/vs/platform/terminal/node/ptyService.ts:687-810`
(`PersistentTerminalProcess`, grace timers, orphan question) and
`common/terminal.ts:865-874`. MIT.

**Today:**
- Liveness: `runtime.go:269-275` `IsAlive` → `client.go:243-257`
  `clientIsAlive` dials the host with `isAliveTimeout`; a timeout is
  "transient". The reaper records a failed probe as `ProbeFailed`, not dead,
  and leaves it to the lifecycle manager
  (`backend/internal/observe/reaper/reaper.go:205-215`). So a hung host
  (accepting nothing, or accepting and never answering) is never restarted.
  What the user sees in that state: **not known**; the plan reproduces it
  first (`kill -STOP` on a pty-host) and records it.
- Heartbeat: `backend/internal/terminal/manager.go:746` `heartbeatLoop` pings
  mux clients over WebSocket every 15 s (landed 721b8b34a, before the survey);
  there is no daemon → pty-host heartbeat.
- History: the pty-host's mirror and ring (`ring.go`, `MaxOutputLines`) live
  only in the host's memory. If the host dies, the history is gone.

**Build:**
- Step 1, measure: hang a pty-host (SIGSTOP), kill one (SIGKILL), reboot-free
  daemon restart; record for each what the pane and the board show.
- A daemon → pty-host heartbeat with a bounded number of missed beats; after
  it, the host is declared hung, the user is told in the pane, and it is
  restarted through the existing respawn path (`respawn.go`) — never
  silently killed while the child still runs work (a decision the plan
  presents: restart vs mark and offer a button).
- Persist the mirror's history (or the ring) to disk periodically so a dead
  host's pane reopens with its history; this is the open "Decision 2" of the
  agent-TUI spec (the §6.3 status line). The plan measures write cost and
  size first.

**Tests:** Go tests with a fake host that stops answering (heartbeat marks it
hung after N beats, not before); respawn keeps the client attached
(`respawn_test.go` pattern); persistence round-trip; a real-app check with
SIGSTOP.

---

## Plan 5 — Highlights and marks (§1.8, §5.6)

**For the user:** selection, search matches and other marks look and behave
the same and overlap cleanly; you can ask for words like `ERROR` to be
highlighted everywhere.

**References:** Ghostty `src/terminal/highlight.zig:1-10,31,62`,
`render.zig:233-236` (MIT); Kitty `kitty/marks.py:15-40`, `docs/marks.rst`
(**GPL-3.0: clean-room only**).

**Today:** the selection paints through `selection-fill`
(`renderer-selection.ts`), find hits through row classes (`find-bar.ts`),
and Plan E's range painter (`decorations.ts`) serves links, hints, redaction
and prediction. No user marks.

**Build:** one highlight model in the renderer (ranges in stable-row
coordinates with a kind and priority) painted by one painter; selection,
find hits (Plan 2) and decorations move onto it. A host seam
`setMarks(rules: { pattern, colour }[])` for user marks; Operator exposes
them in Settings (UI decision).

**Tests:** overlap order (selection over a find hit over a mark);
`bench:selection` unchanged; feel gate unchanged with no marks; a mark
survives a trim and a rewrap.

---

## Plan 6 — Typing ahead, shell panes only (§7.2)

**For the user:** in a shell, what you type while a command is still running
lands in the input box for the next command instead of being lost into the
running program's output.

**Scope decision (2026-09-24):** shell panes only. In a Claude Code session
Claude is the running program and must keep receiving every key.

**References:** Warp `app/src/terminal/model/early_output.rs:26-48`
(**AGPL-3.0: clean-room only** — the behaviour is described in the survey
§7.2 and may be used; the code may not).

**Today:** `ts/editor/src/line-editor.ts:239-247` `passthrough`: when the
line editor does not own the line (`lineEditorState() !== "owned"`), keys go
straight to the pty; this is deliberate since `4b31952aa` (2026-09-02) so an
interactive program (a `y/n` prompt, a password) receives them. The shell
scripts report only `input-ready`/`input-released`
(`shell/zsh.sh`), not the shell's input buffer.

**Build (behaviour-level, clean-room):** keep passthrough while a command
runs, so interactive programs are unaffected. When the block finishes, the
shell echoes typed-ahead text as the start of the next command line; that
text is taken into the line editor (and cleared from the shell's own
buffer), so it appears in the input box ready to edit. Needs the shell to
report its buffer at the prompt: a small addition to `zsh.sh`/`bash.sh`/`fish.fish`
(`$BUFFER` / `READLINE_LINE` / `commandline`), reported through the existing OSC 133 path.

**Decisions for the plan:** what happens to typed-ahead text when the next
prompt is not the shell's (a program that read it).

**Tests:** a recorded shell session typing during `sleep 2`; the editor holds
the text after the prompt; a `read -p` prompt still receives keys; Claude
Code panes unchanged (passthrough test).

---

## Plan 7 — Very old output (§5.8)

**For the user:** in very long sessions, output older than the 200,000-line
limit can still be loaded instead of being dropped.

**References:** Kitty `kitty/history.c:17-45,83-105,347-440` (segmented
history; lines falling off the cap serialised as ANSI into a byte-capped
ring, shown by a pager). **GPL-3.0: clean-room only.**

**Today:** `crates/vt-core/src/limits.rs:8-11` `Limits { rows: 200_000,
bytes: 128 MiB }` in both cores; rows beyond it are dropped. Cold scrollback
rewraps lazily (`row_index.rs:56` `HOT_ROWS = 2_000`).

**Build:** rows evicted past the cap are written, as text with their styles
(ANSI), into a byte-capped cold ring in the pty-host's mirror (the copy that
survives the pane being closed); the pane offers "Load older output" at the
top of scrollback, which fetches a chunk over the existing replay channel and
prepends it as history rows. The ring's size cap is a setting with a default
the plan measures (memory per MiB of ring). Whether the ring is also written
to disk depends on Plan 4's persistence.

**Tests:** evict past the cap, load back, compare text and styles; the cap
holds; `bench:agent:scroll` unchanged.

---

## Plan 8 — Agent awareness in the terminal (§7.1, §6.9)

**For the user:** Claude's "working / needs you / done" signals would also
work for an agent running on another machine over SSH, where Operator's local
hooks cannot reach the daemon; and any host of the terminal package can tell
that an agent is idle or waiting for an answer.

**References:** Warp `app/src/terminal/cli_agent.rs:1-4,404`,
`cli_agent_sessions/plugin_manager/claude.rs:14-22` (an agent plugin that
reports session events in-band over OSC 777; **AGPL-3.0: clean-room only**);
VS Code
`terminalContrib/chatAgentTools/browser/executeStrategy/executeStrategy.ts:14-31`,
`…/tools/monitoring/types.ts:30-52` (idle/prompt state machine; MIT).

**Today:** agent state reaches the daemon out of band only: `opr` hooks
over loopback HTTP (`backend/internal/cli/hooks.go`,
`adapters/agent/claudecode/hooks.go`), the `opr mcp` `session_report` tool
(`2e54a6bfb`), the transcript's interrupt marker (`69ae2946f`). `vt-core`
parses no OSC 777 (§7.1 status line). No idle/prompt detector in the package.

**Build:**
- `vt-core` parses a small, documented OSC 777 event vocabulary (ours, not
  Warp's wire format) into agent events; `ts/core` exposes
  `onAgentEvent`. Operator's hook command writes the same event to the
  terminal when it runs remotely (how a remote hook reaches the tty: the plan
  measures; **not known** here).
- A package-level idle/prompt detector (VS Code's states: active, polling for
  idle, idle, prompting) usable by any host, plus a compact
  `readBlockOutput({ compact: true })` that strips spinner frames and
  repeated redraws.
- Operator prefers its local hooks when present and uses the in-band events
  when not.

**Decision for the plan:** whether remote agents are in scope now or the
in-band path is built and tested only against a local recording.

**Tests:** OSC 777 parse table; detector state transitions on the Claude
recordings (working → idle at `✳`); compact output against a fixture.

---

## Plan 9 — Parser rework: typed dispatch, fast path, row flags (§2.2, §1.11, §1.12)

**For the user:** nothing visible; fewer odd bugs from unusual programs and
faster processing of large output.

**References:** `vte-0.15.0/src/ansi.rs:495` `Handler` (Alacritty's parser
crate, already a dependency; Apache/MIT); Ghostty
`src/terminal/stream.zig:599-720`, `src/simd/vt.zig:1-60` (bulk printable
path), `src/terminal/page.zig:2020-2058` (row flags; MIT).

**Today:** `crates/vt-core/src/parser/perform.rs:6-89` implements
`vte::Perform` by hand: `print` per character with a style resolve each
(`:6`), `execute` (`:13`), `csi_dispatch` (`:26`), `osc_dispatch` (`:89`);
SGR decoded in `sgr.rs`. `ScreenGrid` keeps separate `wrapped` and `dirty`
vectors, no row flags (§1.12 status line). `TERMINAL.md` §4.22 records one
bug this design caused (private `CSI > … m` read as SGR).

**Build, in three separable steps:**
1. Move dispatch to `vte::ansi::Handler` (feature `ansi`), keeping every
   observable behaviour; delete the hand decoders it replaces.
2. A printable-run fast path (`print_run`) and a bounded ring of unknown
   sequences for diagnostics.
3. Row flags (`styled`, `wrapped`, `grapheme`, `hyperlink`) so erase/insert
   on plain rows skips per-cell work.

**Gates:** `tests/ref`, the integrity proptest and every `vt-core` test
unchanged; feel gate zero diff; a throughput bench (MB/s on the 50k
recording) before/after, alternated, with a trace.

---

## Plan 10 — Shell resize reflow (§1.5, §2.4, §5.4)

**For the user:** in a shell, making the window narrower or wider reflows the
text neatly and keeps your prompt in place instead of pushing the screen into
history.

**References:** Ghostty `src/terminal/Terminal.zig:4092-4130`,
`Screen.zig:2232-2290` (prompt redraw, pull scrollback on growth; MIT);
Alacritty `alacritty_terminal/src/grid/resize.rs:14-69` (lines then columns,
cursor carried; Apache/MIT); Kitty `kitty/screen.c:555-760` (keep the
current prompt from rewrapping; **GPL-3.0: clean-room only**).

**Today:** `crates/vt-core/src/screen/resize.rs:4-19`: with
`reflow_on_resize` the frame's rows are recorded as evicted (pushed into
scrollback) and the screen reset (Warp's model); no pull-back on growth, the
cursor is not carried through a reflow.

**Risk:** Claude Code runs on the primary screen and repaints itself on
resize; its duplicate-frame artefact is upstream (memory note "Claude Code
resize duplicate is upstream"). Changing eviction can change what a Claude
pane shows after a resize.

**Build:** reflow in place with the cursor carried and scrollback pulled
back on growth **only while the shell owns the line** (line editor `Owned`,
i.e. at a prompt with OSC 133 marks); every other state keeps today's
eviction. The current prompt is not rewrapped (clean-room of Kitty's
behaviour).

**Gates:** the Claude fixtures' recorded resizes (`applyResizesUpTo`,
`bench/agent-session/main.ts`) must produce byte-identical feel screenshots;
new `vt-core` tests for shrink/grow at a prompt with a wide character at the
cut and a multi-line prompt.

---

## What this spec does not decide

- UI placement for Plans 1, 3 and 5 (confirm dialog, title, marks settings):
  each plan proposes with a screenshot and asks, under `DESIGN.md`.
- Whether Plan 4's persistence and Plan 7's ring share one on-disk format.
- The order after Plan 4; it may change with what Plans 1–4 find.

---

## Real-app checks, deferred to the end (user decision 2026-09-25)

Run all of these once every plan has merged, in the desktop app (`npm run tauri:dev`
with the CLAUDE* environment scrubbed, daemon and app restarted so both wasm builds
and the shell scripts are current). Each plan adds its checks here when it merges.

- **Plan 1 — paste safety:** in a shell pane run `cat`, paste two lines: a dialog
  appears; Cancel sends nothing, Paste sends both. Paste two lines at an idle
  shell prompt: they go into the input line, nothing runs until Enter. Paste two
  lines into a Claude pane: no dialog, the text arrives.
- **Plan 2 — search:** in a Claude pane that is writing, Cmd+F a word that keeps
  appearing: the count grows without retyping. `error` also finds `Error`;
  `Error` finds only that case. Enter/Shift+Enter stay on the chosen hit while
  output streams. The `.*` toggle works (`line [0-9]+`).
- **Plan 4 — crash recovery:** find a session's pty-host pid in
  `~/.operator/windows-pty-hosts.json`. `kill -STOP <pid>`: within ~17 s the
  pane shows "This terminal stopped responding." with Restart terminal; Restart
  brings it back with the agent resumed. `kill -CONT` instead: the strip goes
  away by itself. Wait over a minute, `kill -KILL <pid>`, restore the session:
  the old output is still there.
- **Plan 6 — typing ahead:** in a zsh pane run `sleep 3` and type `echo hi`
  during it: afterwards `echo hi` is in the input box and did not run. In a
  Claude pane, typing while Claude works behaves as before.
- **Plan 5 — highlights and marks:** Settings → Terminal highlights → add
  `error` (red): Claude output containing it is tinted, including inside the
  grey message band, and follows rewrap and streaming. Turn on `.*` and type
  `(`: an inline error, no terminal change; `err(or)?` matches, `ERROR` does
  not. Cmd+F: hit tint as before; Enter outlines the current row; a selection
  dragged over a hit row sits on top. A mark and a find hit on one row layer
  as selection > current hit > find tint > mark. Park a pane, edit a highlight,
  switch back: new colour. Remove all highlights: nothing stays tinted.
- **Plan 3 — messages from programs:** start a Claude Code session: the
  session card and the pane header show the live title without the spinner
  glyph, update as Claude works, and clear after "Relaunch in a cleared
  session". Close the pane: the card still updates. In a shell pane that is off
  screen (or with the window unfocused) run `printf '\e]9;hello\a'`: a Mac
  notification appears, and clicking it opens that terminal; on screen, none.
  `printf '\e[18t'`, `printf '\e]11;?\a'` get answers; `printf '\e]22;text\a'`
  changes the pointer.
- **Plan 7 — very old output:** in a shell pane run `seq 1 400000`. Scroll to
  the top: the first row is about 200001 and "Load older output" shows. Click
  it: the view does not jump and rows up to about 200000 appear above; the
  button comes back. Keep clicking until it disappears (near 1). `echo hi`:
  loaded rows trim away and the button returns at the top.
- **Input ordering fix (d1a962b8f):** nothing to click; covered by tests.
