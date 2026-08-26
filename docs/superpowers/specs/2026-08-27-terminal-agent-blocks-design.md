# Terminal — agent blocks

Status: proposed
Date: 2026-08-27
Scope: `packages/mobile` terminal feature, `frontend/src/renderer` terminal pane,
`backend/internal` hook and stream path

Both clients get the same block view over the same event stream. The urgent case
is mobile, where the current view is unusable; desktop gains the same structure
and the same scrolling, and keeps its existing grid unchanged behind a toggle.

## Problem

On the phone, the terminal screen renders the same character grid the desktop
renders. Text is too small to read, and pinch-zoom trades legibility for context:
zoomed out nothing is readable, zoomed in the surrounding output is off-screen.

The cause is grid arbitration, not font size. `largestGrid`
(`backend/internal/terminal/manager.go:307`) chooses one client's `cols` and
`rows` as a pair. When any primary client has reported a size, every non-primary
is skipped. The desktop is primary; the phone is not. The desktop's grid becomes
authoritative and is pushed to the phone as a `resize` frame, and the phone
renders a desktop-shaped screen on a phone-shaped display.

Two consequences follow, and both matter:

- The phone does **not** degrade the desktop while the desktop is attached. An
  earlier framing in design discussion claimed it did; the code says otherwise.
- No amount of mobile-side styling fixes this. A grid that is 120 columns wide is
  unreadable on a 390pt display at any font size that also fits 30 rows.

Therefore the fix cannot be a better grid. It must be a view that has no grid.

**The desktop is not broken, and gets the same view for a different reason.** Its
grid is the one that wins arbitration, so it renders correctly. What it lacks is
structure: an agent's work is a wall of repainting TUI, not a list of steps that
can be scrolled, collapsed, or copied. The same block stream that rescues mobile
gives desktop that structure at close to no extra cost, since the backend half is
shared. Desktop keeps its current grid untouched behind the same toggle.

## Approach

Render agent sessions as a **list of blocks** derived from structured events the
agent already emits, on both clients, and keep the raw character grid as a
separate mode reachable by a toggle.

This is the model Warp uses, confirmed by reading `warpdotdev/warp` at
`/Users/omaraly/development/AI/warp`. Warp is AGPL-3.0 (`warp_terminal`); nothing
here is derived from its source. What follows is what its design demonstrates.

### What Warp demonstrates

**Structure is pushed, never scraped.** For shells, Warp injects a bootstrap
script that emits hex-encoded JSON over a private OSC 9278 / DCS channel
(`app/assets/bundled/bootstrap/zsh_init_shell.sh`), with a hook vocabulary
defined in `crates/warp_terminal/src/model/ansi/dcs_hooks.rs`: `Preexec`,
`Precmd`, `CommandFinished`, `InitShell`, `Bootstrapped`, `ExitShell` and others.
`PreexecValue` carries the command; `CommandFinished` carries the exit code;
`PromptMetadata` carries `pwd`, `git_branch`, `virtual_env`.

**CLI agents get the same treatment through a plugin installed into the agent.**
`app/src/terminal/cli_agent_sessions/` handles Claude Code, Codex, Gemini and
opencode, one plugin manager per agent. The event vocabulary
(`event/v1.rs`) is `session_start`, `prompt_submit`, `tool_complete`, `stop`,
`stop_failure`, `permission_request`, `permission_replied`, `question_asked`,
`idle_prompt`. The payload carries `query`, `response`, `transcript_path`,
`summary`, `tool_name`, `tool_input`, `error_type`, `session_id`, `cwd`,
`project`, `plugin_version` and a schema version `v`. Transport is OSC 777, with
a documented fallback source for Codex's native OSC 9.

**Full-screen TUIs are not blocked.** `app/src/terminal/alt_screen/` suspends the
block list and hands the display to a full-screen element whenever a program
takes the alternate screen. Warp does not attempt to segment vim, and it does not
attempt to segment an agent's TUI.

