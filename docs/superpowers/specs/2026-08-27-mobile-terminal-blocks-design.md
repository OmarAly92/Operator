# Mobile terminal — agent blocks

Status: proposed
Date: 2026-08-27
Scope: `packages/mobile` terminal feature, `backend/internal` hook and stream path

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

## Approach

Render agent sessions on mobile as a **list of blocks** derived from structured
events the agent already emits, and keep the raw character grid as a separate
mode reachable by a toggle.

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
phone joining mid-session gets history rather than only what arrives next.
Bounds follow the pattern already established in `handoff_artifact.go`.

**Transport.** A new `agent` channel on the existing `/mux` socket carries event
frames, alongside `terminal`, `subscribe`, `sessions` and `system`. This reuses
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

Native code is not covered by either gate; nothing here touches `ios/`,
`android/`, or a vendored package's platform code.

## Does this fix the mobile problem?

The stated problem was that the phone shows an unreadable terminal while the
desktop must stay good.

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

Stated limits, so this is not oversold:

- **Shell terminals are not fixed.** A worktree shell has no agent hooks. It stays
  Raw. Fixing it needs shell integration — Warp's `Preexec` / `CommandFinished`
  approach — which is out of scope here and would be a separate spec.
- **Harnesses without hooks are not fixed.** `activitydispatch` registers eleven.
  The rest stay Raw and say so.
- **Raw mode is unchanged.** Switching to Raw returns the desktop-shaped grid and
  all of the original readability problem. Raw mode exists for when the real
  screen is what you need.
- **Fidelity is not the TUI.** Blocks show what the agent reported, not a
  pixel-accurate reproduction of its interface. Anything the agent renders but
  does not report — spinners, live token counters, its own layout — appears only
  in Raw.
- **Unverified on device.** Everything above is reasoning from source. No part of
  it has been run against a live daemon from a phone.

## Sequencing

1. Backend event capture, vocabulary and persistence. No UI change.
2. Mux `agent` channel and mobile models.
3. Block assembly logic and widgets, Blocks mode behind the toggle, defaulting off.
4. Default Blocks on for covered harnesses.
5. Transcript enrichment, per harness.
6. (Deferred) Actionable permissions, opt-in, as its own spec.

Steps 1–4 deliver the fix. Steps 5 and 6 deepen it, and 6 carries its own risk
and its own review.

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

- **Blocks mode: natural.** By construction, because the list is the app's own.
- **Raw mode: unchanged, and unimprovable.** A full-screen TUI owns the screen and
  keeps no scrollback to scroll. The three existing paths — local buffer, SGR
  reports to tmux copy-mode, and page keys for keyboard-scroll harnesses — remain
  correct. Warp has the identical limitation in its alt-screen element.
- **Desktop: out of scope.** This spec is mobile-only. On desktop
  (`XtermTerminal.tsx`) the normal-buffer case already scrolls naturally through
  xterm.js's own 5000-line scrollback; the mouse-tracking and keyboard-scroll
  cases are inherent to attaching a TUI and would need their own project. Nothing
  here changes desktop behaviour in any direction.

## Input

**Blocks are output only. All input continues through the existing
`TerminalComposer` and `TerminalKeyRow`.** No per-block input field.

This follows Warp. `app/src/ai/blocklist/input_model.rs` defines a single
persistent input for the pane, carrying an `InputConfig { input_type, is_locked }`
where `input_type` is `Shell` or `AI`. The input is auto-detected from context,
lockable when the user turns autodetection off, and toggleable by hand
(`with_toggled_type`). Blocks never own an input.

Operator already has the equivalent surface, so nothing moves. The composer and
key row keep sole ownership of input in both Blocks and Raw mode, and
`send_route.dart` continues to decide where a send goes.

## Permission requests

**Rich and notifying, not actionable.** A permission request becomes a block that
names the tool and its input and shows the session as blocked. Acting on it means
switching to Raw.

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