**Failure is designed for.** The event enum carries an `Unknown(String)` variant,
the schema is versioned in both the payload (`v`) and the module path (`event/v1.rs`),
and the plugin's own version is recorded per session.

### Why Operator is already most of the way there

`opr hooks <agent> <event>` is the same mechanism. `backend/internal/cli/hooks.go`
shows the request body already carrying `Event`, `ToolName`, `ToolUseID`,
`AgentSessionID`, `LatestUserPrompt`, `LatestAssistantUpdate`, `TranscriptPath`,
`LaunchID` and usage metadata. `activitydispatch/dispatch.go` registers derivers
for eleven harnesses. `observe/usage/watcher.go` already watches transcript files
with fsnotify, and `session_manager/handoff_artifact.go` already parses transcript
records with bounded excerpting.

Two differences from Warp, one favourable and one costly:

- **Favourable.** Operator's adapters install the hooks themselves. Warp shows the
  user a modal with manual install instructions per agent
  (`plugin_manager/mod.rs`, `PluginInstructions`). Operator needs no such step.
- **Costly.** Operator's events travel out-of-band over loopback HTTP to the
  daemon; Warp's travel in-band on the PTY. In-band gives byte-position
  correlation for free — an event lands at a known point in the output stream.
  Out-of-band is the right choice for Operator, because mobile is remote and the
  daemon is the hub, but it means a block cannot name the rows of raw output it
  corresponds to.

Warp's alt-screen behaviour makes that cost acceptable: blocks were never going
to interleave with an agent's TUI. Two modes with a toggle is the design, not
blocks embedded in a grid.

**The whole payload is currently discarded.** `domain/activity.go:7` is
`type ActivityState string`. Every hook callback is reduced to a coarse status
and the rich fields are dropped.

### Rejected alternatives

**Scraping the agent's TUI for markers.** Extending the approach in
`adapters/agent/terminalui/composer.go` to segment output. Rejected: per-harness
rules that break on every agent release, no scrollback to segment when the
harness takes the alt screen, and silent degradation — the worst failure mode for
a terminal. No implementation that has solved this problem does it this way.

**On-device grid diffing.** Cutting a block when a repainted region goes stable.
Rejected for the same reason: heuristic, harness-independent but quietly wrong.

**Styling only.** Warp's visual language with no blocks. Rejected: it does not
address the problem, which is grid shape rather than appearance.

## Design

### Backend

**Event capture.** Widen the activity path so hook payloads are retained rather
than collapsed to an `ActivityState`. A new `agentevent` package owns the record:
session id, monotonic sequence, event name, tool name, tool use id, tool input
preview, text (prompt / assistant update), error type, harness, hook schema
version, timestamp. `ActivityState` derivation is unchanged and continues to run
off the same callback, so existing status behaviour is untouched.

**Vocabulary.** Adopt Warp's event names as the normalized set —
`session_start`, `prompt_submit`, `tool_complete`, `stop`, `stop_failure`,
`permission_request`, `permission_replied`, `question_asked`, `idle_prompt` —
with an explicit unknown variant that carries the raw name through rather than
dropping it. Per-harness derivers map native hook names onto this set, registered
alongside the existing activity derivers.

**Persistence.** Events are appended to a bounded per-session log in sqlite, so a
client joining mid-session gets history rather than only what arrives next.
Bounds follow the pattern already established in `handoff_artifact.go`.

**Transport.** A new `blocks` channel on the existing `/mux` socket carries event
frames, alongside `terminal`, `subscribe`, `sessions` and `system`. It is named
for what it carries rather than for its first source, because shell marks
(see Shell blocks) are republished onto the same channel. This reuses
the socket the Kanban board and terminal already depend on, and is the reason
`MuxClient` lives in `core/mux/` rather than under a feature.

**Transcript enrichment (later step).** `TranscriptPath` plus the existing
`TranscriptWatcher` supplies bodies the hook payload truncates — full assistant
text, full tool results, diffs. Per-harness parsers, added one at a time. Not
required for the first release: hook events alone produce usable blocks.

### Mobile

**Models.** New, in `feature/terminal/data/model/`, hand-written, all fields
nullable, following the package conventions. **Deliberately not shared with
`feature/chat`.** The two consume different wire formats from different sources
(hook events versus the ACP conversation snapshot), and a session occupies one
interface mode at a time, so the two timelines are rarely live together. The cost
is accepted duplication in shape; the benefit is that neither view constrains the
other's evolution. Revisit only if a third consumer appears.

**Block assembly.** A pure function in `feature/terminal/logic/`, folding the
event stream into blocks and correlating `tool_complete` with its
`prompt_submit` by `ToolUseID`. Pure, therefore directly testable, matching the
placement of `terminal_scroll.dart` and `terminal_fit.dart`.

**Rendering.** New widgets under `terminal_screen/ui/widgets/`, in the Warp
visual language: block cards with a header (prompt or tool name), a body, a
status affordance (running / done / failed / awaiting permission), collapse, and
copy. Colours come from `AppSkin` via `context.skin`; the terminal palette in
`core/app_themes/colors/terminal_palette.dart` continues to govern raw grid
colours.

**Mode toggle.** The terminal screen gains two modes: **Blocks** (default for
agent sessions with hook coverage) and **Raw** (the current `TerminalSurface`,
unchanged, and the only mode for shell terminals and harnesses without hooks).
The existing status bar carries the toggle.

**Grid arbitration.** In Blocks mode the phone does not join the terminal channel,
so it reports no size and appears in no `members` map. It therefore has no effect
on `largestGrid` in either direction. Switching to Raw joins as today.

### Desktop

The desktop is Tauri 2 — a Rust host with a React 19 webview
(`frontend/src-tauri/`). Blocks are React components in the webview, not Rust.

**Mux client.** `frontend/src/renderer/lib/terminal-mux.ts` currently drops every
frame that is not `ch === "terminal"` (`terminal-mux.ts:202`), so it discards the
server's `resize` frames today and would discard `agent` frames too. It gains
`blocks` handling and a subscriber path, mirroring the mobile `MuxClient`.

**Types.** Generated from the OpenAPI spec through `npm run api`, per the repo's
API-contract rule. Unlike mobile, desktop models are not hand-written.

**Block assembly.** A pure module beside the pane, folding the same event stream
with the same `ToolUseID` correlation as mobile. The two implementations are
parallel by necessity — Dart and TypeScript — but must agree, so both are tested
against the same fixtures.

**Rendering.** New components in `frontend/src/renderer/components/`, built from
shadcn primitives per DESIGN.md, in agent-orchestrator's visual language with the
refined-blue accent. The terminal palette continues to govern Raw mode only, per
the standing carve-out. Blocks are ordinary DOM, so they inherit the platform's
scrolling, selection, find-in-page and accessibility.

**Mode toggle.** `TerminalPane` gains the same Blocks / Raw toggle as mobile, with
the same defaults, so the two clients behave identically. Raw remains
`XtermTerminal` with xterm.js, unchanged.

**Grid arbitration.** The desktop is the primary client, so its Raw grid stays
authoritative exactly as today. In Blocks mode it does not join the terminal
channel and reports no size. A consequence worth stating: if the desktop is in
Blocks mode and a phone is in Raw, the phone becomes the only sizer and the grid
follows the phone. That is correct — the only client rendering a grid should
choose it — but it is a behaviour change and needs a test.

### Desktop parity target

The desktop's goal is stated as parity with Warp's block terminal, not an
approximation of it. That sets a concrete bar, taken from Warp's own source
rather than from impressions of the product.

**The viewport is a component to build, not a `div` to style.**
`block_list_viewport.rs` is over a thousand lines maintaining a `sum_tree` of
block heights (`BlockHeightItem`, `BlockHeightSummary`) with approximate
comparisons (`heights_approx_gt`, `HEIGHT_FUDGE_FACTOR_LINES`) whose only purpose
is keeping scroll correct across a virtualized list of variable-height blocks.
That problem exists in a browser too. An earlier draft of this spec claimed
desktop scrolling came free from the DOM; that holds for a short list and fails
for a real session.

Required, and none of it arrives by default:

- **Virtualization.** A long session is thousands of blocks. Rendering them all
  destroys scroll; rendering a window of them requires knowing the heights of the
  ones not rendered.
- **A measured-height cache.** Blocks vary in height and are not measurable until
  rendered. Estimated heights corrected on measurement, with scroll position
  preserved across the correction, is the browser equivalent of Warp's height
  summary. Getting this wrong produces the drifting, jumping scrollbar that makes
  virtualized lists feel broken.
- **Scroll anchoring on append.** Output streams in continuously. Pinned to the
  bottom, the view follows; scrolled up, the view must not move when content
  arrives below.
- **Sticky block headers.** While a block is partly scrolled its header stays
  pinned, and the behaviour is **disabled when the block is taller than the
  viewport** (`block_list_element.rs:135`) — without that exception a tall block
  traps its own header.
- **Block-boundary navigation.** Jump to previous or next block, and scroll a
  named block into view.
- **Selection and find across blocks.** Selection must cross block boundaries, and
  find must search the list rather than one block (`app/src/terminal/find/`).

**Block actions**, matching what Warp offers per block: copy command, copy output,
re-run, collapse, and filter the list (`block_filter.rs` supports a query with
configurable context lines). Sharing (`share_block_modal.rs`) is deliberately not
adopted — it is a Warp cloud feature with no analogue here.

**Not adopted:** GPU text rendering. Warp rasterizes glyphs itself because it had
no compositor beneath it. A browser has one, and compositor-driven scrolling is
smooth provided the list does not re-render during scroll — which is a React
discipline requirement, enforced by profiling, not a framework requirement.

### Shell blocks

Warp's blocks cover **every command**, not only agent activity. A terminal that
blocks agent turns but leaves ordinary shell work as an undifferentiated wall is
not at parity, so shell terminals are in scope.

**Source.** A bootstrap script injected into the shell, emitting marks at prompt,
command start, and command end with the exit code — the role Warp's `Preexec`,
`Precmd` and `CommandFinished` hooks play. `service/shellterm/loginshell.go`
currently returns a bare `[$SHELL]` argv with no injection point, so this adds
one.

**Transport differs from the agent path, deliberately.** Shell marks are written
by the shell to its own PTY, so they arrive **in-band**, unlike `opr hooks` which
arrives out-of-band over loopback HTTP. The daemon parses the marks out of the
terminal stream and republishes them on the same block channel. Clients therefore
consume one uniform event stream and never learn that two different mechanisms
produced it.

**Why in the daemon rather than the clients.** Parsing once server-side keeps the
two client implementations from having to agree on an escape-sequence parser as
well as on block assembly, and keeps marks from reaching a client's emulator as
stray output.

**Scope limit.** Bash, zsh and fish, matching the shells Warp bootstraps. An
unrecognized shell gets no marks and stays in Raw, visibly.

### Rejected: building a UI framework

Warp wrote `warpui` / `warpui_core` — scene graph, text layout, font
rasterization — and its own scroll engine (`block_list_viewport.rs`, a
`ScrollState` over a `sum_tree`). Not adopted, for two reasons.

**It solves a problem neither client has.** Warp needed a scroll engine because
nothing beneath it had one. Flutter's list and the browser's scroll container
already provide momentum, rubber-band, keyboard paging and accessibility for
free. The quality of Warp's scrolling comes from owning the list, not from owning
the renderer, and both clients can own the list today.

**Its cost is the whole product.** The desktop renderer is React across the
kanban board, project sidebar, PR review and settings, cloned from
agent-orchestrator per DESIGN.md. A UI framework would mean rewriting all of it
for one pane.

Replacing the emulators is rejected for the same reason. `alacritty_terminal` is
a grid model with no renderer, in the Rust host rather than where the UI lives;
adopting it would require bridging every frame into the webview or writing a
Rust-side renderer. xterm.js stays on desktop, xterm.dart stays on mobile, and
both matter only in Raw mode.

### Error handling

- A harness with no registered deriver produces no events; the session opens in
  Raw mode and the toggle states plainly that blocks are unavailable for that
  harness. Absence is visible, never a silently empty list.
- An unknown event name is retained as unknown and rendered as a generic block
  rather than dropped, so a harness update degrades to less detail instead of a
  gap.
- A hook schema version newer than the daemon understands is recorded and
  surfaced; known fields still parse.
- A dropped or reconnected socket refetches the persisted event log by sequence.
- Malformed payloads are logged to the existing `hooks.log` sink and skipped.

### Testing

Backend: table tests per deriver mapping native hook names to the normalized
vocabulary including the unknown case; persistence bounds; mux frame encoding.

Mobile: unit tests for block assembly (correlation by `ToolUseID`, out-of-order
arrival, unknown events, truncation); widget tests for each block state; a test
pinning that Blocks mode does not join the terminal channel, since that is the
property the whole fix rests on. `flutter analyze` clean and `flutter test`
green are the gate, as for every change in this package.

Desktop: unit tests for the mux client's block-channel handling, and for block
assembly. `npm run frontend:typecheck` and `npm test` (vitest) are the gate. A
test pins that Blocks mode does not join the terminal channel, and a second pins
the arbitration consequence — desktop in Blocks with a phone in Raw leaves the
phone as the sole sizer.

Desktop viewport: tests for height estimation and correction (scroll position
preserved when a measured height replaces an estimate), append anchoring at the
bottom and while scrolled up, and the sticky-header exception for a block taller
than the viewport. These are the properties that decide whether scrolling feels
right, so they are pinned rather than eyeballed. Frame-time profiling under a
synthetic long session is part of the step, not an afterthought.

Shell blocks: table tests for mark parsing per shell, including a command whose
own output contains something resembling a mark.

**Shared fixtures.** Block assembly exists twice, in Dart and TypeScript, and the
two must not drift. One set of event-stream fixtures lives in the repo and both
suites assert against it. A behaviour added on one client without the other is a
failing test, not a silent divergence.

Native code is not covered by any of these gates; nothing here touches `ios/`,
`android/`, or a vendored package's platform code.

## Does this fix the problem?

Two goals, stated separately because they are different. Mobile: the phone shows
an unreadable terminal while the desktop must stay good. Desktop: the terminal
should reach parity with Warp's block terminal, including its scrolling.

**Yes, for agent sessions with hook coverage, and by construction rather than by
tuning.** A block list has no columns and no rows. It reflows to whatever width
the phone has, at whatever type size `AppSkin` specifies. There is no grid to
arbitrate, so there is no size to compromise on.

**The desktop is unaffected.** It already is: `largestGrid` skips non-primaries
whenever a primary has reported. In Blocks mode the phone additionally reports no
size at all, so the two clients stop competing even in the transient case where
the phone attaches first and the desktop arrives later.

**Both are good at the same time**, which was the requirement, because the two
clients no longer render the same artifact.

**Desktop reaches parity where parity is reachable.** Its grid was never
unreadable, so the win is different: agent turns and shell commands both become
blocks that can be scrolled, collapsed, copied, filtered and searched. Scrolling
matches Warp's because the requirements are matched item by item — virtualization,
height stability, append anchoring, sticky headers, block navigation, cross-block
selection and find — rather than assumed to come free.

The one deliberate divergence is rendering: Warp rasterizes glyphs on the GPU
because nothing beneath it composited. A browser composites, so the same
perceived smoothness is available provided the list does not re-render during
scroll. That is a profiling obligation, and it is the item most likely to be the
difference between parity and nearly-parity.

Stated limits, so this is not oversold:

- **Shell terminals are fixed only where the shell is supported.** Bash, zsh and
  fish get blocks through the injected bootstrap. Any other shell gets no marks
  and stays Raw, visibly.
- **Harnesses without hooks are not fixed.** `activitydispatch` registers eleven.
  The rest stay Raw and say so.
- **Raw mode is unchanged.** Switching to Raw returns the desktop-shaped grid and
  all of the original readability problem. Raw mode exists for when the real
  screen is what you need.
- **Fidelity is not the TUI.** Blocks show what the agent reported, not a
  pixel-accurate reproduction of its interface. Anything the agent renders but
  does not report — spinners, live token counters, its own layout — appears only
  in Raw.
- **Unverified.** Everything above is reasoning from source. No part of it has
  been run against a live daemon, from a phone or from the desktop app.

## Sequencing

1. Backend agent-event capture, vocabulary and persistence. No UI change.
2. Block channel on the mux, on the daemon and in both mux clients. Shared
   fixtures land here, before either UI consumes them.
3. **Mobile** block assembly, widgets and the toggle, defaulting off, then on.
   Mobile leads because its problem is the urgent one and its list is simpler.
4. **Desktop** block assembly and components, behind the toggle. Reuses steps 1
   and 2 wholesale.
5. **Desktop viewport**: virtualization, measured-height cache, append anchoring,
   sticky headers, block navigation. This is the parity work and the largest
   single piece; it is deliberately separate from step 4 so blocks are correct
   before they are fast.
6. Cross-block selection, find, and block actions (copy, re-run, filter).
7. **Shell blocks**: bootstrap injection, daemon-side mark parsing, republished on
   the block channel. Benefits both clients.
8. Transcript enrichment, per harness.
9. (Deferred) Actionable permissions, opt-in, as its own spec.

Steps 1 through 3 fix mobile and are the shortest path to a usable phone. Steps 4
through 7 are desktop parity. Steps 8 and 9 deepen both, and 9 carries its own
risk and its own review.

Mobile and desktop are sequenced rather than built in parallel so the event
vocabulary is settled against one real consumer before a second depends on it.

**Honest cost.** Steps 5, 6 and 7 are each larger than the original agent-blocks
work. Step 7 in particular adds a subsystem — shell bootstrap injection across
three shells plus an in-band mark parser — and could be cut without affecting
mobile at all. If the desktop bar has to move, cut from the end: 7, then 6.

## Scrolling

**In Blocks mode, scrolling is a native Flutter list scroll**: momentum, fling,
rubber-band and scrollbar, with no wheel reports, no tmux copy-mode and no
`WheelDivider` step conversion. `terminal_scroll.dart` continues to govern Raw
mode and is untouched.

This is the same reason Warp's scrolling feels natural. Warp owns its scrollback
— `block_list_viewport.rs` keeps its own `ScrollState` over a `sum_tree` of
blocks — and only forwards scroll to the running program when the alt screen is
active with mouse reporting (`should_intercept_scroll`, whose logic matches
`scrollActionFor`). Natural scrolling is a property of owning the content, not of
a better wheel handler.

Consequences, stated exactly:

- **Blocks mode, both clients: natural, once the viewport is built.** The platform
  supplies momentum, rubber-band and keyboard paging; virtualization, height
  stability, append anchoring and sticky headers are ours to build. See the
  Desktop parity target above for the full list — mobile needs the same
  properties from Flutter's list, with the same care.
- **Raw mode, both clients: unchanged, and unimprovable.** A full-screen TUI owns
  the screen and keeps no scrollback to scroll. The three existing paths — local
  buffer, SGR reports to tmux copy-mode, and page keys for keyboard-scroll
  harnesses — remain correct on both. `terminal_scroll.dart` and the wheel handler
  in `XtermTerminal.tsx` are untouched. Warp has the identical limitation in its
  alt-screen element, which is the proof that no renderer choice removes it.
- **The emulators are not the constraint.** Raw mode would scroll exactly as it
  does now under any emulator or any UI framework, because the limit is tmux and
  the TUI, not xterm.

## Input

**Blocks are output only. All input continues through the existing
`TerminalComposer` and `TerminalKeyRow`.** No per-block input field.

This follows Warp. `app/src/ai/blocklist/input_model.rs` defines a single
persistent input for the pane, carrying an `InputConfig { input_type, is_locked }`
where `input_type` is `Shell` or `AI`. The input is auto-detected from context,
lockable when the user turns autodetection off, and toggleable by hand
(`with_toggled_type`). Blocks never own an input.

Operator already has the equivalent surface on both clients, so nothing moves.
Mobile's composer and key row keep sole ownership of input in both modes, with
`send_route.dart` deciding where a send goes; desktop's existing pane input keeps
the same role. Neither gains a per-block field.

## Permission requests

**Rich and notifying, not actionable, on both clients.** A permission request
becomes a block that names the tool and its input and shows the session as
blocked. Acting on it means switching to Raw.

Warp does the same. `cli_agent_sessions/mod.rs` maps `PermissionRequest` to
`Blocked { message: summary }`, stashes `tool_name` and `tool_input_preview`,
and clears that state on `PermissionReplied`. It drives status, notifications
and the tab title; the user answers in the agent's own TUI. Operator could go
further later, because its hooks are its own; see Phase B below.

### Scope: Phase A only

**This spec implements Phase A.** Permission blocks are rich and notifying, at
Warp parity: the tool being requested, its input preview, and a blocked status.
They are **not** actionable. Answering means switching to Raw, and the block says
so plainly rather than leaving the user to discover it.

Phase A requires no change to `opr hooks` stdout behaviour, so the deliberate
guarantee in `claudecode/hooks.go:34` — that installing the hook never injects a
permission decision — is preserved exactly.

### Permanently rejected: synthesizing keystrokes

Sending the menu selection into the PTY reintroduces exactly the fragility this
design rejects — option ordering and labels are TUI surface. The repo already
guards against it: `claudecode.go:90` records that a permission-menu selection is
rejected by the empty-composer check that gates the guarded send loop, and that
guard exists so a blind send cannot land in a menu. Do not defeat it, in this
phase or any later one.

### Phase B — deferred, not part of this spec

Recorded so the option is not lost. `opr hooks` would block on a permission
decision routed from the daemon, and the mobile permission block would gain
approve and deny. It is a separate change with its own spec and its own review.

Constraints it would have to meet, all load-bearing:

- **Off by default, per project.** A session only waits on a remote decision when
  the user has enabled it.
- **Timeout falls through to the agent's own prompt.** It never approves and
  never denies on Operator's behalf. A sleeping phone or a dropped Tailscale link
  must degrade to the behaviour that exists today.
- **The wait is visible.** The daemon records that a hook is blocked on a remote
  decision, and both clients show it, so a stalled agent is never mysterious.
- **Only harnesses whose hook protocol documents a decision channel.** Others stay
  Phase A regardless of the setting.

The risk being managed is that a defect there becomes Operator approving tool
calls that the user did not approve. That is why any such change would default to
off and time out by falling through rather than allowing.

### Overlap with chat

This makes the terminal screen an approval surface, which chat's
`approval_card.dart` already is. They stay separate, consistent with the model
decision above: chat resolves approvals through the ACP driver
(`resolve_approval_params.dart`), while the terminal resolves them through the
hook. Different mechanisms, different modes, no shared path.

## Open questions

- Whether Phase B's opt-in belongs in project settings, session settings, or
  both.
- Which harnesses beyond Claude Code document a hook decision channel; this
  determines Phase B's reach and is unresearched.
